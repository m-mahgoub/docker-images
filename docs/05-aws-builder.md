# AWS Builder

The AWS builder is optional. It is useful when local machines or HPC login nodes cannot build containers reliably.

The helper script is:

```text
scripts/start_aws_builder.sh
```

## Recommendation

Keep `scripts/start_aws_builder.sh` in the repository because it is shared workflow glue.

Keep these outside the repository:

```text
AWS credentials
SSH private keys
personal SSH config values
real token values
```

## AWS Prerequisites

Verify the AWS CLI works:

```bash
aws sts get-caller-identity
```

If your group uses an AWS profile:

```bash
aws --profile lab-builder sts get-caller-identity
```

## Launch Template

The script expects an EC2 launch template name by default:

```bash
scripts/start_aws_builder.sh --template DockerBuilderTemplate
```

That means this AWS CLI field:

```text
LaunchTemplateName
```

not this field:

```text
LaunchTemplateId
```

The launch template should define:

```text
AMI
instance type
storage
security group
SSH key pair
IAM role if needed
user-data or AMI setup that installs Docker/Podman
```

## SSH Alias

Recommended local SSH config:

```sshconfig
Host aws-docker-builder
    HostName ec2-placeholder.compute-1.amazonaws.com
    User ubuntu
    IdentityFile ~/.ssh/your-ec2-key.pem
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
```

The launcher updates only the `HostName` line for this alias.

## Start Builder

Using defaults:

```bash
scripts/start_aws_builder.sh
```

With explicit template:

```bash
scripts/start_aws_builder.sh \
  --template DockerBuilderTemplate \
  --host-alias aws-docker-builder
```

With AWS profile and region:

```bash
scripts/start_aws_builder.sh \
  --profile lab-builder \
  --region us-east-1 \
  --template DockerBuilderTemplate \
  --host-alias aws-docker-builder
```

Without modifying SSH config:

```bash
scripts/start_aws_builder.sh --no-ssh-config-update
```

## What The Script Does

```text
Runs aws ec2 run-instances from the launch template.
Waits for instance-running.
Waits for instance-status-ok.
Reads public DNS and public IP.
Updates ~/.ssh/config HostName for the configured alias.
Prints the instance ID and terminate command.
```

## Test Builder

```bash
ssh aws-docker-builder 'hostname; command -v docker || command -v podman'
```

Confirm Docker works:

```bash
ssh aws-docker-builder 'docker version'
```

Or Podman:

```bash
ssh aws-docker-builder 'podman version'
```

## Use Builder

```bash
export IMAGE_DIR=basetools
export IMAGE_PATH="images/${IMAGE_DIR}"
export BUILDER_MODE=ssh
export BUILDER_TARGET=aws-docker-builder
export BUILDER_ENGINE=docker

./build_and_push.sh test "${IMAGE_DIR}" --registry ghcr
```

## Push From Builder

```bash
export IMAGE_DIR=basetools
export IMAGE_PATH="images/${IMAGE_DIR}"
export BUILDER_MODE=ssh
export BUILDER_TARGET=aws-docker-builder
export BUILDER_ENGINE=docker
export GHCR_OWNER=your-github-org-or-user
export GHCR_USER=your-github-username
export GHCR_TOKEN=your-github-token-with-package-write-access

./build_and_push.sh push "${IMAGE_DIR}" --registry ghcr --login
```

## Promote AWS Build

```bash
export IMAGE_DIR=basetools
export IMAGE_PATH="images/${IMAGE_DIR}"
export BUILDER_MODE=ssh
export BUILDER_TARGET=aws-docker-builder
export BUILDER_ENGINE=docker

./build_and_push.sh push "${IMAGE_DIR}" \
  --registry ghcr \
  --login \
  --emit-promotion
```

Then:

```bash
git add "${IMAGE_PATH}" ".github/promotions/${IMAGE_DIR}.json"
git commit -m "Promote AWS-built ${IMAGE_DIR} image"
git push origin main
```

## Terminate Builder

The start script prints:

```bash
aws ec2 terminate-instances --instance-ids <instance-id>
```

Run it when finished.

Confirm termination:

```bash
aws ec2 describe-instances \
  --instance-ids <instance-id> \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text
```
