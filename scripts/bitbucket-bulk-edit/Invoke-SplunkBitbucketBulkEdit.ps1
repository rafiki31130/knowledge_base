<#
.SYNOPSIS
    Applique en masse des transformations regex sur des fichiers ciblés, dans les
    repos d'un projet Bitbucket Server / Data Center filtrés par regex. Pensé pour
    des applications Splunk (structure N1 : local/ bin/ default/ metadata/ ...).

.DESCRIPTION
    Workflow par repo : clone (shallow) -> branche (créée si absente) -> application
    des transformations -> commit -> push -> Pull Request.

    Deux modes :
      - Audit   : simule tout, affiche un AVANT/APRÈS par fichier, n'écrit/commit/push RIEN.
      - Execute : applique réellement, commit, push la branche, ouvre la PR.

    Authentification : aucun secret en paramètre. Le script récupère les identifiants
    via `git credential fill`, qui lit le Windows Credential Manager (helper manager
    /manager-core déjà utilisé par git pour le HTTPS). Le même couple user/PAT sert
    au clone/push ET aux appels REST (Basic auth).

    Transformations : liste de couples regex -> remplacement (moteur .NET).
    ATTENTION : la syntaxe des groupes est celle de .NET ($1, ${nom}), PAS celle de
    sed (\1). Les classes \d \w etc. sont identiques.

.PARAMETER BitbucketUrl
    URL de base de l'instance Bitbucket Server/DC. Ex : https://bitbucket.corp.example.

.PARAMETER Project
    Clé du projet Bitbucket (PROJECTKEY), pas le nom affiché.

.PARAMETER RepoRegex
    Regex .NET appliquée au slug ET au nom des repos pour sélectionner les cibles.
    Ex : '^splunk-app-' ou 'ta_.*linux'.

.PARAMETER TargetFiles
    Chemins / globs relatifs à la racine du repo, à traiter dans CHAQUE repo matché.
    Wildcards * et ? supportés. Ex : 'default/*.conf','local/inputs.conf','metadata/*.meta'.

.PARAMETER Replacements
    Tableau de hashtables décrivant les transformations, appliquées dans l'ordre :
        @(
            @{ Pattern = '^index\s*=.*$'; Replacement = 'index = prod_idx' },
            @{ Pattern = 'old_host';      Replacement = 'new_host'; IgnoreCase = $true }
        )
    Clés : Pattern (obligatoire), Replacement (obligatoire), IgnoreCase (def. $false),
           Multiline (def. $true ; ^ et $ s'ancrent par ligne).

.PARAMETER ReplacementsFile
    Alternative à -Replacements : chemin d'un fichier JSON contenant un tableau
    d'objets { "Pattern": "...", "Replacement": "...", "IgnoreCase": false }.

.PARAMETER BranchName
    Nom de la branche de travail. Créée à partir de la branche cible si absente,
    réutilisée si déjà présente sur origin.

.PARAMETER TargetBranch
    Branche de destination de la PR et base de la branche de travail.
    Si omis : la branche par défaut du repo (API) est utilisée.

.PARAMETER Mode
    Audit (défaut) ou Execute.

.PARAMETER CommitMessage
    Message de commit. Défaut : "chore: bulk edit via Invoke-SplunkBitbucketBulkEdit".

.PARAMETER PRTitle
    Titre de la PR. Défaut : le message de commit.

.PARAMETER PRDescription
    Corps de la PR. Défaut : récapitulatif auto des fichiers modifiés.

.PARAMETER WorkDir
    Dossier où cloner les repos. Défaut : sous-dossier horodaté dans $env:TEMP.

.PARAMETER KeepClones
    Conserve les clones après exécution (par défaut ils sont supprimés en fin de run,
    sauf en cas d'erreur où ils sont conservés pour inspection).

.PARAMETER MaxRepos
    Garde-fou : nombre maximum de repos à traiter (0 = illimité). Défaut : 0.

.EXAMPLE
    # Audit (dry-run) : voir l'avant/après sans rien modifier
    .\Invoke-SplunkBitbucketBulkEdit.ps1 -BitbucketUrl https://bitbucket.corp.example `
        -Project SPLK -RepoRegex '^ta_' `
        -TargetFiles 'default/*.conf','local/*.conf' `
        -Replacements @(@{ Pattern='^index\s*=.*$'; Replacement='index = prod_main' }) `
        -BranchName chore/reindex -Mode Audit

.EXAMPLE
    # Exécution réelle : applique, commit, push, ouvre la PR
    .\Invoke-SplunkBitbucketBulkEdit.ps1 -BitbucketUrl https://bitbucket.corp.example `
        -Project SPLK -RepoRegex '^ta_' `
        -TargetFiles 'default/*.conf' `
        -ReplacementsFile .\replacements.json `
        -BranchName chore/reindex -TargetBranch master -Mode Execute

.NOTES
    - Idempotent : aucun commit/PR si le repo ne change pas.
    - Spécifique Splunk : si une modif touche default/<f> alors qu'un local/<f> existe,
      un avertissement signale que local surcharge default (modif potentiellement sans effet).
    - Préserve l'encodage et les fins de ligne d'origine de chaque fichier.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]   $BitbucketUrl,
    [Parameter(Mandatory)] [string]   $Project,
    [Parameter(Mandatory)] [string]   $RepoRegex,
    [Parameter(Mandatory)] [string[]] $TargetFiles,

    [hashtable[]] $Replacements,
    [string]      $ReplacementsFile,

    [Parameter(Mandatory)] [string]   $BranchName,
    [string]      $TargetBranch,

    [ValidateSet('Audit','Execute')]
    [string]      $Mode = 'Audit',

    [string]      $CommitMessage = 'chore: bulk edit via Invoke-SplunkBitbucketBulkEdit',
    [string]      $PRTitle,
    [string]      $PRDescription,

    [string]      $WorkDir,
    [switch]      $KeepClones,
    [int]         $MaxRepos = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# TLS 1.2 pour les instances Bitbucket derrière reverse-proxy moderne (Win PS 5.1).
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

#region ----------------------------------------------------------------- Helpers

function Write-Section { param([string]$Text) Write-Host ""; Write-Host "==== $Text ====" -ForegroundColor Cyan }
function Write-Info    { param([string]$Text) Write-Host "  $Text" -ForegroundColor Gray }
function Write-Ok      { param([string]$Text) Write-Host "  $Text" -ForegroundColor Green }
function Write-Warn    { param([string]$Text) Write-Host "  $Text" -ForegroundColor Yellow }
function Write-Err     { param([string]$Text) Write-Host "  $Text" -ForegroundColor Red }

function Assert-GitAvailable {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git introuvable dans le PATH. Installe Git for Windows (inclut le helper manager-core)."
    }
}

# Récupère user/password depuis le Windows Credential Manager via `git credential fill`.
function Get-GitCredential {
    param([Parameter(Mandatory)][uri]$Url)
    $query = "protocol=$($Url.Scheme)`nhost=$($Url.Host)`n"
    if ($Url.AbsolutePath -and $Url.AbsolutePath -ne '/') {
        $query += "path=$($Url.AbsolutePath.TrimStart('/'))`n"
    }
    $query += "`n"
    # GIT_TERMINAL_PROMPT=0 : pas d'invite interactive ; on veut un secret DÉJÀ stocké.
    $prev = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        $out = $query | & git credential fill 2>$null
    } finally {
        $env:GIT_TERMINAL_PROMPT = $prev
    }
    $u = $null; $p = $null
    foreach ($line in $out) {
        if ($line -like 'username=*') { $u = $line.Substring(9) }
        elseif ($line -like 'password=*') { $p = $line.Substring(9) }
    }
    if ([string]::IsNullOrEmpty($u) -or [string]::IsNullOrEmpty($p)) {
        throw ("Aucun identifiant trouvé dans le Windows Credential Manager pour {0}://{1}. " -f $Url.Scheme,$Url.Host) +
              "Connecte-toi une fois en HTTPS (git clone) pour que git mémorise le PAT, ou ajoute-le via le Gestionnaire d'identification Windows."
    }
    return [pscustomobject]@{ Username = $u; Password = $p }
}

function New-BasicAuthHeader {
    param([Parameter(Mandatory)]$Credential)
    $pair = "$($Credential.Username):$($Credential.Password)"
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    return @{ Authorization = "Basic $b64" }
}

function Invoke-BbApi {
    param(
        [Parameter(Mandatory)][string]$Path,        # ex: /rest/api/1.0/projects/KEY/repos
        [hashtable]$Headers,
        [string]$Method = 'GET',
        [hashtable]$Query,
        $Body
    )
    $uri = "$($script:BaseUrl)$Path"
    if ($Query) {
        $pairs = $Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))" }
        $uri += '?' + ($pairs -join '&')
    }
    $params = @{ Uri = $uri; Method = $Method; Headers = $Headers; ContentType = 'application/json' }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }
    return Invoke-RestMethod @params
}

# Liste paginée des repos d'un projet.
function Get-BbRepos {
    param([hashtable]$Headers)
    $all = @()
    $start = 0
    do {
        $resp = Invoke-BbApi -Path "/rest/api/1.0/projects/$Project/repos" -Headers $Headers `
                             -Query @{ limit = 100; start = $start }
        if ($resp.values) { $all += $resp.values }
        $isLast = $resp.isLastPage
        if (-not $isLast) { $start = $resp.nextPageStart }
    } while (-not $isLast)
    return $all
}

function Get-BbDefaultBranch {
    param([hashtable]$Headers, [string]$RepoSlug)
    try {
        $b = Invoke-BbApi -Path "/rest/api/1.0/projects/$Project/repos/$RepoSlug/branches/default" -Headers $Headers
        return $b.displayId
    } catch {
        return $null
    }
}

function New-BbPullRequest {
    param(
        [hashtable]$Headers, [string]$RepoSlug,
        [string]$From, [string]$To, [string]$Title, [string]$Description
    )
    $body = @{
        title  = $Title
        description = $Description
        state  = 'OPEN'
        open   = $true
        closed = $false
        fromRef = @{ id = "refs/heads/$From"; repository = @{ slug = $RepoSlug; project = @{ key = $Project } } }
        toRef   = @{ id = "refs/heads/$To";   repository = @{ slug = $RepoSlug; project = @{ key = $Project } } }
    }
    return Invoke-BbApi -Path "/rest/api/1.0/projects/$Project/repos/$RepoSlug/pull-requests" `
                        -Headers $Headers -Method POST -Body $body
}

# Détecte l'encodage par sniff du BOM ; défaut UTF-8 sans BOM (cas Splunk le plus courant).
function Get-FileTextAndEncoding {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $enc = $null
    if     ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = New-Object System.Text.UTF8Encoding($true) }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $enc = [System.Text.Encoding]::Unicode }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $enc = [System.Text.Encoding]::BigEndianUnicode }
    else { $enc = New-Object System.Text.UTF8Encoding($false) }
    $text = $enc.GetString($bytes)
    # Retire un éventuel BOM résiduel en tête de la chaîne décodée.
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return [pscustomobject]@{ Text = $text; Encoding = $enc }
}

function Set-FileText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)]$Encoding)
    [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

# Applique la liste de transformations sur un texte ; renvoie le texte modifié.
function Convert-Text {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][array]$Rules)
    $result = $Text
    foreach ($rule in $Rules) {
        $opts = [System.Text.RegularExpressions.RegexOptions]::None
        if ($rule.Multiline)  { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }
        if ($rule.IgnoreCase) { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        $rx = New-Object System.Text.RegularExpressions.Regex($rule.Pattern, $opts)
        $result = $rx.Replace($result, $rule.Replacement)
    }
    return $result
}

# Diff ligne à ligne lisible (numéro de ligne, - avant / + après). Sans dépendance externe.
function Show-LineDiff {
    param([string]$Before, [string]$After, [int]$Context = 0)
    $b = $Before -split "`r?`n"
    $a = $After  -split "`r?`n"
    $max = [Math]::Max($b.Count, $a.Count)
    $shown = $false
    for ($i = 0; $i -lt $max; $i++) {
        $ol = if ($i -lt $b.Count) { $b[$i] } else { $null }
        $nl = if ($i -lt $a.Count) { $a[$i] } else { $null }
        if ($ol -ne $nl) {
            $shown = $true
            if ($null -ne $ol) { Write-Host ("    {0,5} - {1}" -f ($i+1), $ol) -ForegroundColor Red }
            if ($null -ne $nl) { Write-Host ("    {0,5} + {1}" -f ($i+1), $nl) -ForegroundColor Green }
        }
    }
    if (-not $shown) { Write-Info "    (contenu identique après normalisation des lignes)" }
}

# Résout les fichiers d'un repo à partir des globs TargetFiles (relatifs racine repo).
function Resolve-TargetFiles {
    param([string]$RepoRoot, [string[]]$Patterns)
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($pat in $Patterns) {
        $norm = $pat -replace '/', '\'
        $full = Join-Path $RepoRoot $norm
        $items = Get-ChildItem -Path $full -File -ErrorAction SilentlyContinue
        foreach ($it in $items) {
            if (-not $files.Contains($it.FullName)) { $files.Add($it.FullName) }
        }
    }
    return $files
}

# Avertissement Splunk : modif dans default/<f> alors que local/<f> existe (surcharge).
function Test-SplunkOverride {
    param([string]$RepoRoot, [string]$ChangedFullPath)
    $rel = $ChangedFullPath.Substring($RepoRoot.Length).TrimStart('\','/') -replace '\\','/'
    if ($rel -like 'default/*') {
        $localEquiv = Join-Path $RepoRoot ($rel -replace '^default/','local/').Replace('/','\')
        if (Test-Path -LiteralPath $localEquiv) {
            return ($rel -replace '^default/','local/')
        }
    }
    return $null
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$GitArgs, [string]$WorkingDir)
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($WorkingDir) { $out = & git -C $WorkingDir @GitArgs 2>&1 }
        else             { $out = & git @GitArgs 2>&1 }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prevPref }
    return [pscustomobject]@{ ExitCode = $code; Output = ($out -join "`n") }
}

#endregion --------------------------------------------------------------- Helpers

# ----------------------------------------------------------------------- Préparation
Assert-GitAvailable

$script:BaseUrl = $BitbucketUrl.TrimEnd('/')
$baseUri = [uri]$script:BaseUrl

# Construit la liste de règles normalisée (depuis -Replacements ou -ReplacementsFile).
$rules = @()
if ($ReplacementsFile) {
    if (-not (Test-Path -LiteralPath $ReplacementsFile)) { throw "ReplacementsFile introuvable : $ReplacementsFile" }
    $rules = Get-Content -LiteralPath $ReplacementsFile -Raw | ConvertFrom-Json
} elseif ($Replacements) {
    $rules = $Replacements
} else {
    throw "Fournis -Replacements ou -ReplacementsFile."
}

# Normalise chaque règle (valeurs par défaut, validation). On convertit d'abord
# tout en hashtable : l'accès à une clé absente y renvoie $null sans lever sous
# StrictMode, contrairement à une propriété absente sur un PSCustomObject (cas JSON).
$normRules = foreach ($r in $rules) {
    $ht = @{}
    if ($r -is [hashtable]) { $ht = $r }
    else { $r.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value } }

    $pattern = $ht['Pattern']
    if ([string]::IsNullOrEmpty($pattern)) { throw "Une règle de remplacement n'a pas de 'Pattern'." }
    $replacement = if ($null -ne $ht['Replacement']) { [string]$ht['Replacement'] } else { '' }

    [pscustomobject]@{
        Pattern     = [string]$pattern
        Replacement = $replacement
        IgnoreCase  = [bool]$ht['IgnoreCase']
        Multiline   = if ($null -ne $ht['Multiline']) { [bool]$ht['Multiline'] } else { $true }
    }
}

if (-not $PRTitle) { $PRTitle = $CommitMessage }

if (-not $WorkDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $WorkDir = Join-Path $env:TEMP "bb-bulk-edit-$stamp"
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

Write-Section "Authentification"
$cred    = Get-GitCredential -Url $baseUri
$headers = New-BasicAuthHeader -Credential $cred
Write-Ok "Identifiant récupéré depuis le Credential Manager : utilisateur '$($cred.Username)'"

# Validation du compte + des droits via un appel REST léger.
try {
    Invoke-BbApi -Path "/rest/api/1.0/projects/$Project" -Headers $headers | Out-Null
    Write-Ok "Projet '$Project' accessible."
} catch {
    throw "Échec d'accès au projet '$Project' : $($_.Exception.Message). Vérifie l'URL, la clé projet et les droits du PAT."
}

Write-Section "Sélection des repos (regex : $RepoRegex)"
$repos = Get-BbRepos -Headers $headers
$rx = [regex]$RepoRegex
$targets = $repos | Where-Object { $rx.IsMatch($_.slug) -or $rx.IsMatch($_.name) } | Sort-Object slug
if ($MaxRepos -gt 0 -and $targets.Count -gt $MaxRepos) {
    Write-Warn "Garde-fou MaxRepos=$MaxRepos : $($targets.Count) repos matchés, troncature aux $MaxRepos premiers."
    $targets = $targets | Select-Object -First $MaxRepos
}
Write-Ok "$($targets.Count) repo(s) sélectionné(s) sur $($repos.Count) du projet."
$targets | ForEach-Object { Write-Info "- $($_.slug)" }
if ($targets.Count -eq 0) { Write-Warn "Aucun repo. Fin."; return }

Write-Host ""
Write-Host ("MODE : {0}" -f $Mode.ToUpper()) -ForegroundColor Magenta
if ($Mode -eq 'Audit') { Write-Warn "AUDIT - aucune écriture, aucun commit, aucun push, aucune PR." }

# ----------------------------------------------------------------------- Traitement
$report   = New-Object System.Collections.Generic.List[object]
$hadError = $false

foreach ($repo in $targets) {
    $slug = $repo.slug
    Write-Section "Repo : $slug"
    $repoEntry = [ordered]@{
        Repo = $slug; FilesScanned = 0; FilesChanged = 0; Status = ''; PrUrl = ''; Detail = ''
    }

    try {
        $cloneUrl = ($repo.links.clone | Where-Object { $_.name -eq 'http' } | Select-Object -First 1).href
        if (-not $cloneUrl) { throw "Pas d'URL de clone HTTP exposée pour ce repo." }

        $effectiveTarget = $TargetBranch
        if (-not $effectiveTarget) {
            $effectiveTarget = Get-BbDefaultBranch -Headers $headers -RepoSlug $slug
            if (-not $effectiveTarget) { throw "Impossible de déterminer la branche par défaut ; précise -TargetBranch." }
        }
        Write-Info "Branche cible (PR) : $effectiveTarget"

        # La branche de travail existe-t-elle déjà sur origin ?
        $ls = Invoke-Git -GitArgs @('ls-remote','--heads',$cloneUrl,$BranchName)
        if ($ls.ExitCode -ne 0) { throw "ls-remote a échoué : $($ls.Output)" }
        $branchExistsRemote = -not [string]::IsNullOrWhiteSpace($ls.Output)
        $baseBranch = if ($branchExistsRemote) { $BranchName } else { $effectiveTarget }
        if ($branchExistsRemote) { Write-Info "Branche '$BranchName' déjà présente sur origin : réutilisée." }

        # Clone shallow de la branche de base.
        $dest = Join-Path $WorkDir $slug
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        $clone = Invoke-Git -GitArgs @('clone','--depth','1','--no-tags','--branch',$baseBranch,$cloneUrl,$dest)
        if ($clone.ExitCode -ne 0) { throw "git clone a échoué : $($clone.Output)" }

        # Crée la branche de travail si elle n'existait pas.
        if (-not $branchExistsRemote) {
            $co = Invoke-Git -WorkingDir $dest -GitArgs @('checkout','-b',$BranchName)
            if ($co.ExitCode -ne 0) { throw "Création de branche a échoué : $($co.Output)" }
            Write-Info "Branche '$BranchName' créée depuis '$effectiveTarget'."
        }

        # Résout et traite les fichiers.
        $files = Resolve-TargetFiles -RepoRoot $dest -Patterns $TargetFiles
        $repoEntry.FilesScanned = $files.Count
        if ($files.Count -eq 0) { Write-Warn "Aucun fichier ne matche $($TargetFiles -join ', ')." }

        $changedFiles = @()
        foreach ($file in $files) {
            $rel = $file.Substring($dest.Length).TrimStart('\','/') -replace '\\','/'
            $fi  = Get-FileTextAndEncoding -Path $file
            $after = Convert-Text -Text $fi.Text -Rules $normRules

            if ($after -eq $fi.Text) {
                Write-Info "= $rel (inchangé)"
                continue
            }

            $changedFiles += $rel
            Write-Host "  ~ $rel" -ForegroundColor Yellow

            # Avertissement surcharge Splunk default/ vs local/.
            $ovr = Test-SplunkOverride -RepoRoot $dest -ChangedFullPath $file
            if ($ovr) { Write-Warn "    ! '$rel' est surchargé par '$ovr' : la modif peut être sans effet à l'exécution Splunk." }

            Write-Host "    --- AVANT / APRÈS ---" -ForegroundColor DarkGray
            Show-LineDiff -Before $fi.Text -After $after

            if ($Mode -eq 'Execute') {
                Set-FileText -Path $file -Text $after -Encoding $fi.Encoding
            }
        }

        $repoEntry.FilesChanged = $changedFiles.Count

        if ($changedFiles.Count -eq 0) {
            $repoEntry.Status = 'no-change'
            Write-Info "Aucun changement -> ni commit ni PR (idempotent)."
            $report.Add([pscustomobject]$repoEntry); continue
        }

        if ($Mode -eq 'Audit') {
            $repoEntry.Status = 'audited'
            $repoEntry.Detail = "$($changedFiles.Count) fichier(s) seraient modifiés"
            $report.Add([pscustomobject]$repoEntry); continue
        }

        # --- Execute : commit + push + PR ---
        $addArgs = @('add','--') + $changedFiles
        Invoke-Git -WorkingDir $dest -GitArgs $addArgs | Out-Null
        $commit = Invoke-Git -WorkingDir $dest -GitArgs @('commit','-m',$CommitMessage)
        if ($commit.ExitCode -ne 0) { throw "git commit a échoué : $($commit.Output)" }

        $push = Invoke-Git -WorkingDir $dest -GitArgs @('push','origin',$BranchName)
        if ($push.ExitCode -ne 0) { throw "git push a échoué : $($push.Output)" }
        Write-Ok "Branche '$BranchName' poussée."

        # PR (gère le cas 'déjà existante' renvoyé par Bitbucket en 409).
        $prDesc = if ($PRDescription) { $PRDescription } else { "Modifications automatiques sur :`n" + (($changedFiles | ForEach-Object { "- $_" }) -join "`n") }
        try {
            $pr = New-BbPullRequest -Headers $headers -RepoSlug $slug -From $BranchName -To $effectiveTarget -Title $PRTitle -Description $prDesc
            $repoEntry.PrUrl  = ($pr.links.self | Select-Object -First 1).href
            $repoEntry.Status = 'pr-created'
            Write-Ok "PR créée : $($repoEntry.PrUrl)"
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match '409' -or $msg -match 'already') {
                $repoEntry.Status = 'pushed-pr-exists'
                Write-Warn "Push OK ; une PR existe déjà pour cette branche (pas de doublon créé)."
            } else { throw }
        }
        $report.Add([pscustomobject]$repoEntry)

    } catch {
        $hadError = $true
        $repoEntry.Status = 'ERROR'
        $repoEntry.Detail = $_.Exception.Message
        Write-Err "Erreur sur '$slug' : $($_.Exception.Message)"
        $report.Add([pscustomobject]$repoEntry)
    }
}

# ----------------------------------------------------------------------- Synthèse
Write-Section "Synthèse ($Mode)"
$report | Format-Table -AutoSize Repo, FilesScanned, FilesChanged, Status, PrUrl

# Nettoyage des clones (conservés en cas d'erreur ou si -KeepClones).
if ($KeepClones) {
    Write-Info "Clones conservés dans : $WorkDir"
} elseif ($hadError) {
    Write-Warn "Des erreurs sont survenues : clones conservés pour inspection dans $WorkDir"
} else {
    Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
    Write-Info "Clones temporaires supprimés."
}

if ($Mode -eq 'Audit') {
    Write-Host ""
    Write-Host "Audit terminé. Rien n'a été modifié. Relance avec -Mode Execute pour appliquer." -ForegroundColor Magenta
}

if ($hadError) { exit 1 }
