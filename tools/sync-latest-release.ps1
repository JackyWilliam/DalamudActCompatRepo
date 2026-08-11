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
        "User-Agent" = "DalamudActCompatRepo-release-sync"
    }
    $releaseBaseUri = "https://github.com/$SourceRepository/releases"
    $latestResponse = Invoke-WebRequest `
        -Uri "$releaseBaseUri/latest" `
        -Headers $headers `
        -Method Head `
        -MaximumRedirection 10 `
        -UseBasicParsing

    $baseResponse = $latestResponse.BaseResponse
    $responseUriProperty = $baseResponse.PSObject.Properties['ResponseUri']
    $requestMessageProperty = $baseResponse.PSObject.Properties['RequestMessage']
    $latestUri = if ($null -ne $responseUriProperty) {
        [Uri]$responseUriProperty.Value
    }
    elseif ($null -ne $requestMessageProperty) {
        [Uri]$requestMessageProperty.Value.RequestUri
    }
    else {
        throw "Unable to determine the final stable release URL."
    }

    # GitHub's /latest redirect excludes prereleases without requiring cross-repository API access.
    $tagPrefix = "$releaseBaseUri/tag/"
    $latestPageUri = $latestUri.GetLeftPart([UriPartial]::Path)
    if (-not $latestPageUri.StartsWith($tagPrefix, [StringComparison]::Ordinal)) {
        throw "Latest release URL '$latestPageUri' does not belong to '$SourceRepository'."
    }
    $tag = [Uri]::UnescapeDataString($latestPageUri.Substring($tagPrefix.Length)).Trim('/')

    $feedResponse = Invoke-WebRequest `
        -Uri "$releaseBaseUri.atom" `
        -Headers $headers `
        -UseBasicParsing
    $feed = [xml]$feedResponse.Content
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($feed.NameTable)
    $namespaceManager.AddNamespace('atom', 'http://www.w3.org/2005/Atom')

    $matchingEntry = $null
    foreach ($feedEntry in $feed.SelectNodes('/atom:feed/atom:entry', $namespaceManager)) {
        $linkNode = $feedEntry.SelectSingleNode("atom:link[@rel='alternate']", $namespaceManager)
        if ($null -ne $linkNode -and
            $linkNode.GetAttribute('href').TrimEnd('/') -eq $latestPageUri.TrimEnd('/')) {
            $matchingEntry = $feedEntry
            break
        }
    }
    if ($null -eq $matchingEntry) {
        throw "Stable release '$tag' was not found in the public release feed."
    }

    $updatedNode = $matchingEntry.SelectSingleNode('atom:updated', $namespaceManager)
    $contentNode = $matchingEntry.SelectSingleNode('atom:content', $namespaceManager)
    if ($null -eq $updatedNode -or $null -eq $contentNode) {
        throw "Release feed entry '$tag' is missing its timestamp or notes."
    }

    $releaseHtml = [Net.WebUtility]::HtmlDecode($contentNode.InnerText)
    $firstSection = [regex]::Match(
        $releaseHtml,
        '(?is)<h2\b[^>]*>.*?</h2>(?<section>.*?)(?=<h2\b|$)')
    $sectionHtml = if ($firstSection.Success) {
        $firstSection.Groups['section'].Value
    }
    else {
        $releaseHtml
    }
    $markdownLines = [System.Collections.Generic.List[string]]::new()
    $markdownLines.Add('## Release highlights')
    foreach ($listItem in [regex]::Matches($sectionHtml, '(?is)<li\b[^>]*>(?<item>.*?)</li>')) {
        $plainText = [regex]::Replace($listItem.Groups['item'].Value, '<[^>]+>', '')
        $plainText = [Net.WebUtility]::HtmlDecode($plainText)
        $plainText = [regex]::Replace($plainText, '\s+', ' ').Trim()
        if (-not [string]::IsNullOrWhiteSpace($plainText)) {
            $markdownLines.Add("- $plainText")
        }
    }

    $assetUrl = "$releaseBaseUri/download/$tag/DalamudActCompat.zip"
    $assetResponse = Invoke-WebRequest `
        -Uri $assetUrl `
        -Headers $headers `
        -Method Head `
        -MaximumRedirection 10 `
        -UseBasicParsing
    $contentLengthHeader = $assetResponse.Headers['Content-Length']
    $contentLengthText = [string](@($contentLengthHeader)[0])
    $assetSize = 0L
    if (-not [long]::TryParse($contentLengthText, [ref]$assetSize) -or $assetSize -le 0) {
        throw "Release '$tag' has no verifiably non-empty DalamudActCompat.zip asset."
    }

    return [pscustomobject]@{
        draft        = $false
        prerelease   = $false
        tag_name     = $tag
        published_at = $updatedNode.InnerText
        body          = $markdownLines -join "`n"
        assets        = @(
            [pscustomobject]@{
                name                 = 'DalamudActCompat.zip'
                size                 = $assetSize
                browser_download_url = $assetUrl
            }
        )
    }
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
