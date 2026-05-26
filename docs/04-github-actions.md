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
