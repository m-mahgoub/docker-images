# Reference

## Script Interface

```bash
./build_and_push.sh <mode> <image-directory> [options]
```

The image argument can be the short logical image name, such as `basetools`, or the explicit path, such as `images/basetools`. The recommended command style is the short name.

Modes:

```text
test    Build and open an interactive shell.
push    Build and push image tags.
```

Builder options:

```text
--builder auto|local|ssh
--host <ssh-target>
--engine docker|podman
--platform linux/amd64
--shell /bin/bash
```

Registry options:

```text
--registry ghcr
--registry dockerhub
--login
```

Promotion options:

```text
--emit-promotion
--promotion-dir .github/promotions
```

Build options:

```text
--date-tag YYYYMMDD
--origin custom-origin-name
--build-opt "--no-cache"
--build-opt "--build-arg=NAME=value"
```

Config options:

```text
--config /path/to/file
--no-config
```

## Config Variables

```text
DEFAULT_REGISTRY
IMAGE_ROOT
BUILDER_MODE
BUILDER_TARGET
BUILDER_ENGINE
GHCR_OWNER
GHCR_USER
GHCR_TOKEN
DOCKERHUB_USER
DOCKERHUB_TOKEN
AWS_BUILDER_TEMPLATE
AWS_PROFILE_NAME
AWS_REGION_NAME
```

## Tagging Strategy

GitHub-built image:

```text
gha-YYYYMMDD-<commit12>
```

External AWS-built image:

```text
aws-YYYYMMDD-<context12>
external-aws-YYYYMMDD
```

External local-built image:

```text
local-YYYYMMDD-<context12>
external-local-YYYYMMDD
```

Commit tag:

```text
sha-<commit12>
```

Promoted image:

```text
promoted-<origin>-<commit12>
```

Shared convenience tags:

```text
latest
YYYYMMDD
```

## OCI Labels

Images built by the script and GitHub Actions include:

```text
org.opencontainers.image.created
org.opencontainers.image.revision
org.opencontainers.image.source
org.opencontainers.image.title
edu.wustl.dhslab.build.origin
edu.wustl.dhslab.build.engine
edu.wustl.dhslab.build.context_sha256
```

Inspect with Docker:

```bash
docker inspect ghcr.io/<owner>/<image>:<tag>
```

Inspect with Podman:

```bash
podman inspect ghcr.io/<owner>/<image>:<tag>
```

## Promotion Manifest

Path:

```text
.github/promotions/<image>.json
```

`image_dir` stores the logical image name, such as `basetools`. The repository path is resolved as `images/<image>/` by default.

Example:

```json
{
  "schema_version": 1,
  "image_dir": "basetools",
  "image_name": "basetools",
  "registry": "ghcr",
  "repository": "ghcr.io/example-org/basetools",
  "source_image": "ghcr.io/example-org/basetools:aws-20260525-abc123def456",
  "build_origin": "aws",
  "build_engine": "docker",
  "context_sha256": "abc123...",
  "created_at": "2026-05-25T18:00:00Z"
}
```

## Context Hash

The context hash protects promotion correctness.

The script computes a SHA256 hash of the image directory contents under `images/<image>/`. GitHub recomputes the hash from committed files. Promotion is allowed only when both hashes match.

Before emitting a promotion manifest:

```bash
git status --short "images/${IMAGE_DIR}"
```

After emitting:

```bash
cat ".github/promotions/${IMAGE_DIR}.json"
```

## Troubleshooting

SSH builder cannot connect:

```bash
ssh aws-docker-builder 'hostname'
```

Remote Docker/Podman missing:

```bash
ssh aws-docker-builder 'command -v docker; command -v podman'
```

GHCR login fails:

```bash
echo "${GHCR_USER}"
test -n "${GHCR_TOKEN}" && echo "GHCR_TOKEN is set"
```

Do not print the token value.

Promotion context mismatch:

```text
The files committed to Git differ from the files used to build the external image.
Rebuild from the exact files you will push.
Re-run with --emit-promotion.
Commit the image directory and promotion manifest together.
```

GitHub builds instead of promotes:

```text
Confirm .github/promotions/<image>.json changed in the pushed commit.
Confirm the manifest image_dir matches the logical image name, such as basetools.
For manual runs, set promote_existing to true.
```

Workflow runs but no image builds:

```text
The changed files probably are not under images/<image>/.
This is expected for docs/, scripts/, and other repo-level support folders.
```
