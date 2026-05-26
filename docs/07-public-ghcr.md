# Public GHCR Images For SLURM

This repository is intended to publish images that can be pulled by SLURM/Pyxis/Enroot without user-specific credentials.

For that to work, the GHCR package must be public.

## Why Pyxis/Enroot Fails

Common failure:

```text
pyxis: failed to import docker image
[INFO] Querying registry for permission grant
[INFO] Authenticating with user: <user>
[INFO] Using credentials from file: ~/.config/enroot/.credentials
[ERROR] URL https://ghcr.io/token returned error code: 403 Forbidden
```

This usually means one of two things:

```text
The GHCR package is private, so anonymous cluster pulls are blocked.
```

or:

```text
The package is public, but Enroot found stale GHCR credentials and attempted a bad authenticated pull instead of an anonymous pull.
```

## What Can Be Automated

GitHub's official behavior matters here:

```text
Public GHCR container packages allow anonymous pull.
Personal-account GHCR packages are private when first published.
Linked packages inherit repository access permissions, but not repository visibility.
For organization-owned packages, org owners can configure package creation visibility policy.
Changing a package from private to public is irreversible.
```

Practical interpretation:

```text
For packages under a personal account, GitHub documents changing package visibility through package settings.
For packages under an organization, the cleanest scalable setup is to publish under the organization and configure organization package creation to allow public packages.
For existing private packages, expect a one-time visibility flip per package unless your GitHub organization policy handles it at creation time.
```

The workflow and build script can make packages easier to manage by linking images back to this repository, but they cannot safely bypass GitHub package visibility controls.

## Best Long-Term Setup

Use an organization namespace for lab-owned public images:

```bash
GHCR_OWNER=your-lab-org
```

In GitHub, an organization owner should configure:

```text
Organization -> Settings -> Packages -> Package Creation -> Public
```

Then build/push images as usual:

```bash
export IMAGE_DIR=fibertools
./build_and_push.sh push "${IMAGE_DIR}" \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --login
```

This avoids every lab member publishing personal private packages accidentally.

## Personal Namespace Setup

If you publish under a personal namespace:

```bash
GHCR_OWNER=your-github-username
```

new GHCR packages are private by default. For each new image package:

```text
Open https://github.com/users/<owner>/packages/container/package/<image>
Package settings
Danger Zone
Change visibility
Public
Confirm the package name
```

Important:

```text
Once a GHCR package is public, GitHub does not allow making it private again.
```

## Check Anonymous Pullability

Use the repository helper:

```bash
scripts/check_ghcr_public.sh --owner your-github-org-or-user
```

Check one image:

```bash
scripts/check_ghcr_public.sh --owner your-github-org-or-user fibertools
```

Check a specific tag:

```bash
scripts/check_ghcr_public.sh --owner your-github-org-or-user --tag latest fibertools
```

Expected public output:

```text
PUBLIC  your-github-org-or-user/fibertools:latest  anonymous manifest request succeeded
```

Private or blocked output:

```text
NOT_PUBLIC  your-github-org-or-user/fibertools:latest  anonymous token request returned HTTP 403
```

The script does not read or send your GitHub token. It checks exactly what the cluster needs: anonymous pull access.

## Enroot Credentials Gotcha

For public images, Enroot should not need GHCR credentials.

If the package is public but Pyxis still fails while saying it is using:

```text
~/.config/enroot/.credentials
```

then the credentials file may contain an expired or insufficient GHCR token. Options:

```bash
mv ~/.config/enroot/.credentials ~/.config/enroot/.credentials.backup
```

or edit the file and remove/comment only the `ghcr.io` entry.

Then retry:

```bash
sin_docker ghcr.io/<owner>/fibertools:latest 4 12
```

If you also use private GHCR images, do not delete the file permanently. Instead, refresh the GHCR entry with a token that has at least:

```text
read:packages
```

Do not commit Enroot credentials or paste token values into documentation, chat, shell scripts, or screenshots.

## Quick Decision Tree

Use this for lab-public images:

```text
Can we publish under a lab GitHub organization?
Yes -> Configure org package creation policy and publish to ghcr.io/<org>/<image>.
No  -> Publish under personal owner and manually make each new package public once.
```

If SLURM still fails:

```text
Run scripts/check_ghcr_public.sh.
If NOT_PUBLIC, fix package visibility.
If PUBLIC, remove or refresh ~/.config/enroot/.credentials for ghcr.io.
```

## Sources

GitHub documents that public Container registry packages allow anonymous access, while package visibility and package Actions access are controlled in package settings:

```text
https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility
```
