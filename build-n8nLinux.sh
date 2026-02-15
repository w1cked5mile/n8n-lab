#!/usr/bin/env bash
set -euo pipefail

# Provision a local n8n instance inside Docker on a Linux workstation.
# Mirrors the container configuration used by build-n8nWSL.ps1.

if [[ ${EUID} -ne 0 ]]; then
  echo "This script must be run as root (try prefixing with sudo)." >&2
  exit 1
fi

readonly WORKSPACE_DIR=${WORKSPACE_DIR:-/opt/n8n_lab}
readonly DATA_DIR=${DATA_DIR:-"${WORKSPACE_DIR}/n8n_data"}
readonly NETWORK_NAME=${NETWORK_NAME:-n8n-network}
readonly CONTAINER_NAME=${CONTAINER_NAME:-n8n}
readonly IMAGE_REF=${IMAGE_REF:-n8nio/n8n:latest}
readonly HOST_PORT=${HOST_PORT:-5678}
readonly TZ_VALUE=${TZ_VALUE:-UTC}

log_step() {
  local message=$1
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "${message}"
}

ensure_prerequisites() {
  umask 077
  mkdir -p "${WORKSPACE_DIR}" "${DATA_DIR}"
}

install_docker_if_missing() {
  if command -v docker >/dev/null 2>&1; then
    log_step 'Docker is already installed.'
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    echo 'Docker is not installed and automatic installation only supports apt-based systems. Install Docker manually and rerun.' >&2
    exit 1
  fi

  log_step 'Installing Docker dependencies (apt).'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  local codename
  codename=$(lsb_release -cs)
  printf 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' "${codename}" \
    >/etc/apt/sources.list.d/docker.list

  log_step 'Installing Docker Engine (apt).'
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker.service
}

prepare_runtime() {
  log_step 'Ensuring Docker daemon is running.'
  systemctl restart docker.service

  log_step 'Creating dedicated Docker network if missing.'
  if ! docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
    docker network create "${NETWORK_NAME}"
  fi

  log_step 'Preparing persistent data directory.'
  chown 1000:1000 "${DATA_DIR}"
  chmod 0770 "${DATA_DIR}"

  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_step 'Existing n8n container found; removing it.'
    docker rm -f "${CONTAINER_NAME}"
  fi
}

start_container() {
  log_step 'Pulling latest n8n image.'
  docker pull "${IMAGE_REF}"

  log_step 'Starting n8n container.'
  docker run -d \
    --name "${CONTAINER_NAME}" \
    --restart unless-stopped \
    --network "${NETWORK_NAME}" \
    -p "${HOST_PORT}:5678" \
    -v "${DATA_DIR}:/home/node/.n8n" \
    -e TZ="${TZ_VALUE}" \
    "${IMAGE_REF}"
}

main() {
  log_step 'Provisioning n8n Docker configuration for Linux.'
  ensure_prerequisites
  install_docker_if_missing
  prepare_runtime
  start_container
  log_step 'n8n container is running. Access it at http://localhost:'"${HOST_PORT}"'/'
}

main "$@"
