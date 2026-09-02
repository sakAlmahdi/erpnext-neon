#!/usr/bin/env bash
# Build a custom ERPNext image containing the erpnext-develop source.
#
# IMPORTANT: the build context must be the frappe_docker repo, because
# images/layered/Containerfile COPYs resources/core/*.sh from that context.
# Your app source is NOT part of the context — it is fetched from Git by
# `bench init` using apps.json. That is why your repo must be pushed first.
#
# Requires: Docker Engine >= 23.0 (BuildKit default) for --secret support.

set -euo pipefail

# ---- configure these -------------------------------------------------------
IMAGE="${IMAGE:-ghcr.io/sakalmahdi/erpnext-neon}"
TAG="${TAG:-develop}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-develop}"
APPS_JSON="${APPS_JSON:-$(cd "$(dirname "$0")" && pwd)/apps.json}"
# ---------------------------------------------------------------------------

if [ ! -f "$APPS_JSON" ]; then
  echo "ERROR: apps.json not found at $APPS_JSON" >&2
  exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Cloning frappe_docker (build context) into $WORKDIR"
git clone --depth 1 https://github.com/frappe/frappe_docker "$WORKDIR/frappe_docker"

echo "==> Building $IMAGE:$TAG  (frappe branch: $FRAPPE_BRANCH)"
docker build \
  --no-cache \
  --build-arg="FRAPPE_PATH=https://github.com/frappe/frappe" \
  --build-arg="FRAPPE_BRANCH=${FRAPPE_BRANCH}" \
  --build-arg="FRAPPE_IMAGE_PREFIX=frappe" \
  --secret="id=apps_json,src=${APPS_JSON}" \
  --tag="${IMAGE}:${TAG}" \
  --file="$WORKDIR/frappe_docker/images/layered/Containerfile" \
  "$WORKDIR/frappe_docker"

echo
echo "==> Built ${IMAGE}:${TAG}"
echo "    Next: docker push ${IMAGE}:${TAG}"
echo "    Then set CUSTOM_IMAGE=${IMAGE} and CUSTOM_TAG=${TAG} in Coolify."
