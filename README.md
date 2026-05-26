# Container Build Documentation

This repository builds, tests, publishes, and promotes Docker/OCI images for bioinformatics workflows.

Start here:

1. Read [docs/01-overview.md](docs/01-overview.md) for the mental model.
2. Read [docs/02-initial-setup.md](docs/02-initial-setup.md) for one-time user setup.
3. Use [docs/03-common-workflows.md](docs/03-common-workflows.md) for copy-paste workflows.
4. Use [docs/04-github-actions.md](docs/04-github-actions.md) to understand automatic builds and promotion.
5. Use [docs/05-aws-builder.md](docs/05-aws-builder.md) to start and use an EC2 builder.
6. Use [docs/06-reference.md](docs/06-reference.md) for tags, labels, manifests, and troubleshooting.

Most common commands:

```bash
export IMAGE_DIR=basetools
./build_and_push.sh test "${IMAGE_DIR}" --builder local --registry ghcr
```

```bash
export IMAGE_DIR=basetools
./build_and_push.sh test "${IMAGE_DIR}" --builder ssh --host aws-docker-builder --registry ghcr
```

```bash
export IMAGE_DIR=basetools
./build_and_push.sh push "${IMAGE_DIR}" --builder ssh --host aws-docker-builder --registry ghcr --login --emit-promotion
```

Important rule:

```text
Image source directories live under images/.
Commands still use the logical image name, such as basetools.
Any committed change under images/<image>/ can trigger that image build.
```

Example:

```text
images/basetools/Dockerfile                  triggers basetools
images/basetools/pixi.toml                   triggers basetools
images/basetools/scripts/install.sh          triggers basetools
images/basetools/configs/tool.yaml           triggers basetools
images/basetools/docs/notes.md               triggers basetools
docs/general-notes.md                        does not trigger any image
```
