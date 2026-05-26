# Overview

This repository is organized around image directories under `images/`. Each image directory contains one `Dockerfile` and all files needed by that image.

The command-facing image name stays short. For example, the `basetools` image lives at `images/basetools/`, but commands still use `basetools`.

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
  images/
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
Pushing changes under `images/<image>/` triggers GitHub Actions.
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

Any committed change under `images/<image>/` can trigger that image build.

Examples that trigger `basetools`:

```text
images/basetools/Dockerfile
images/basetools/pixi.toml
images/basetools/scripts/install.sh
images/basetools/configs/tool.yaml
images/basetools/docs/notes.md
```

Examples that do not build an image:

```text
README.md
docs/01-overview.md
scripts/start_aws_builder.sh
docker-builder-secrets.example
```

Technically, the workflow can start for some repo-level changes, but the build matrix only includes directories that resolve to `images/<image>/Dockerfile`.

## Promotion Rule

If both the image directory under `images/` and `.github/promotions/<image>.json` change in the same push, GitHub Actions promotes the pre-built image instead of rebuilding.

If only the image directory changes, GitHub Actions builds in GitHub.

## Recommended Daily Flow

For simple changes where GitHub cloud build is fine:

```bash
git add images/basetools
git commit -m "Update basetools image"
git push origin main
```

For heavy changes you tested on AWS:

```bash
./build_and_push.sh push basetools --builder ssh --host aws-docker-builder --registry ghcr --login --emit-promotion
git add images/basetools .github/promotions/basetools.json
git commit -m "Promote AWS-built basetools image"
git push origin main
```
