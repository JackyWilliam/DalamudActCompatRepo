# DalamudActCompatRepo

Custom Dalamud repository for Dalamud ACT Compat.

Users add this raw URL in Dalamud:

```text
https://raw.githubusercontent.com/JackyWilliam/DalamudActCompatRepo/main/pluginmaster.json
```

This repository should contain only the public repository metadata. The plugin source and release ZIP live in:

```text
https://github.com/JackyWilliam/DalamudActCompat
```

The metadata on `main` points to the latest published release ZIP, so existing users keep the same repository URL across updates.

## Publish

After authenticating GitHub CLI on Windows:

```powershell
gh repo create JackyWilliam/DalamudActCompatRepo --public --source . --remote origin --push
```

Then verify:

```text
https://raw.githubusercontent.com/JackyWilliam/DalamudActCompatRepo/main/pluginmaster.json
```
