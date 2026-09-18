# DalamudActCompatRepo

Custom Dalamud repository for Dalamud ACT Compat.

此仓库同时提供独立卫月插件 **DACT 修复工具**。安装了错误编号 4.4.0.0 的用户可在 `/xlplugins` 搜索安装，停用 DACT 主插件后点击修复，完成后重启一次游戏并重新启用 DACT。工具保留配置并备份旧安装；[详细说明](https://github.com/JackyWilliam/DalamudActCompat/tree/main/tools/DACT.Repair)。它是游戏内插件，不需要运行外部软件。

Users add this raw URL in Dalamud:

```text
https://raw.githubusercontent.com/JackyWilliam/DalamudActCompatRepo/main/pluginmaster.json
```

This repository contains the public repository metadata and its release-sync automation. The plugin source and release ZIP live in:

```text
https://github.com/JackyWilliam/DalamudActCompat
```

The metadata on `main` points to the latest published release ZIP, so existing users keep the same repository URL across updates.

## Automatic synchronization

`.github/workflows/sync-latest-release.yml` checks the source repository's latest
stable GitHub Release every 15 minutes. When it finds a newer numeric release,
it validates the preferred `DalamudActCompat-core.zip` asset (with the legacy
`DalamudActCompat.zip` name retained as a fallback), derives the installer changelog
from the release highlights, preserves other plugin entries, and commits the updated `pluginmaster.json` to this
repository with its own scoped `GITHUB_TOKEN`.

No personal access token or cross-repository secret is required. A manual run is
also available under GitHub Actions; select `force` to rewrite and verify the
current release metadata even when its version has not changed.

For local validation:

```powershell
./tools/sync-latest-release.ps1
```

Then verify:

```text
https://raw.githubusercontent.com/JackyWilliam/DalamudActCompatRepo/main/pluginmaster.json
```
