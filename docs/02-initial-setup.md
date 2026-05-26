# Initial Setup

This setup is per user. Do not commit personal credentials, SSH keys, AWS credentials, or private config files.

## Required Tools

For local builds:

```text
Docker or Podman
Bash
tar
Git
```

For SSH/AWS builds:

```text
ssh
tar
AWS builder host with Docker or Podman
```

For starting AWS builders:

```text
AWS CLI configured with credentials and region
An EC2 launch template
SSH access to the launched instance
```

## Private Config File

Create a private config/secrets file:

```bash
mkdir -p "${HOME}/.config"
cp docker-builder-secrets.example "${HOME}/.config/.docker-builder-secrets"
chmod 600 "${HOME}/.config/.docker-builder-secrets"
```

Edit it:

```bash
nano "${HOME}/.config/.docker-builder-secrets"
```

Minimum GHCR config:

```bash
DEFAULT_REGISTRY=ghcr
IMAGE_ROOT=images
BUILDER_MODE=auto
BUILDER_TARGET=
BUILDER_ENGINE=docker

GHCR_OWNER=your-github-org-or-user
GHCR_USER=your-github-username
GHCR_TOKEN=your-github-token-with-package-write-access
```

Optional DockerHub config:

```bash
DOCKERHUB_USER=your-dockerhub-username
DOCKERHUB_TOKEN=your-dockerhub-access-token
```

Optional AWS builder launcher config:

```bash
AWS_BUILDER_TEMPLATE=DockerBuilderTemplate
AWS_PROFILE_NAME=
AWS_REGION_NAME=
```

The script automatically loads:

```text
~/.config/.docker-builder-secrets
```

Use another config file:

```bash
export DOCKER_BUILDER_SECRETS=/path/to/another/secrets-file
```

Disable config loading for one command:

```bash
./build_and_push.sh test basetools --no-config --registry ghcr
```

## GHCR Token

Use a GitHub token that can push packages to GHCR.

For a classic token, it generally needs:

```text
write:packages
read:packages
```

If the package is private, repository/org permissions may also matter.

Do not print token values in logs. Do not paste tokens into chat. If a token is exposed, revoke or regenerate it.

## DockerHub Token

Create a DockerHub access token if you will push to DockerHub.

Store it only in:

```text
~/.config/.docker-builder-secrets
```

## SSH Config For Remote Builder

Recommended `~/.ssh/config` entry:

```sshconfig
Host aws-docker-builder
    HostName ec2-xx-xx-xx-xx.compute-1.amazonaws.com
    User ubuntu
    IdentityFile ~/.ssh/your-ec2-key.pem
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
```

Test SSH:

```bash
ssh aws-docker-builder 'hostname'
```

Test remote container engine:

```bash
ssh aws-docker-builder 'command -v docker || command -v podman'
```

The SSH user must be able to run Docker or Podman without interactive `sudo`.

## Builder Defaults

For local-first behavior:

```bash
BUILDER_MODE=auto
BUILDER_TARGET=
BUILDER_ENGINE=docker
```

For AWS-first behavior:

```bash
BUILDER_MODE=ssh
BUILDER_TARGET=aws-docker-builder
BUILDER_ENGINE=docker
```

## Verify The Script

```bash
./build_and_push.sh --help
```

Verify config loads without building by using a harmless engine for parser testing:

```bash
GHCR_OWNER=example-org ./build_and_push.sh test basetools --no-config --builder local --engine true --registry ghcr
```

The command above validates argument parsing and tagging only. It does not build a real image.
