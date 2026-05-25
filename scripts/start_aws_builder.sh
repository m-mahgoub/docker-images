#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/start_aws_builder.sh [options]

Launch an AWS EC2 builder from a launch template and update an SSH config host.
AWS credentials and default region must already be configured.

Options:
  --template <name>        Launch template name (default: DockerBuilderTemplate)
  --host-alias <alias>     SSH config Host alias to update (default: aws-docker-builder)
  --ssh-config <path>      SSH config file (default: ~/.ssh/config)
  --profile <name>         Optional AWS profile
  --region <region>        Optional AWS region
  --no-ssh-config-update   Do not edit SSH config; print the IP only
  -h, --help               Show this help

Examples:
  scripts/start_aws_builder.sh
  scripts/start_aws_builder.sh --template DockerBuilderTemplate --host-alias aws-docker-builder
  scripts/start_aws_builder.sh --profile lab --region us-east-1
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found in PATH"
}

validate_host_alias() {
  local host_alias="$1"

  [[ "${host_alias}" =~ ^[A-Za-z0-9._-]+$ ]] || {
    die "host alias must contain only letters, numbers, dots, underscores, and dashes"
  }
}

aws_cli() {
  local cmd=(aws)

  if [[ -n "${AWS_PROFILE_NAME}" ]]; then
    cmd+=(--profile "${AWS_PROFILE_NAME}")
  fi

  if [[ -n "${AWS_REGION_NAME}" ]]; then
    cmd+=(--region "${AWS_REGION_NAME}")
  fi

  cmd+=("$@")
  "${cmd[@]}"
}

update_ssh_config_host() {
  local ssh_config="$1"
  local host_alias="$2"
  local public_host="$3"
  local tmp_config

  mkdir -p "$(dirname "${ssh_config}")"
  touch "${ssh_config}"
  chmod 600 "${ssh_config}"

  tmp_config="$(mktemp)"

  awk -v host_alias="${host_alias}" -v public_host="${public_host}" '
    BEGIN {
      in_block = 0
      found_block = 0
      updated_hostname = 0
    }
    /^Host[[:space:]]+/ {
      if (in_block && !updated_hostname) {
        print "    HostName " public_host
      }
      in_block = 0
      updated_hostname = 0
      for (i = 2; i <= NF; i++) {
        if ($i == host_alias) {
          in_block = 1
          found_block = 1
        }
      }
    }
    in_block && /^[[:space:]]*HostName[[:space:]]+/ {
      print "    HostName " public_host
      updated_hostname = 1
      next
    }
    { print }
    END {
      if (in_block && !updated_hostname) {
        print "    HostName " public_host
      }
      if (!found_block) {
        print ""
        print "Host " host_alias
        print "    HostName " public_host
      }
    }
  ' "${ssh_config}" > "${tmp_config}"

  mv "${tmp_config}" "${ssh_config}"
  chmod 600 "${ssh_config}"
}

TEMPLATE_NAME="${AWS_BUILDER_TEMPLATE:-DockerBuilderTemplate}"
HOST_ALIAS="${BUILDER_TARGET:-aws-docker-builder}"
SSH_CONFIG="${SSH_CONFIG:-${HOME}/.ssh/config}"
AWS_PROFILE_NAME="${AWS_PROFILE_NAME:-${AWS_PROFILE:-}}"
AWS_REGION_NAME="${AWS_REGION_NAME:-${AWS_REGION:-}}"
UPDATE_SSH_CONFIG=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      [[ $# -ge 2 ]] || die "--template requires a value"
      TEMPLATE_NAME="$2"
      shift 2
      ;;
    --host-alias)
      [[ $# -ge 2 ]] || die "--host-alias requires a value"
      HOST_ALIAS="$2"
      shift 2
      ;;
    --ssh-config)
      [[ $# -ge 2 ]] || die "--ssh-config requires a value"
      SSH_CONFIG="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || die "--profile requires a value"
      AWS_PROFILE_NAME="$2"
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || die "--region requires a value"
      AWS_REGION_NAME="$2"
      shift 2
      ;;
    --no-ssh-config-update)
      UPDATE_SSH_CONFIG=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_cmd aws
require_cmd awk
validate_host_alias "${HOST_ALIAS}"

echo "Requesting EC2 instance from launch template: ${TEMPLATE_NAME}"
INSTANCE_ID="$(
  aws_cli ec2 run-instances \
    --launch-template "LaunchTemplateName=${TEMPLATE_NAME}" \
    --query 'Instances[0].InstanceId' \
    --output text
)"

if [[ -z "${INSTANCE_ID}" || "${INSTANCE_ID}" == "None" ]]; then
  die "failed to launch instance from template '${TEMPLATE_NAME}'"
fi

echo "Instance requested: ${INSTANCE_ID}"
echo "Waiting for instance to enter running state..."
aws_cli ec2 wait instance-running --instance-ids "${INSTANCE_ID}"

echo "Waiting for AWS status checks..."
aws_cli ec2 wait instance-status-ok --instance-ids "${INSTANCE_ID}"

PUBLIC_DNS="$(
  aws_cli ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text
)"

PUBLIC_IP="$(
  aws_cli ec2 describe-instances \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
)"

if [[ -z "${PUBLIC_DNS}" || "${PUBLIC_DNS}" == "None" ]]; then
  PUBLIC_DNS="${PUBLIC_IP}"
fi

if [[ -z "${PUBLIC_DNS}" || "${PUBLIC_DNS}" == "None" ]]; then
  die "instance is running, but no public DNS/IP was found"
fi

echo "Builder is running."
echo "Instance ID : ${INSTANCE_ID}"
echo "Public host : ${PUBLIC_DNS}"
echo "Public IP   : ${PUBLIC_IP}"

if [[ "${UPDATE_SSH_CONFIG}" -eq 1 ]]; then
  update_ssh_config_host "${SSH_CONFIG}" "${HOST_ALIAS}" "${PUBLIC_DNS}"
  echo "Updated SSH config: ${SSH_CONFIG}"
  echo "SSH alias         : ${HOST_ALIAS}"
fi

cat <<EOF

Use this builder:
  export BUILDER_MODE=ssh
  export BUILDER_TARGET=${HOST_ALIAS}
  export BUILDER_ENGINE=docker

Test SSH:
  ssh ${HOST_ALIAS} 'hostname; command -v docker || command -v podman'

Terminate when finished:
  aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
EOF
