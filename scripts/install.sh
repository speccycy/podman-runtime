#!/usr/bin/env bash
# Universal, pinned release installer. Supported: Debian 13 and Ubuntu 24.04 amd64.
set -euo pipefail
umask 022

REPO="speccycy/podman-runtime"
RELEASE_TAG="v6.1.4-2"
PODMAN_VERSION="6.1.4"
PACKAGE_VERSION="6.1.4-2"
DRY_RUN=0

usage() {
  cat <<'EOF'
Podman runtime installer (Debian 13 / Ubuntu 24.04, amd64)

Usage:
  sudo bash install.sh
  sudo bash install.sh --dry-run

The installer selects the correct native package, validates release digests,
simulates the apt transaction and checks existing container services.
It will not replace an actively running Podman workload.
EOF
}

fail() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "==> $*"; }
service_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --dry-run) DRY_RUN=1 ;;
  "") ;;
  *) usage >&2; fail "Unknown argument: $1" ;;
esac

[ "$EUID" -eq 0 ] || fail "Run with sudo: sudo bash install.sh"
[ -r /etc/os-release ] || fail "Cannot identify operating system"
. /etc/os-release
case "$ID:$VERSION_ID" in
  debian:13) PLATFORM="debian13" ;;
  ubuntu:24.04) PLATFORM="ubuntu24.04" ;;
  *) fail "Unsupported OS: $ID $VERSION_ID. Supported: Debian 13, Ubuntu 24.04." ;;
esac
[ "$(dpkg --print-architecture)" = amd64 ] || fail "Only amd64 (x86_64) is supported"

for cmd in curl python3 sha256sum dpkg-query apt-get systemctl mktemp; do
  command -v "$cmd" >/dev/null 2>&1 ||
    fail "Missing $cmd. Install prerequisites: sudo apt-get update && sudo apt-get install -y curl python3 ca-certificates"
done

PKG="podman-runtime_${PACKAGE_VERSION}_${PLATFORM}_amd64.deb"
API_URL="https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG"
BASE_URL="https://github.com/$REPO/releases/download/$RELEASE_TAG"

check_legacy() {
  for path in /usr/local/bin/podman /usr/local/bin/podman-remote \
    /usr/local/libexec/podman/netavark /usr/local/libexec/podman/aardvark-dns \
    /opt/infh-podman-build; do
    [ ! -e "$path" ] || fail "Legacy source-built file exists: $path (review and migrate first)"
  done
}

check_running_podman() {
  if command -v podman >/dev/null 2>&1; then
    local current
    current="$(podman ps --format '{{.ID}}')" ||
      fail "Cannot inspect existing Podman containers; installation stopped"
    [ -z "$current" ] ||
      fail "Podman containers are running. Plan a maintenance window and stop affected services first."
  fi
}

capture_services() {
  DOCKER_ACTIVE=0; CONTAINERD_ACTIVE=0; CLOUDFLARED_ACTIVE=0; AMP_ACTIVE=0
  DOCKER_IDS=""
  if service_active docker; then
    DOCKER_ACTIVE=1
    command -v docker >/dev/null 2>&1 || fail "Docker active but CLI missing"
    DOCKER_IDS="$(docker ps -q | sort)"
  fi
  if service_active containerd; then CONTAINERD_ACTIVE=1; fi
  if service_active cloudflared; then CLOUDFLARED_ACTIVE=1; fi
  if service_active ampinstmgr; then AMP_ACTIVE=1; fi
}

check_services() {
  if [ "$DOCKER_ACTIVE" -eq 1 ]; then
    service_active docker || fail "Docker stopped unexpectedly"
    test "$(docker ps -q | sort)" = "$DOCKER_IDS" ||
      fail "Running Docker container set changed during installation"
  fi
  if [ "$CONTAINERD_ACTIVE" -eq 1 ]; then
    service_active containerd || fail "containerd stopped unexpectedly"
  fi
  if [ "$CLOUDFLARED_ACTIVE" -eq 1 ]; then
    service_active cloudflared || fail "cloudflared stopped unexpectedly"
  fi
  if [ "$AMP_ACTIVE" -eq 1 ]; then
    service_active ampinstmgr || fail "AMP instance manager stopped unexpectedly"
  fi
}

verify_runtime() {
  note "Verifying installed Podman runtime"
  local version
  version="$(dpkg-query -W -f='${Version}' podman-runtime 2>/dev/null || true)"
  [ "$version" = "$PACKAGE_VERSION" ] ||
    fail "Installed package is '$version' (expected $PACKAGE_VERSION)"
  [ "$(command -v podman)" = "/usr/bin/podman" ] ||
    fail "Unexpected Podman binary path"
  podman --version | grep -F "podman version $PODMAN_VERSION" >/dev/null ||
    fail "Podman binary version mismatch"
  /usr/libexec/podman/netavark --version | grep -F 2.1.0 >/dev/null ||
    fail "Netavark version mismatch"
  /usr/libexec/podman/aardvark-dns --version | grep -F 2.1.0 >/dev/null ||
    fail "Aardvark DNS version mismatch"
  [ "$(podman info --format '{{.Host.CgroupsVersion}}')" = "v2" ] ||
    fail "Podman requires cgroup v2"
  [ "$(podman info --format '{{.Host.NetworkBackend}}')" = "netavark" ] ||
    fail "Unexpected Podman network backend"
}

note "Detected $PRETTY_NAME / amd64"
check_legacy
capture_services

installed="$(dpkg-query -W -f='${Status} ${Version}' podman-runtime 2>/dev/null || true)"
if [ "$installed" = "install ok installed $PACKAGE_VERSION" ] && [ "$DRY_RUN" -eq 0 ]; then
  verify_runtime
  check_services
  note "Already installed and verified: $PACKAGE_VERSION"
  exit 0
fi
if [ -z "$installed" ] && command -v podman >/dev/null 2>&1; then
  fail "A non-podman-runtime Podman installation exists. Review migration before replacing it."
fi
check_running_podman

TMPDIR_INSTALL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_INSTALL"' EXIT
chmod 0755 "$TMPDIR_INSTALL"

note "Fetching verified release metadata $RELEASE_TAG"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  -H 'Accept: application/vnd.github+json' \
  "$API_URL" -o "$TMPDIR_INSTALL/release.json"

digest_pair="$(python3 - "$TMPDIR_INSTALL/release.json" "$PKG" "$RELEASE_TAG" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("tag_name") != sys.argv[3] or data.get("draft") or data.get("prerelease"):
    sys.exit("Incorrect or unapproved GitHub release metadata")
assets = {a.get("name"): a for a in data.get("assets", [])}
def digest(name):
    item = assets.get(name)
    if not item:
        sys.exit("Missing release asset: " + name)
    value = item.get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", value):
        sys.exit("Release asset missing a SHA-256 digest: " + name)
    return value[7:]
print(digest(sys.argv[2]), digest("SHA256SUMS"))
PY
)"
read -r EXPECTED_DEB EXPECTED_SUMS <<< "$digest_pair"
[ "${#EXPECTED_DEB}" -eq 64 ] && [ "${#EXPECTED_SUMS}" -eq 64 ] ||
  fail "Invalid release checksums"

note "Downloading OS-specific package: $PKG"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$BASE_URL/$PKG" -o "$TMPDIR_INSTALL/$PKG"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$BASE_URL/SHA256SUMS" -o "$TMPDIR_INSTALL/SHA256SUMS"

note "Checking independent GitHub asset digests and SHA256SUMS"
echo "$EXPECTED_DEB  $TMPDIR_INSTALL/$PKG" | sha256sum -c -
echo "$EXPECTED_SUMS  $TMPDIR_INSTALL/SHA256SUMS" | sha256sum -c -
(
  cd "$TMPDIR_INSTALL"
  grep -F "  $PKG" SHA256SUMS >/dev/null ||
    fail "Package not listed in SHA256SUMS"
  sha256sum -c --ignore-missing SHA256SUMS
)
chmod 0644 "$TMPDIR_INSTALL/$PKG" "$TMPDIR_INSTALL/SHA256SUMS"

note "Reviewing package operations (no changes yet)"
apt-get update
apt-get -s install "$TMPDIR_INSTALL/$PKG" | tee "$TMPDIR_INSTALL/apt-plan.txt"

while IFS= read -r line; do
  case "$line" in
    Remv\ *)
      name="${line#Remv }"; name="${name%% *}"
      case "$name" in
        podman|podman-remote|netavark|aardvark-dns|golang-github-containers-common|golang-github-containers-image) ;;
        *) fail "APT wants to remove unrelated package '$name'. Review manually." ;;
      esac
      ;;
  esac
done < "$TMPDIR_INSTALL/apt-plan.txt"

if [ "$DRY_RUN" -eq 1 ]; then
  note "Dry run complete. No package installed."
  exit 0
fi

note "Installing $PACKAGE_VERSION for $PLATFORM"
DEBIAN_FRONTEND=noninteractive apt-get install -y "$TMPDIR_INSTALL/$PKG"
systemctl daemon-reload
verify_runtime
check_services

echo
echo "Podman runtime $PACKAGE_VERSION installed and verified successfully."
echo "Platform: $PRETTY_NAME"
echo "Podman: $(podman --version)"
echo "Package: $PKG"
echo "No Podman service/socket was enabled automatically."
