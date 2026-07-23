# DalamudActCompatRepo

Custom Dalamud repository for Dalamud ACT Compat.

Users add this raw URL in Dalamud:

```text
https://raw.githubusercontent.com/raynording/DalamudActCompatRepo/main/pluginmaster.json
```

This repository should contain only the public repository metadata. The plugin source and release ZIP live in:

```text
https://github.com/raynording/DalamudActCompat
```

Current status: development preview metadata only. The referenced `v0.1.0` release ZIP still needs to be built and uploaded before users can install from this repository.

## Publish

After authenticating GitHub CLI on Windows:

```powershell
gh repo create raynording/DalamudActCompatRepo --public --source . --remote origin --push
```

Then verify:

```text
https://raw.githubusercontent.com/raynording/DalamudActCompatRepo/main/pluginmaster.json
```
