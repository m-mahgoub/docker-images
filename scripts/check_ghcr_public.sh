#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/check_ghcr_public.sh [options] [image ...]

Checks whether GHCR container images are anonymously pullable.
No GitHub token is required or used.

Options:
  --owner <owner>        GHCR owner/user/org. Defaults to GHCR_OWNER or git remote owner.
  --tag <tag>            Tag to check. Default: latest.
  --image-root <dir>     Directory containing image folders. Default: IMAGE_ROOT or images.
  -h, --help             Show this help.

Examples:
  scripts/check_ghcr_public.sh --owner my-lab basetools fibertools
  scripts/check_ghcr_public.sh --owner my-lab --tag latest
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found in PATH"
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

owner_from_git_remote() {
  local remote path

  remote="$(git config --get remote.origin.url 2>/dev/null || true)"
  [[ -n "${remote}" ]] || return 0

  case "${remote}" in
    git@github.com:*)
      path="${remote#git@github.com:}"
      ;;
    https://github.com/*)
      path="${remote#https://github.com/}"
      ;;
    *)
      return 0
      ;;
  esac

  path="${path%.git}"
  printf '%s' "${path%%/*}"
}

discover_images() {
  local dockerfile dir

  shopt -s nullglob
  for dockerfile in "${IMAGE_ROOT}"/*/Dockerfile; do
    dir="$(dirname "${dockerfile}")"
    basename "${dir}"
  done
}

check_image_public() {
  local image="$1"
  local token_tmp manifest_tmp token_http manifest_http token
  local scope="repository:${OWNER}/${image}:pull"
  local manifest_url="https://ghcr.io/v2/${OWNER}/${image}/manifests/${TAG}"

  token_tmp="$(mktemp)"
  manifest_tmp="$(mktemp)"

  token_http="$(
    curl -sS -o "${token_tmp}" -w '%{http_code}' -G \
      --data-urlencode 'service=ghcr.io' \
      --data-urlencode "scope=${scope}" \
      https://ghcr.io/token || true
  )"

  if [[ "${token_http}" != "200" ]]; then
    printf 'NOT_PUBLIC\t%s/%s:%s\tanonymous token request returned HTTP %s\n' \
      "${OWNER}" "${image}" "${TAG}" "${token_http}"
    rm -f "${token_tmp}" "${manifest_tmp}"
    return 1
  fi

  token="$(jq -r '.token // empty' "${token_tmp}")"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    printf 'NOT_PUBLIC\t%s/%s:%s\tanonymous token response did not include a token\n' \
      "${OWNER}" "${image}" "${TAG}"
    rm -f "${token_tmp}" "${manifest_tmp}"
    return 1
  fi

  manifest_http="$(
    curl -sS -o "${manifest_tmp}" -w '%{http_code}' \
      -H "Authorization: Bearer ${token}" \
      -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
      "${manifest_url}" || true
  )"

  case "${manifest_http}" in
    200)
      printf 'PUBLIC\t%s/%s:%s\tanonymous manifest request succeeded\n' \
        "${OWNER}" "${image}" "${TAG}"
      rm -f "${token_tmp}" "${manifest_tmp}"
      return 0
      ;;
    404)
      printf 'NOT_FOUND\t%s/%s:%s\tpackage or tag was not found anonymously\n' \
        "${OWNER}" "${image}" "${TAG}"
      rm -f "${token_tmp}" "${manifest_tmp}"
      return 1
      ;;
    *)
      printf 'NOT_PUBLIC\t%s/%s:%s\tanonymous manifest request returned HTTP %s\n' \
        "${OWNER}" "${image}" "${TAG}" "${manifest_http}"
      rm -f "${token_tmp}" "${manifest_tmp}"
      return 1
      ;;
  esac
}

OWNER="${GHCR_OWNER:-}"
TAG="latest"
IMAGE_ROOT="${IMAGE_ROOT:-images}"
IMAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)
      [[ $# -ge 2 ]] || die "--owner requires a value"
      OWNER="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    --image-root)
      [[ $# -ge 2 ]] || die "--image-root requires a value"
      IMAGE_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        IMAGES+=("$1")
        shift
      done
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      IMAGES+=("$1")
      shift
      ;;
  esac
done

require_cmd curl
require_cmd jq
require_cmd git
require_cmd tr

IMAGE_ROOT="${IMAGE_ROOT%/}"

if [[ -z "${OWNER}" ]]; then
  OWNER="$(owner_from_git_remote)"
fi

[[ -n "${OWNER}" ]] || die "could not determine GHCR owner; pass --owner or set GHCR_OWNER"
OWNER="$(sanitize_ref_component "${OWNER}")"

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  mapfile -t IMAGES < <(discover_images)
fi

[[ ${#IMAGES[@]} -gt 0 ]] || die "no images provided and none found under '${IMAGE_ROOT}'"

failures=0
for image in "${IMAGES[@]}"; do
  image="$(sanitize_ref_component "${image}")"
  check_image_public "${image}" || failures=$((failures + 1))
done

if [[ "${failures}" -gt 0 ]]; then
  echo
  echo "One or more images are not anonymously pullable from GHCR."
  echo "For public cluster execution, make the package public or remove stale GHCR credentials that force a bad authenticated pull."
  exit 1
fi
