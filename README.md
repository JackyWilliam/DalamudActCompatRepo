# DalamudActCompatRepo

Custom Dalamud repository for Dalamud ACT Compat.

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
it validates the `DalamudActCompat.zip` asset, derives the installer changelog
from the release highlights, and commits the updated `pluginmaster.json` to this
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
