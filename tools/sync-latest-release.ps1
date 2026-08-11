[CmdletBinding()]
param(
    [string] $SourceRepository = "JackyWilliam/DalamudActCompat",
    [string] $PluginMasterPath,
    [string] $ReleaseJsonPath,
    [switch] $Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($PluginMasterPath)) {
    $PluginMasterPath = Join-Path $PSScriptRoot "../pluginmaster.json"
}

function Set-WorkflowOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value" -Encoding utf8
    }
}

function Get-LatestRelease {
    if (-not [string]::IsNullOrWhiteSpace($ReleaseJsonPath)) {
        return Get-Content -LiteralPath $ReleaseJsonPath -Raw -Encoding utf8 |
            ConvertFrom-Json
    }

    $headers = @{
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "DalamudActCompatRepo-release-sync"
    }

    # The source is public, so the target repository token remains scoped only to target writes.
    return Invoke-RestMethod `
        -Uri "https://api.github.com/repos/$SourceRepository/releases/latest" `
        -Headers $headers
}

function ConvertTo-InstallerChangelog {
    param(
        [string] $Tag,
        [string] $Body
    )

    $items = [System.Collections.Generic.List[string]]::new()
    $capturingHighlights = $false
    $foundFirstSection = $false
    foreach ($line in ($Body -split "`r?`n")) {
        if ($line -match '^##\s+(.+?)\s*$') {
            if ($capturingHighlights) {
                break
            }

            # Release notes keep user-facing highlights in the first H2 section.
            if (-not $foundFirstSection) {
                $foundFirstSection = $true
                $capturingHighlights = $true
            }
            continue
        }

        if (-not $capturingHighlights -or $line -notmatch '^\s*[-*]\s+(.+?)\s*$') {
            continue
        }

        $item = $Matches[1].Trim()
        $item = [regex]::Replace($item, '\[([^\]]+)\]\([^)]+\)', '$1')
        $item = $item.Replace('`', '').Replace('**', '')
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $items.Add($item)
        }
    }

    $summary = if ($items.Count -gt 0) {
        $items -join ([string][char]0xFF1B)
    }
    else {
        "Release published; see GitHub Release for full notes."
    }
    $result = "$Tag $summary"
    if ($result.Length -gt 1200) {
        $result = $result.Substring(0, 1197) + '...'
    }
    return $result
}

$resolvedPluginMaster = (Resolve-Path -LiteralPath $PluginMasterPath).Path
$parsedPluginMaster = Get-Content -LiteralPath $resolvedPluginMaster -Raw -Encoding utf8 |
    ConvertFrom-Json
$entries = @($parsedPluginMaster | ForEach-Object { $_ })
if ($entries.Count -ne 1) {
    throw "Expected exactly one plugin entry in '$resolvedPluginMaster'."
}

$entry = $entries[0]
$release = Get-LatestRelease
if ($release.draft -or $release.prerelease) {
    throw "GitHub's latest release endpoint returned a draft or prerelease."
}

$tag = [string]$release.tag_name
if ($tag -notmatch '^v(?<version>\d+\.\d+\.\d+(?:\.\d+)?)$') {
    throw "Latest release tag '$tag' is not a supported numeric version."
}

$releaseVersion = $Matches.version
$versionParts = $releaseVersion.Split('.')
$assemblyVersion = if ($versionParts.Count -eq 3) {
    "$releaseVersion.0"
}
else {
    $releaseVersion
}
$latestVersion = [Version]$assemblyVersion
$currentVersion = [Version]([string]$entry.AssemblyVersion)

Set-WorkflowOutput -Name "tag" -Value $tag
Set-WorkflowOutput -Name "version" -Value $assemblyVersion
if (-not $Force -and $latestVersion -le $currentVersion) {
    Set-WorkflowOutput -Name "changed" -Value "false"
    Write-Host "PluginMaster is current at $currentVersion; latest release is $latestVersion."
    exit 0
}

$asset = @($release.assets) |
    Where-Object { $_.name -eq "DalamudActCompat.zip" -and [long]$_.size -gt 0 } |
    Select-Object -First 1
if ($null -eq $asset) {
    throw "Release '$tag' does not contain a non-empty DalamudActCompat.zip asset."
}

$downloadUri = [Uri]([string]$asset.browser_download_url)
$expectedPrefix = "https://github.com/$SourceRepository/releases/download/$tag/"
if ($downloadUri.Scheme -ne 'https' -or
    -not $downloadUri.AbsoluteUri.StartsWith($expectedPrefix, [StringComparison]::Ordinal)) {
    throw "Release asset URL '$downloadUri' does not belong to '$SourceRepository' tag '$tag'."
}

$publishedAt = [DateTimeOffset]::Parse([string]$release.published_at)
$entry.AssemblyVersion = $assemblyVersion
$entry.DownloadLinkInstall = $downloadUri.AbsoluteUri
$entry.DownloadLinkUpdate = $downloadUri.AbsoluteUri
# Manual force runs refresh the timestamp so they exercise the real commit/push path.
$entry.LastUpdate = if ($Force) {
    [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}
else {
    $publishedAt.ToUnixTimeMilliseconds()
}
$entry.Changelog = ConvertTo-InstallerChangelog -Tag $tag -Body ([string]$release.body)

$json = $entry | ConvertTo-Json -Depth 10
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    $resolvedPluginMaster,
    "[`n$json`n]`n",
    $utf8NoBom)

Set-WorkflowOutput -Name "changed" -Value "true"
Write-Host "Updated PluginMaster from $currentVersion to $latestVersion using $tag."
