$ErrorActionPreference = 'Stop'
$folder = Join-Path ([IO.Path]::GetTempPath()) ('DACT-Repo-Sync-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $folder | Out-Null
$manifest = Join-Path $folder 'pluginmaster.json'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../pluginmaster.json') -Destination $manifest
$entries = @(Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json)
$repair = @($entries | Where-Object InternalName -eq 'DalamudActCompatRepair')
if ($repair.Count -ne 1) { throw 'Repair fixture missing.' }
$before = ConvertTo-Json -InputObject $repair[0] -Depth 20 -Compress
$release = Join-Path $folder 'release.json'
@{
    tag_name='v0.4.4.1';draft=$false;prerelease=$false;published_at='2026-09-18T05:23:01Z';
    body="## 更新`n- 测试更新";
    assets=@(@{name='DalamudActCompat-core.zip';size=123;browser_download_url='https://github.com/JackyWilliam/DalamudActCompat/releases/download/v0.4.4.1/DalamudActCompat-core.zip'})
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $release -Encoding utf8
& (Join-Path $PSScriptRoot 'sync-latest-release.ps1') -PluginMasterPath $manifest -ReleaseJsonPath $release -Force
$after = @(Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json)
if ($after.Count -ne 2 -or @($after | Where-Object InternalName -eq 'DalamudActCompat')[0].AssemblyVersion -ne '0.4.4.1') { throw 'Main update failed.' }
$afterRepair = @($after | Where-Object InternalName -eq 'DalamudActCompatRepair')[0]
if ((ConvertTo-Json -InputObject $afterRepair -Depth 20 -Compress) -ne $before) { throw 'Main update changed the repair entry.' }
$hash = (Get-FileHash -LiteralPath $manifest).Hash
& (Join-Path $PSScriptRoot 'sync-latest-release.ps1') -PluginMasterPath $manifest -ReleaseJsonPath $release
if ((Get-FileHash -LiteralPath $manifest).Hash -ne $hash) { throw 'Already-current sync rewrote metadata.' }
Write-Output 'PASS: main update and repeated sync preserve independent repair plugin metadata.'
