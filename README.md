# susfs4ksu

GitHub mirror and development entry point for **SUSFS v2.3.0**.

## Upstream

Official upstream:

- GitLab: `simonpunk/susfs4ksu`
- License: GNU GPL v3.0 or later

This repository preserves upstream Git history and commit object IDs on mirrored branches.

## Branch layout

`main` is reserved for GitHub-side maintenance and synchronization metadata.

The actual upstream source is mirrored without rewriting history, including:

- `gki-android12-5.10`
- `gki-android12-5.10-dev`
- `gki-android13-5.10`
- `gki-android13-5.15`
- `gki-android13-5.15-dev`
- `gki-android14-5.15`
- `gki-android14-6.1`
- `gki-android14-6.1-dev`
- `gki-android15-6.6`
- `gki-android15-6.6-dev`
- `gki-android16-6.12`
- `gki-android16-6.12-dev`
- legacy kernel branches and other upstream branches

The current maintained GKI branches report:

```text
SUSFS_VERSION "v2.3.0"
version=v2.3.0
versionCode=202000
```

## Synchronization

GitHub Actions mirrors official GitLab branches and tags every 6 hours and can also be triggered manually.

Upstream mirror branches should remain untouched. Custom development should be done in separate downstream branches.
