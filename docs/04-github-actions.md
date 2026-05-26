# GitHub Actions Build And Promotion

Workflow file:

```text
.github/workflows/build-and-push.yml
```

## What Triggers The Workflow

The workflow watches:

```yaml
paths:
  - 'images/**'
  - '.github/promotions/*.json'
  - '.github/workflows/build-and-push.yml'
```

Image build detection is based on logical image names under `images/`.

If this changes:

```text
images/basetools/scripts/setup.sh
```

GitHub maps it to:

```text
images/basetools/
```

Then it builds `basetools` only if:

```text
images/basetools/Dockerfile
```

exists.

## What Does Not Build

These do not build images:

```text
docs/04-github-actions.md
scripts/start_aws_builder.sh
README.md
docker-builder-secrets.example
```

## Default Build Mode

If an image directory changes and no promotion manifest changed for that image, GitHub builds in the cloud.

Example:

```bash
git add images/basetools
git commit -m "Update basetools image"
git push origin main
```

Result:

```text
GitHub Actions builds basetools.
GitHub Actions pushes GHCR tags.
```

## Promotion Mode

If `.github/promotions/<image>.json` changed, GitHub promotes the source image from that manifest.

Example:

```bash
git add images/basetools .github/promotions/basetools.json
git commit -m "Promote AWS-built basetools image"
git push origin main
```

Result:

```text
GitHub Actions reads .github/promotions/basetools.json.
GitHub Actions verifies the committed basetools context hash.
GitHub Actions skips docker build.
GitHub Actions retags the pre-built image.
```

## Why The Context Hash Matters

The manifest contains:

```json
{
  "context_sha256": "..."
}
```

GitHub recomputes this hash from the committed image directory.

If the hashes match:

```text
The source image was built from these committed files.
Promotion is allowed.
```

If the hashes do not match:

```text
The source image was built from different files.
Promotion fails.
```

## Tags From GitHub Build

GitHub cloud build pushes:

```text
ghcr.io/<owner>/<image>:latest
ghcr.io/<owner>/<image>:YYYYMMDD
ghcr.io/<owner>/<image>:sha-<commit12>
ghcr.io/<owner>/<image>:gha-YYYYMMDD-<commit12>
```

## Tags From Promotion

Promotion pushes:

```text
ghcr.io/<owner>/<image>:latest
ghcr.io/<owner>/<image>:YYYYMMDD
ghcr.io/<owner>/<image>:sha-<commit12>
ghcr.io/<owner>/<image>:promoted-<origin>-<commit12>
```

The original external source tag remains available, for example:

```text
ghcr.io/<owner>/<image>:aws-YYYYMMDD-<context12>
```

## Manual Workflow Dispatch

Open GitHub:

```text
Actions -> Build Or Promote Changed Containers -> Run workflow
```

Build:

```text
image_dir: basetools
promote_existing: false
```

Promote:

```text
image_dir: basetools
promote_existing: true
```

Manual promotion requires:

```text
.github/promotions/basetools.json
```

## Troubleshooting GHCR Push Permission

Symptom:

```text
ERROR: failed to push ghcr.io/<owner>/<image>:latest
unexpected status from HEAD request ... 403 Forbidden
```

What this usually means:

```text
The image built successfully, but GitHub Actions could not push layers to GHCR.
This is usually package-level access control, not a Dockerfile problem.
```

This workflow already requests package write permission:

```yaml
permissions:
  contents: read
  packages: write
```

If the package already existed because it was first pushed from local/AWS with a personal token, GHCR may treat it as a separately permissioned package. In that case, the repository workflow token may not automatically have write access.

### Option 1: Grant Actions Access To The Existing Package

Use this when the package already has useful tags you want to keep.

Open the package page:

```text
https://github.com/users/<owner>/packages/container/package/<image>
```

Then:

```text
Package settings
Manage Actions access
Add Repository
Select <owner>/<repo>
Grant Write access
Re-run the failed workflow
```

Use `Admin` instead of `Write` only if you want the workflow to manage or delete package versions later.

### Option 2: Delete And Recreate The Package

Use this only when you do not need the existing package versions/tags.

```text
Package settings
Danger Zone
Delete this package
Re-run the GitHub Actions workflow
```

When GitHub Actions creates the package from this repository, the package should be associated with the repository automatically.

### Option 3: Keep External Builds As The Source Of Truth

Use this when AWS/local builds are preferred and GitHub should only promote an already-pushed image.

```bash
./build_and_push.sh push basetools \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --login \
  --emit-promotion

git add images/basetools .github/promotions/basetools.json
git commit -m "Promote AWS-built basetools image"
git push origin main
```

This still needs GitHub Actions to write the promoted tags, so package Actions access may still be required for the destination package.

### Option 4: Use A PAT Secret For The Workflow

Prefer `GITHUB_TOKEN` when possible. If package ownership/access rules make that painful for a group workflow, you can use a dedicated GitHub personal access token secret.

Create a classic PAT with:

```text
write:packages
read:packages
```

Add it as a repository secret:

```text
Settings
Secrets and variables
Actions
New repository secret
Name: GHCR_TOKEN
Value: <token value>
```

If the token belongs to a shared service account rather than the person who triggered the workflow, also add:

```text
Name: GHCR_USER
Value: <github username that owns the token>
```

Then change the GHCR login step to use the PAT secret. If you added `GHCR_USER`, use both secrets:

```yaml
username: ${{ secrets.GHCR_USER }}
password: ${{ secrets.GHCR_TOKEN }}
```

If the token belongs to the same account as the workflow actor, this smaller change is usually enough:

```yaml
password: ${{ secrets.GHCR_TOKEN }}
```

Do not commit token values. If a token is pasted into a file, shell history, terminal screenshot, or chat, revoke/regenerate it immediately.

Related GitHub documentation:

```text
https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages
https://docs.github.com/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility
```

### Quick Diagnosis Checklist

Check these in order:

```text
The job reached "Build and push image in GitHub Actions" and failed during push.
The repository workflow has packages: write.
The GHCR package exists under the same owner as the repository owner.
The package has Manage Actions access for this repository.
The package was not first created under a different user/org than expected.
The failed image name is the intended logical image name, such as basetools.
```

## Common Questions

Question:

```text
I changed Dockerfile and built on AWS. I want to commit the Dockerfile but not rebuild in GitHub.
```

Answer:

```bash
./build_and_push.sh push basetools \
  --builder ssh \
  --host aws-docker-builder \
  --registry ghcr \
  --login \
  --emit-promotion

git add images/basetools .github/promotions/basetools.json
git commit -m "Promote AWS-built basetools image"
git push origin main
```

Question:

```text
I changed images/basetools/docs/notes.md. Will it rebuild basetools?
```

Answer:

```text
Yes. It is inside the basetools image directory under images/.
```

Question:

```text
I changed docs/notes.md. Will it rebuild basetools?
```

Answer:

```text
No. It is not inside images/basetools.
```
