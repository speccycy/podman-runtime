#!/usr/bin/env bash
set -euo pipefail
umask 022

REPO="speccycy/podman-runtime"
RELEASE_TAG="v6.1.2-1"
PODMAN_VERSION="6.1.2"
ARCH="amd64"
DEB="podman-runtime_6.1.2_amd64.deb"
SHA256SUMS="SHA256SUMS"

EXPECTED_DEB_SHA256="bc5dacab001ef19d5a390cedb01f87e720d02a64436f211ca59e561e0cff49cd"
EXPECTED_SUMS_SHA256="bbecdd07a2ee8b92307338cdff74726068090e93b95c0dbbb1c8a910914280b2"

BASE_URL="https://github.com/$REPO/releases/download/$RELEASE_TAG"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

service_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

require_root() {
  [ "$EUID" -eq 0 ] || fail "Run this installer as root."
}

verify_platform() {
  [ -r /etc/os-release ] || fail "Cannot identify operating system."
  # shellcheck disable=SC1091
  . /etc/os-release

  [ "${ID:-}" = "debian" ] || fail "Debian is required; found '${ID:-unknown}'."
  [ "${VERSION_ID:-}" = "13" ] || fail "Debian 13 is required; found '${VERSION_ID:-unknown}'."
  [ "$(dpkg --print-architecture)" = "$ARCH" ] ||
    fail "This release supports amd64 only; found '$(dpkg --print-architecture)'."
}

require_commands() {
  local cmd
  for cmd in apt-get curl dpkg-query sha256sum systemctl; do
    command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
  done
}

capture_service_state() {
  DOCKER_WAS_ACTIVE=0
  CONTAINERD_WAS_ACTIVE=0
  CLOUDFLARED_WAS_ACTIVE=0
  AMP_WAS_ACTIVE=0
  DOCKER_CONTAINERS_BEFORE=""

  if service_active docker; then
    DOCKER_WAS_ACTIVE=1
    command -v docker >/dev/null 2>&1 || fail "Docker service is active but docker command is missing."
    DOCKER_CONTAINERS_BEFORE="$(docker ps -q | sort)"
  fi
  service_active containerd && CONTAINERD_WAS_ACTIVE=1 || true
  service_active cloudflared && CLOUDFLARED_WAS_ACTIVE=1 || true
  service_active ampinstmgr && AMP_WAS_ACTIVE=1 || true
}

verify_no_legacy_source_install() {
  local path
  for path in     /usr/local/bin/podman     /usr/local/bin/podman-remote     /usr/local/libexec/podman/netavark     /usr/local/libexec/podman/aardvark-dns     /opt/infh-podman-build
  do
    [ ! -e "$path" ] || fail "Legacy source-built Podman artifact still exists: $path"
  done

  if dpkg-query -W -f='${Status}' podman-runtime 2>/dev/null |
      grep -q '^install ok installed$'; then
    local installed_version
    installed_version="$(dpkg-query -W -f='${Version}' podman-runtime)"
    [ "$installed_version" = "$PODMAN_VERSION" ] ||
      fail "podman-runtime is already installed at version $installed_version."

    echo "podman-runtime $installed_version is already installed."
    return 10
  fi

  if command -v podman >/dev/null 2>&1; then
    fail "Another Podman installation is already present at $(command -v podman)."
  fi
}

download_and_verify() {
  local dir="$1"

  echo "==> Downloading pinned release $RELEASE_TAG"
  curl --fail --location --proto '=https' --tlsv1.2     "$BASE_URL/$DEB"     --output "$dir/$DEB"

  curl --fail --location --proto '=https' --tlsv1.2     "$BASE_URL/$SHA256SUMS"     --output "$dir/$SHA256SUMS"

  echo "==> Verifying release asset digests"
  echo "$EXPECTED_DEB_SHA256  $dir/$DEB" | sha256sum --check -
  echo "$EXPECTED_SUMS_SHA256  $dir/$SHA256SUMS" | sha256sum --check -

  (
    cd "$dir"
    grep -F "  $DEB" "$SHA256SUMS" >/dev/null ||
      fail "SHA256SUMS does not contain $DEB."
    sha256sum --check --ignore-missing "$SHA256SUMS"
  )
}

install_package() {
  local deb_path="$1"

  echo "==> Installing Podman runtime package"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y "$deb_path"
  systemctl daemon-reload
}

verify_runtime() {
  echo "==> Verifying installed runtime"

  local package_version podman_path podman_version cgroup_version network_backend
  package_version="$(dpkg-query -W -f='${Version}' podman-runtime)"
  [ "$package_version" = "$PODMAN_VERSION" ] ||
    fail "Installed package version is $package_version; expected $PODMAN_VERSION."

  podman_path="$(command -v podman || true)"
  [ "$podman_path" = "/usr/bin/podman" ] ||
    fail "Expected /usr/bin/podman; found '${podman_path:-missing}'."

  podman_version="$(podman --version | awk '{print $3}')"
  [ "$podman_version" = "$PODMAN_VERSION" ] ||
    fail "Expected Podman $PODMAN_VERSION; found $podman_version."

  /usr/libexec/podman/netavark --version | grep -F "2.1.0" >/dev/null ||
    fail "Netavark 2.1.0 verification failed."

  /usr/libexec/podman/aardvark-dns --version | grep -F "2.1.0" >/dev/null ||
    fail "Aardvark DNS 2.1.0 verification failed."

  podman info >/dev/null

  cgroup_version="$(podman info --format '{{.Host.CgroupsVersion}}')"
  [ "$cgroup_version" = "v2" ] ||
    fail "Expected cgroup v2; found '$cgroup_version'."

  network_backend="$(podman info --format '{{.Host.NetworkBackend}}')"
  [ "$network_backend" = "netavark" ] ||
    fail "Expected Netavark network backend; found '$network_backend'."
}

verify_protected_services() {
  echo "==> Verifying existing services were not disrupted"

  if [ "$DOCKER_WAS_ACTIVE" -eq 1 ]; then
    service_active docker || fail "Docker was active before install but is not active now."
    docker ps >/dev/null || fail "Docker is active but docker ps failed."

    local docker_containers_after
    docker_containers_after="$(docker ps -q | sort)"
    [ "$docker_containers_after" = "$DOCKER_CONTAINERS_BEFORE" ] ||
      fail "The set of running Docker containers changed during Podman installation."
  fi

  if [ "$CONTAINERD_WAS_ACTIVE" -eq 1 ]; then
    service_active containerd ||
      fail "containerd was active before install but is not active now."
  fi

  if [ "$CLOUDFLARED_WAS_ACTIVE" -eq 1 ]; then
    service_active cloudflared ||
      fail "cloudflared was active before install but is not active now."
  fi

  if [ "$AMP_WAS_ACTIVE" -eq 1 ]; then
    service_active ampinstmgr ||
      fail "AMP Instance Manager was active before install but is not active now."
  fi
}

main() {
  require_root
  verify_platform
  require_commands
  capture_service_state

  if verify_no_legacy_source_install; then
    :
  else
    rc=$?
    if [ "$rc" -eq 10 ]; then
      verify_runtime
      verify_protected_services
      echo "Podman runtime is already installed and verified."
      exit 0
    fi
    exit "$rc"
  fi

  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  download_and_verify "$tmp"
  install_package "$tmp/$DEB"
  verify_runtime
  verify_protected_services

  echo
  echo "Podman runtime installed successfully."
  echo "Release:  $RELEASE_TAG"
  echo "Package:  podman-runtime $PODMAN_VERSION"
  echo "Podman:   $(podman --version)"
  echo "Path:     $(command -v podman)"
  echo "Netavark: $(/usr/libexec/podman/netavark --version)"
  echo "Aardvark: $(/usr/libexec/podman/aardvark-dns --version)"
  echo
  echo "Podman socket/service is not enabled automatically."
}

main "$@"
