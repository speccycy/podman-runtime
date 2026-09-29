#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"

STAGE="$ROOT/work/stage"
DIST="$ROOT/dist"

test -x "$STAGE/usr/bin/podman"
test -x "$STAGE/usr/libexec/podman/rootlessport"
test -x "$STAGE/usr/libexec/podman/quadlet"
test -x "$STAGE/usr/libexec/podman/netavark"
test -x "$STAGE/usr/libexec/podman/aardvark-dns"
test -f "$STAGE/usr/share/containers/containers.conf"
test -f "$STAGE/usr/share/containers/seccomp.json"
test -f "$STAGE/usr/share/containers/policy.json"
test -f "$STAGE/usr/share/containers/registries.conf"
test -f "$STAGE/usr/share/containers/registries.d/default.yaml"

"$STAGE/usr/bin/podman" --version | grep -F "podman version $PODMAN_VERSION"
"$STAGE/usr/libexec/podman/netavark" --version | grep -F "$NETAVARK_VERSION"
"$STAGE/usr/libexec/podman/aardvark-dns" --version | grep -F "$AARDVARK_VERSION"

grep -F "podman_sha=$PODMAN_SHA" "$STAGE/BUILD-METADATA"
grep -F "netavark_sha=$NETAVARK_SHA" "$STAGE/BUILD-METADATA"
grep -F "aardvark_sha=$AARDVARK_SHA" "$STAGE/BUILD-METADATA"
grep -F "common_sha=$COMMON_SHA" "$STAGE/BUILD-METADATA"
grep -F "image_sha=$IMAGE_SHA" "$STAGE/BUILD-METADATA"
grep -F "package_revision=$PACKAGE_REVISION" "$STAGE/BUILD-METADATA"

(
  cd "$DIST"
  sha256sum -c SHA256SUMS
)

deb="$(find "$DIST" -maxdepth 1 -name 'podman-runtime_*.deb' -print -quit)"
test -n "$deb"
dpkg-deb --info "$deb"
test "$(dpkg-deb -f "$deb" Version)" = "$PODMAN_VERSION-$PACKAGE_REVISION"
depends="$(dpkg-deb -f "$deb" Depends)"
case "$depends" in
  *golang-github-containers-common*|*netavark*|*aardvark-dns*)
    echo "unexpected distro container-stack dependency: $depends" >&2
    exit 1
    ;;
esac
dpkg-deb --contents "$deb" | grep -E '/usr/bin/podman$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/netavark$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/aardvark-dns
echo "==> Verification passed"

dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/containers.conf
echo "==> Verification passed"

dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/seccomp.json
echo "==> Verification passed"

dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/policy.json
echo "==> Verification passed"

dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/registries.conf
echo "==> Verification passed"

dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/registries.d/default.yaml
echo "==> Verification passed"


echo "==> Verification passed"
