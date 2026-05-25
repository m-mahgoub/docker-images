# Common Workflows

All examples assume you are in the repository root:

```bash
cd /path/to/docker-images
export IMAGE_DIR=basetools
```

## Workflow 1: Local Test Build

Use this when you want quick local validation.

```bash
export IMAGE_DIR=basetools
export GHCR_OWNER=your-github-org-or-user

./build_and_push.sh test "${IMAGE_DIR}" \
  --builder local \
  --registry ghcr
```

What happens:

```text
Docker/Podman builds the image locally.
The image is tagged with local-origin tags.
The script opens an interactive shell inside the container.
Nothing is pushed.
```

Useful checks inside the container:

```bash
which python
python --version
which samtools
samtools --version
echo "$PATH"
exit
```

Force Podman locally:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder local \
  --engine podman \
  --registry ghcr
```

Use `/bin/sh` instead of `/bin/bash`:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder local \
  --registry ghcr \
  --shell /bin/sh
```

## Workflow 2: SSH/AWS Test Build

Use this when the cluster cannot build reliably, or when you want a larger AWS builder.

```bash
export IMAGE_DIR=basetools
export GHCR_OWNER=your-github-org-or-user

./build_and_push.sh test "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr
```

What happens:

```text
The local image directory is tar-streamed to AWS over SSH.
AWS builds the image from that streamed context.
The remote temporary context is removed after build.
The script opens an interactive shell inside the container on AWS.
Nothing is pushed.
```

Set the builder once for the shell:

```bash
export BUILDER_MODE=ssh
export BUILDER_TARGET=aws-docker-builder
export BUILDER_ENGINE=docker

./build_and_push.sh test "${IMAGE_DIR}" --registry ghcr
```

Force Podman remotely:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --engine podman \
  --registry ghcr
```

## Workflow 3: Local Push To GHCR

Use this when local build is trustworthy and you want to publish directly.

```bash
export IMAGE_DIR=basetools
export GHCR_OWNER=your-github-org-or-user
export GHCR_USER=your-github-username
export GHCR_TOKEN=your-github-token-with-package-write-access

./build_and_push.sh push "${IMAGE_DIR}" \
  --builder local \
  --registry ghcr \
  --login
```

Tags pushed:

```text
ghcr.io/<owner>/<image>:latest
ghcr.io/<owner>/<image>:YYYYMMDD
ghcr.io/<owner>/<image>:local-YYYYMMDD-<context12>
ghcr.io/<owner>/<image>:external-local-YYYYMMDD
```

## Workflow 4: AWS Push To GHCR

Use this when AWS is your trusted builder.

```bash
export IMAGE_DIR=basetools
export GHCR_OWNER=your-github-org-or-user
export GHCR_USER=your-github-username
export GHCR_TOKEN=your-github-token-with-package-write-access

./build_and_push.sh push "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --login
```

Tags pushed:

```text
ghcr.io/<owner>/<image>:latest
ghcr.io/<owner>/<image>:YYYYMMDD
ghcr.io/<owner>/<image>:aws-YYYYMMDD-<context12>
ghcr.io/<owner>/<image>:external-aws-YYYYMMDD
```

## Workflow 5: AWS Build, Commit Dockerfile, Skip GitHub Rebuild

This is the important fast-track workflow.

Use this when:

```text
You changed Dockerfile/pixi.toml/scripts/configs inside the image directory.
You built and tested the image on AWS.
You want Git to track the exact files used for the build.
You do not want GitHub Actions to rebuild the image.
```

Step 1: edit files under the image directory.

```bash
export IMAGE_DIR=basetools
$EDITOR "${IMAGE_DIR}/Dockerfile"
```

Step 2: test on AWS.

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr
```

Step 3: push the AWS-built image and emit a promotion manifest.

```bash
export GHCR_OWNER=your-github-org-or-user
export GHCR_USER=your-github-username
export GHCR_TOKEN=your-github-token-with-package-write-access

./build_and_push.sh push "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --login \
  --emit-promotion
```

Step 4: review what changed.

```bash
git status --short
cat ".github/promotions/${IMAGE_DIR}.json"
```

Step 5: commit the image files and promotion manifest together.

```bash
git add "${IMAGE_DIR}" ".github/promotions/${IMAGE_DIR}.json"
git commit -m "Promote AWS-built ${IMAGE_DIR} image"
git push origin main
```

What GitHub Actions does after the push:

```text
It sees files under basetools changed.
It sees .github/promotions/basetools.json changed.
It recomputes the basetools build-context hash from the committed files.
It compares that hash to the manifest.
If the hashes match, it skips docker build.
It retags the AWS-built source image as latest/date/sha/promoted tags.
```

If hashes do not match:

```text
The workflow fails.
No promotion happens.
Rebuild from the exact files you intend to push and re-run --emit-promotion.
```

## Workflow 6: Default GitHub Actions Build

Use this when you are comfortable with GitHub building the image.

```bash
export IMAGE_DIR=basetools

git add "${IMAGE_DIR}"
git commit -m "Update ${IMAGE_DIR} image"
git push origin main
```

What GitHub Actions does:

```text
It detects changed files under the image directory.
It builds in GitHub Actions.
It pushes latest/date/sha/gha tags to GHCR.
```

Tags pushed:

```text
ghcr.io/<owner>/<image>:latest
ghcr.io/<owner>/<image>:YYYYMMDD
ghcr.io/<owner>/<image>:sha-<commit12>
ghcr.io/<owner>/<image>:gha-YYYYMMDD-<commit12>
```

## Workflow 7: Manual GitHub Actions Build Or Promote

In GitHub:

```text
Actions -> Build Or Promote Changed Containers -> Run workflow
```

Build a specific image:

```text
image_dir: basetools
promote_existing: false
```

Promote a specific image:

```text
image_dir: basetools
promote_existing: true
```

Manual promotion requires a committed manifest:

```text
.github/promotions/basetools.json
```

## Workflow 8: DockerHub Push

DockerHub push is supported by the script. GitHub Actions promotion is GHCR-focused.

Local DockerHub push:

```bash
export IMAGE_DIR=basetools
export DOCKERHUB_USER=your-dockerhub-username
export DOCKERHUB_TOKEN=your-dockerhub-access-token

./build_and_push.sh push "${IMAGE_DIR}" \
  --builder local \
  --registry dockerhub \
  --login
```

AWS DockerHub push:

```bash
export IMAGE_DIR=basetools
export DOCKERHUB_USER=your-dockerhub-username
export DOCKERHUB_TOKEN=your-dockerhub-access-token

./build_and_push.sh push "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry dockerhub \
  --login
```

## Workflow 9: Options

Override the date tag:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder local \
  --registry ghcr \
  --date-tag 20260525
```

Build for a platform:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --platform linux/amd64
```

Pass a build argument:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --build-opt "--build-arg=PIXI_VERSION=v0.61.0"
```

Disable cache:

```bash
./build_and_push.sh test "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --build-opt "--no-cache"
```

Use a custom origin tag:

```bash
./build_and_push.sh push "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --origin ec2-large \
  --login
```
