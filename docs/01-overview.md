# Overview

This repository is organized around image directories. Each top-level image directory contains one `Dockerfile` and all files needed by that image.

Example:

```text
docker-images/
  build_and_push.sh
  docker-builder-secrets.example
  README.md
  docs/
  scripts/
    start_aws_builder.sh
  .github/
    workflows/
      build-and-push.yml
    promotions/
      .gitkeep
  basetools/
    Dockerfile
    pixi.toml
    scripts/
      install-extra-tools.sh
    configs/
      tool-settings.yaml
```

## Build Locations

Local builder:

```text
Your current machine builds and runs the image using Docker or Podman.
```

SSH builder:

```text
The local image directory is streamed over SSH to a remote builder, such as AWS EC2.
The remote builder runs Docker or Podman.
No Git clone is required on the remote host.
```

GitHub Actions builder:

```text
Pushing changes under an image directory triggers GitHub Actions.
GitHub builds the image and pushes it to GHCR.
```

Fast-track promotion:

```text
You build and push externally from local/AWS.
The script emits a promotion manifest.
You commit the image files plus the manifest.
GitHub verifies the context hash.
GitHub skips docker build and retags the already pushed image.
```

## Trigger Rule

Any committed change under an image directory can trigger that image build.

Examples that trigger `basetools`:

```text
basetools/Dockerfile
basetools/pixi.toml
basetools/scripts/install.sh
basetools/configs/tool.yaml
basetools/docs/notes.md
```

Examples that do not build an image unless the top-level folder has a `Dockerfile`:

```text
README.md
docs/01-overview.md
scripts/start_aws_builder.sh
docker-builder-secrets.example
```

Technically, the workflow can start for some repo-level changes, but the build matrix skips any top-level folder that does not contain a `Dockerfile`.

## Promotion Rule

If both the image directory and `.github/promotions/<image>.json` change in the same push, GitHub Actions promotes the pre-built image instead of rebuilding.

If only the image directory changes, GitHub Actions builds in GitHub.

## Recommended Daily Flow

For simple changes where GitHub cloud build is fine:

```bash
git add basetools
git commit -m "Update basetools image"
git push origin main
```

For heavy changes you tested on AWS:

```bash
./build_and_push.sh push basetools --builder ssh --host aws-docker-builder --registry ghcr --login --emit-promotion
git add basetools .github/promotions/basetools.json
git commit -m "Promote AWS-built basetools image"
git push origin main
```
