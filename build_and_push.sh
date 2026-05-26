#!/usr/bin/env bash
set -euo pipefail

# Manual builder utility for local or SSH-routed Docker/Podman builds.
# Supports promotion manifests for GitHub Actions fast-track publishing.

usage() {
  cat <<'USAGE'
Usage:
  ./build_and_push.sh <mode> <image-directory> [options]

The image argument can be a logical image name under IMAGE_ROOT, such as
basetools, or an explicit path such as images/basetools.

Modes:
  test                         Build then open an interactive shell
  push                         Build then push image tags

Builder options:
  --builder <auto|local|ssh>    Builder route (default: auto)
  --host <ssh-target>           SSH target for remote builds
  --engine <docker|podman>      Container engine locally or on SSH builder
  --platform <platform>         Optional platform, e.g. linux/amd64
  --shell <path>                Shell for test mode (default: /bin/bash)

Registry and tagging options:
  -r, --registry <target>       Registry target: ghcr | dockerhub
  --date-tag <YYYYMMDD>         Override date tag (default: current date)
  --origin <name>               Build origin tag component (default: local/aws)
  --login                       Perform registry login using secrets/config
  --build-opt <opt>             Extra build option (repeatable)

Promotion options:
  --emit-promotion              After push, write a GHCR promotion manifest
  --promotion-dir <dir>         Promotion manifest dir (default: .github/promotions)

Config options:
  --config <path>               Load builder config/secrets from path
  --no-config                   Do not auto-load config/secrets file
  -h, --help                    Show this help

Config/secrets lookup:
  Default file:                 ~/.config/.docker-builder-secrets
  Override with env:            DOCKER_BUILDER_SECRETS=/path/to/file

Recommended config variables:
  DEFAULT_REGISTRY              ghcr | dockerhub
  IMAGE_ROOT                    Directory containing image folders (default: images)
  BUILDER_MODE                  auto | local | ssh
  BUILDER_TARGET                SSH target, e.g. aws-docker-builder
  BUILDER_ENGINE                docker | podman
  GHCR_OWNER                    GitHub org/user for ghcr.io images
  GHCR_USER                     GitHub username for GHCR login
  GHCR_TOKEN                    GitHub token for GHCR login
  DOCKERHUB_USER                DockerHub username/namespace
  DOCKERHUB_TOKEN               DockerHub access token

Examples:
  ./build_and_push.sh test basetools --builder local -r ghcr
  ./build_and_push.sh test basetools --builder ssh --host aws-docker-builder -r ghcr
  ./build_and_push.sh push basetools --builder ssh --host aws-docker-builder -r ghcr --login
  ./build_and_push.sh push basetools --builder ssh --host aws-docker-builder -r ghcr --login --emit-promotion
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

warn() {
  echo "Warning: $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found in PATH"
}

shell_join() {
  printf -v "$1" '%q ' "${@:2}"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}

sanitize_ref_component() {
  local value="$1"
  value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]' | tr '/' '-' | tr -c 'a-z0-9_.-' '-')"
  while [[ "${value}" == [-.]* ]]; do
    value="${value#?}"
  done
  while [[ "${value}" == *[-.] ]]; do
    value="${value%?}"
  done
  [[ -n "${value}" ]] || value="image"
  printf '%s' "${value}"
}

hash_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die "sha256sum or shasum is required to compute build context hashes"
  fi
}

compute_context_sha256() {
  local context_dir="$1"

  if tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
      -C "${context_dir}" -cf - . 2>/dev/null | hash_stream; then
    return 0
  fi

  warn "GNU tar deterministic options are unavailable; falling back to plain tar hashing"
  tar -C "${context_dir}" -cf - . | hash_stream
}

repo_source_url() {
  local url path

  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "${url}" ]] || {
    printf unknown
    return 0
  }

  case "${url}" in
    git@github.com:*)
      path="${url#git@github.com:}"
      path="${path%.git}"
      printf 'https://github.com/%s' "${path}"
      ;;
    https://github.com/*)
      printf '%s' "${url%.git}"
      ;;
    *)
      printf '%s' "${url}"
      ;;
  esac
}

load_config_file() {
  local config_file="$1"

  [[ -n "${config_file}" ]] || return 0
  [[ -f "${config_file}" ]] || return 0
  [[ -r "${config_file}" ]] || die "config file exists but is not readable: ${config_file}"

  # The config file is intentionally a shell-style env file. Keep it private.
  set -a
  # shellcheck source=/dev/null
  . "${config_file}"
  set +a
}

ssh_run() {
  local remote_command
  shell_join remote_command "$@"
  ssh "${BUILDER_TARGET}" "${remote_command}"
}

engine_login() {
  local remote_command

  if [[ "${REMOTE_MODE}" -eq 1 ]]; then
    shell_join remote_command "${CONTAINER_CLI}" login "${REGISTRY_HOST}" --username "${LOGIN_USER}" --password-stdin
    printf '%s' "${LOGIN_TOKEN}" | ssh "${BUILDER_TARGET}" "${remote_command}"
  else
    printf '%s' "${LOGIN_TOKEN}" | "${CONTAINER_CLI}" login "${REGISTRY_HOST}" --username "${LOGIN_USER}" --password-stdin
  fi
}

engine_push() {
  if [[ "${REMOTE_MODE}" -eq 1 ]]; then
    ssh_run "${CONTAINER_CLI}" push "$1"
  else
    "${CONTAINER_CLI}" push "$1"
  fi
}

build_local() {
  local build_cmd=("${CONTAINER_CLI}" build -f "${DOCKERFILE_PATH}")
  local tag label

  for tag in "${BUILD_TAGS[@]}"; do
    build_cmd+=(-t "${tag}")
  done

  for label in "${BUILD_LABELS[@]}"; do
    build_cmd+=(--label "${label}")
  done

  if [[ -n "${PLATFORM}" ]]; then
    build_cmd+=(--platform "${PLATFORM}")
  fi

  if [[ ${#BUILD_OPTS[@]} -gt 0 ]]; then
    build_cmd+=("${BUILD_OPTS[@]}")
  fi

  build_cmd+=("${IMAGE_DIR}")
  "${build_cmd[@]}"
}

build_remote() {
  local build_cmd remote_command tag label
  build_cmd=("${CONTAINER_CLI}" build -f Dockerfile)

  for tag in "${BUILD_TAGS[@]}"; do
    build_cmd+=(-t "${tag}")
  done

  for label in "${BUILD_LABELS[@]}"; do
    build_cmd+=(--label "${label}")
  done

  if [[ -n "${PLATFORM}" ]]; then
    build_cmd+=(--platform "${PLATFORM}")
  fi

  if [[ ${#BUILD_OPTS[@]} -gt 0 ]]; then
    build_cmd+=("${BUILD_OPTS[@]}")
  fi

  build_cmd+=(.)
  shell_join remote_command "${build_cmd[@]}"

  # Extract only for the lifetime of the remote build so Docker and Podman
  # both get a normal directory context with Dockerfile ignore behavior.
  remote_command=$(
    printf '%s' 'set -eu; '
    printf '%s' 'build_context="$(mktemp -d "${TMPDIR:-/tmp}/oci-build-context.XXXXXX")"; '
    printf '%s' 'cleanup() { rm -rf "${build_context}"; }; trap cleanup EXIT; '
    printf '%s' 'tar -xf - -C "${build_context}"; cd "${build_context}"; '
    printf '%s' "${remote_command}"
  )

  tar -C "${IMAGE_DIR}" -cf - . | ssh "${BUILDER_TARGET}" "${remote_command}"
}

write_promotion_manifest() {
  local manifest_path origin_safe engine_safe source_safe
  local repository_safe image_dir_safe image_name_safe registry_safe context_safe created_safe

  [[ "${REGISTRY}" == "ghcr" ]] || die "--emit-promotion is currently supported only for GHCR"

  mkdir -p "${PROMOTION_DIR}"
  manifest_path="${PROMOTION_DIR}/${IMAGE_NAME}.json"

  origin_safe="$(json_escape "${BUILD_ORIGIN}")"
  engine_safe="$(json_escape "${CONTAINER_CLI}")"
  source_safe="$(json_escape "${SOURCE_IMAGE}")"
  repository_safe="$(json_escape "${REPO}")"
  image_dir_safe="$(json_escape "${IMAGE_NAME_RAW}")"
  image_name_safe="$(json_escape "${IMAGE_NAME}")"
  registry_safe="$(json_escape "${REGISTRY}")"
  context_safe="$(json_escape "${CONTEXT_HASH}")"
  created_safe="$(json_escape "${CREATED_AT}")"

  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "image_dir": "%s",\n' "${image_dir_safe}"
    printf '  "image_name": "%s",\n' "${image_name_safe}"
    printf '  "registry": "%s",\n' "${registry_safe}"
    printf '  "repository": "%s",\n' "${repository_safe}"
    printf '  "source_image": "%s",\n' "${source_safe}"
    printf '  "build_origin": "%s",\n' "${origin_safe}"
    printf '  "build_engine": "%s",\n' "${engine_safe}"
    printf '  "context_sha256": "%s",\n' "${context_safe}"
    printf '  "created_at": "%s"\n' "${created_safe}"
    printf '}\n'
  } > "${manifest_path}"

  echo "Wrote promotion manifest: ${manifest_path}"
}

CONFIG_FILE="${DOCKER_BUILDER_SECRETS:-${HOME}/.config/.docker-builder-secrets}"
LOAD_CONFIG=1
MODE="${1:-}"
IMAGE_REF="${2:-}"

if [[ "${MODE}" == "-h" || "${MODE}" == "--help" || -z "${MODE}" ]]; then
  usage
  exit 0
fi

if [[ -z "${IMAGE_REF}" ]]; then
  usage
  die "missing required <image-directory>"
fi

shift 2 || true
ORIGINAL_ARGS=("$@")

idx=0
while [[ ${idx} -lt ${#ORIGINAL_ARGS[@]} ]]; do
  case "${ORIGINAL_ARGS[$idx]}" in
    --config)
      next=$((idx + 1))
      [[ ${next} -lt ${#ORIGINAL_ARGS[@]} ]] || die "--config requires a value"
      CONFIG_FILE="${ORIGINAL_ARGS[$next]}"
      idx=$((idx + 2))
      ;;
    --no-config)
      LOAD_CONFIG=0
      idx=$((idx + 1))
      ;;
    *)
      idx=$((idx + 1))
      ;;
  esac
done

if [[ "${LOAD_CONFIG}" -eq 1 ]]; then
  load_config_file "${CONFIG_FILE}"
fi

REGISTRY="${DEFAULT_REGISTRY:-ghcr}"
IMAGE_ROOT="${IMAGE_ROOT:-images}"
IMAGE_ROOT="${IMAGE_ROOT%/}"
DATE_TAG="$(date +%Y%m%d)"
BUILDER_MODE="${BUILDER_MODE:-auto}"
BUILDER_TARGET="${BUILDER_TARGET:-}"
CONTAINER_CLI="${BUILDER_ENGINE:-}"
PLATFORM=""
TEST_SHELL="/bin/bash"
DO_LOGIN=0
BUILD_OPTS=()
REMOTE_MODE=0
BUILD_ORIGIN="${BUILD_ORIGIN:-}"
PROMOTION_DIR="${PROMOTION_DIR:-.github/promotions}"
EMIT_PROMOTION=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--registry)
      [[ $# -ge 2 ]] || die "--registry requires a value"
      REGISTRY="$2"
      shift 2
      ;;
    --builder)
      [[ $# -ge 2 ]] || die "--builder requires a value"
      BUILDER_MODE="$2"
      shift 2
      ;;
    --host|--target)
      [[ $# -ge 2 ]] || die "--host requires a value"
      BUILDER_TARGET="$2"
      shift 2
      ;;
    --engine)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      CONTAINER_CLI="$2"
      shift 2
      ;;
    --date-tag)
      [[ $# -ge 2 ]] || die "--date-tag requires a value"
      DATE_TAG="$2"
      shift 2
      ;;
    --origin)
      [[ $# -ge 2 ]] || die "--origin requires a value"
      BUILD_ORIGIN="$2"
      shift 2
      ;;
    --platform)
      [[ $# -ge 2 ]] || die "--platform requires a value"
      PLATFORM="$2"
      shift 2
      ;;
    --shell)
      [[ $# -ge 2 ]] || die "--shell requires a value"
      TEST_SHELL="$2"
      shift 2
      ;;
    --login)
      DO_LOGIN=1
      shift
      ;;
    --build-opt)
      [[ $# -ge 2 ]] || die "--build-opt requires a value"
      BUILD_OPTS+=("$2")
      shift 2
      ;;
    --emit-promotion)
      EMIT_PROMOTION=1
      shift
      ;;
    --promotion-dir)
      [[ $# -ge 2 ]] || die "--promotion-dir requires a value"
      PROMOTION_DIR="$2"
      shift 2
      ;;
    --config)
      shift 2
      ;;
    --no-config)
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

case "${MODE}" in
  test|push) ;;
  *) die "mode must be 'test' or 'push'" ;;
esac

case "${BUILDER_MODE}" in
  auto|local|ssh) ;;
  *) die "--builder must be one of: auto, local, ssh" ;;
esac

case "${REGISTRY}" in
  ghcr|dockerhub) ;;
  *) die "--registry must be one of: ghcr, dockerhub" ;;
esac

if [[ "${EMIT_PROMOTION}" -eq 1 && "${MODE}" != "push" ]]; then
  die "--emit-promotion can only be used with push mode"
fi

IMAGE_REF="${IMAGE_REF%/}"
if [[ "${IMAGE_REF}" == ./* ]]; then
  IMAGE_REF="${IMAGE_REF#./}"
fi

if [[ "${IMAGE_REF}" == "${IMAGE_ROOT}/"* ]]; then
  IMAGE_NAME_RAW="${IMAGE_REF#${IMAGE_ROOT}/}"
  IMAGE_DIR="${IMAGE_REF}"
else
  IMAGE_NAME_RAW="${IMAGE_REF}"
  IMAGE_DIR="${IMAGE_ROOT}/${IMAGE_REF}"
fi

[[ -d "${IMAGE_DIR}" ]] || die "image directory '${IMAGE_DIR}' does not exist"
DOCKERFILE_PATH="${IMAGE_DIR}/Dockerfile"
[[ -f "${DOCKERFILE_PATH}" ]] || die "Dockerfile not found at '${DOCKERFILE_PATH}'"

require_cmd tar
require_cmd tr
require_cmd awk

if [[ ! "${DATE_TAG}" =~ ^[0-9]{8}$ ]]; then
  die "--date-tag must be in YYYYMMDD format"
fi

if [[ "${BUILDER_MODE}" == "auto" ]]; then
  if [[ -n "${BUILDER_TARGET}" ]]; then
    BUILDER_MODE="ssh"
  else
    BUILDER_MODE="local"
  fi
fi

if [[ "${BUILDER_MODE}" == "ssh" ]]; then
  [[ -n "${BUILDER_TARGET}" ]] || die "--builder ssh requires --host or BUILDER_TARGET"
  REMOTE_MODE=1
  require_cmd ssh

  if [[ -z "${CONTAINER_CLI}" ]]; then
    CONTAINER_CLI="$(
      ssh "${BUILDER_TARGET}" \
        'if command -v docker >/dev/null 2>&1; then printf docker; elif command -v podman >/dev/null 2>&1; then printf podman; fi'
    )"
  fi

  [[ -n "${CONTAINER_CLI}" ]] || die "neither docker nor podman found on SSH builder '${BUILDER_TARGET}'"
  ssh_run command -v "${CONTAINER_CLI}" >/dev/null || die "container CLI '${CONTAINER_CLI}' is not available on SSH builder '${BUILDER_TARGET}'"
else
  if [[ -z "${CONTAINER_CLI}" ]]; then
    if command -v docker >/dev/null 2>&1; then
      CONTAINER_CLI="docker"
    elif command -v podman >/dev/null 2>&1; then
      CONTAINER_CLI="podman"
    else
      die "neither docker nor podman found in PATH"
    fi
  fi

  require_cmd "${CONTAINER_CLI}"
fi

if [[ -z "${BUILD_ORIGIN}" ]]; then
  if [[ "${REMOTE_MODE}" -eq 1 ]]; then
    BUILD_ORIGIN="aws"
  else
    BUILD_ORIGIN="local"
  fi
fi

BUILD_ORIGIN="$(sanitize_ref_component "${BUILD_ORIGIN}")"
IMAGE_NAME="$(sanitize_ref_component "${IMAGE_NAME_RAW}")"
CONTEXT_HASH="$(compute_context_sha256 "${IMAGE_DIR}")"
CONTEXT_SHORT="${CONTEXT_HASH:0:12}"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_REVISION="$(git rev-parse HEAD 2>/dev/null || printf unknown)"
GIT_SOURCE="$(repo_source_url)"

REGISTRY_HOST=""
REPO=""
LOGIN_USER=""
LOGIN_TOKEN=""

case "${REGISTRY}" in
  ghcr)
    GHCR_OWNER="${GHCR_OWNER:-}"
    [[ -n "${GHCR_OWNER}" ]] || die "GHCR_OWNER is required for --registry ghcr"
    REGISTRY_HOST="ghcr.io"
    REPO="${REGISTRY_HOST}/$(sanitize_ref_component "${GHCR_OWNER}")/${IMAGE_NAME}"
    LOGIN_USER="${GHCR_USER:-}"
    LOGIN_TOKEN="${GHCR_TOKEN:-}"
    ;;
  dockerhub)
    DOCKERHUB_USER="${DOCKERHUB_USER:-}"
    [[ -n "${DOCKERHUB_USER}" ]] || die "DOCKERHUB_USER is required for --registry dockerhub"
    REGISTRY_HOST="docker.io"
    REPO="${REGISTRY_HOST}/$(sanitize_ref_component "${DOCKERHUB_USER}")/${IMAGE_NAME}"
    LOGIN_USER="${DOCKERHUB_USER}"
    LOGIN_TOKEN="${DOCKERHUB_TOKEN:-}"
    ;;
esac

DATE_IMAGE="${REPO}:${DATE_TAG}"
LATEST_IMAGE="${REPO}:latest"
SOURCE_IMAGE="${REPO}:${BUILD_ORIGIN}-${DATE_TAG}-${CONTEXT_SHORT}"
ORIGIN_DATE_IMAGE="${REPO}:external-${BUILD_ORIGIN}-${DATE_TAG}"
BUILD_TAGS=("${DATE_IMAGE}" "${LATEST_IMAGE}" "${SOURCE_IMAGE}" "${ORIGIN_DATE_IMAGE}")
BUILD_LABELS=(
  "org.opencontainers.image.created=${CREATED_AT}"
  "org.opencontainers.image.revision=${GIT_REVISION}"
  "org.opencontainers.image.source=${GIT_SOURCE}"
  "org.opencontainers.image.title=${IMAGE_NAME}"
  "edu.wustl.dhslab.build.origin=${BUILD_ORIGIN}"
  "edu.wustl.dhslab.build.engine=${CONTAINER_CLI}"
  "edu.wustl.dhslab.build.context_sha256=${CONTEXT_HASH}"
)

echo "Container CLI : ${CONTAINER_CLI}"
echo "Mode          : ${MODE}"
if [[ "${REMOTE_MODE}" -eq 1 ]]; then
  echo "Builder       : ssh://${BUILDER_TARGET}"
else
  echo "Builder       : local"
fi
echo "Registry      : ${REGISTRY} (${REGISTRY_HOST})"
echo "Dockerfile    : ${DOCKERFILE_PATH}"
echo "Origin        : ${BUILD_ORIGIN}"
echo "Context hash  : ${CONTEXT_HASH}"
echo "Image tags:"
printf '  %s\n' "${BUILD_TAGS[@]}"

if [[ "${DO_LOGIN}" -eq 1 ]]; then
  [[ -n "${LOGIN_USER}" ]] || die "login user is empty for registry '${REGISTRY}'"
  [[ -n "${LOGIN_TOKEN}" ]] || die "login token is empty for registry '${REGISTRY}'"
  echo "Logging in to ${REGISTRY_HOST} as ${LOGIN_USER}"
  engine_login
fi

echo "Building image..."
if [[ "${REMOTE_MODE}" -eq 1 ]]; then
  build_remote
else
  build_local
fi

if [[ "${MODE}" == "test" ]]; then
  echo "Launching interactive test shell (${TEST_SHELL}) in ${SOURCE_IMAGE}"
  if [[ "${REMOTE_MODE}" -eq 1 ]]; then
    RUN_CMD=""
    shell_join RUN_CMD "${CONTAINER_CLI}" run --rm -it --entrypoint "${TEST_SHELL}" "${SOURCE_IMAGE}"
    exec ssh -tt "${BUILDER_TARGET}" "${RUN_CMD}"
  else
    exec "${CONTAINER_CLI}" run --rm -it --entrypoint "${TEST_SHELL}" "${SOURCE_IMAGE}"
  fi
fi

for image in "${BUILD_TAGS[@]}"; do
  echo "Pushing ${image}"
  engine_push "${image}"
done

if [[ "${EMIT_PROMOTION}" -eq 1 ]]; then
  write_promotion_manifest
fi

echo "Done: pushed ${#BUILD_TAGS[@]} tags for ${REPO}"
