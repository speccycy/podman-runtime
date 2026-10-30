#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"

STAGE="$ROOT/work/stage"
DIST="$ROOT/dist"
. /etc/os-release
case "$ID:$VERSION_ID" in
  debian:13) PLATFORM=debian13 ;;
  ubuntu:24.04) PLATFORM=ubuntu24.04 ;;
  ubuntu:26.04) PLATFORM=ubuntu26.04 ;;
  *) echo "Unsupported verification host: $ID $VERSION_ID" >&2; exit 1 ;;
esac

test -x "$STAGE/usr/bin/podman"
test -x "$STAGE/usr/libexec/podman/rootlessport"
test -x "$STAGE/usr/libexec/podman/quadlet"
test -x "$STAGE/usr/libexec/podman/netavark"
test -x "$STAGE/usr/libexec/podman/aardvark-dns"
test -x "$STAGE/usr/libexec/podman/crun"
test -f "$STAGE/usr/share/containers/containers.conf.d/99-infh-pinned-crun.conf"
if [ "$PLATFORM" = ubuntu26.04 ]; then
  nft_conf="$STAGE/usr/share/containers/containers.conf.d/98-infh-netavark-nftables.conf"
  test -f "$nft_conf"
  grep -Fx '[network]' "$nft_conf"
  grep -Fx 'firewall_driver = "nftables"' "$nft_conf"
else
  test ! -e "$STAGE/usr/share/containers/containers.conf.d/98-infh-netavark-nftables.conf"
fi
test -f "$STAGE/usr/share/containers/containers.conf"
test -f "$STAGE/usr/share/containers/seccomp.json"
test -f "$STAGE/usr/share/containers/policy.json"
test -f "$STAGE/usr/share/containers/registries.conf"
test -f "$STAGE/usr/share/containers/registries.d/default.yaml"

"$STAGE/usr/bin/podman" --version | grep -F "podman version $PODMAN_VERSION"
"$STAGE/usr/libexec/podman/netavark" --version | grep -F "$NETAVARK_VERSION"
"$STAGE/usr/libexec/podman/aardvark-dns" --version | grep -F "$AARDVARK_VERSION"
"$STAGE/usr/libexec/podman/crun" --version | grep -F "$CRUN_VERSION"

grep -F "podman_sha=$PODMAN_SHA" "$STAGE/BUILD-METADATA"
grep -F "netavark_sha=$NETAVARK_SHA" "$STAGE/BUILD-METADATA"
grep -F "aardvark_sha=$AARDVARK_SHA" "$STAGE/BUILD-METADATA"
grep -F "crun_sha=$CRUN_SHA" "$STAGE/BUILD-METADATA"
grep -F "common_sha=$COMMON_SHA" "$STAGE/BUILD-METADATA"
grep -F "image_sha=$IMAGE_SHA" "$STAGE/BUILD-METADATA"
grep -F "package_revision=$PACKAGE_REVISION" "$STAGE/BUILD-METADATA"
grep -Fx "build_platform=$ID:$VERSION_ID" "$STAGE/BUILD-METADATA"

(
  cd "$DIST"
  sha256sum -c "SHA256SUMS.$PLATFORM"
)

deb="$DIST/podman-runtime_${PODMAN_VERSION}-${PACKAGE_REVISION}_${PLATFORM}_$(dpkg --print-architecture).deb"
test -f "$deb"
dpkg-deb --info "$deb"
test "$(dpkg-deb -f "$deb" Version)" = "$PODMAN_VERSION-$PACKAGE_REVISION"
test "$(dpkg-deb -f "$deb" Architecture)" = "amd64"
depends="$(dpkg-deb -f "$deb" Depends)"
case "$PLATFORM" in
  ubuntu26.04) echo "$depends" | grep -F "libgpgme45"; echo "$depends" | grep -F "libsubid5" ;;
  ubuntu24.04) echo "$depends" | grep -F "libgpgme11t64"; echo "$depends" | grep -F "libsubid4" ;;
  debian13) echo "$depends" | grep -F "libgpgme11t64"; echo "$depends" | grep -F "libsubid5" ;;
esac
case "$depends" in
  *golang-github-containers-common*|*netavark*|*aardvark-dns*)
    echo "unexpected distro container-stack dependency: $depends" >&2
    exit 1
    ;;
esac
dpkg-deb --contents "$deb" | grep -E '/usr/bin/podman$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/netavark$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/aardvark-dns$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/crun$'
dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/containers.conf.d/99-infh-pinned-crun.conf$'
if [ "$PLATFORM" = ubuntu26.04 ]; then
  dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/containers.conf.d/98-infh-netavark-nftables.conf$'
fi
dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/containers.conf$'
dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/seccomp.json$'
dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/policy.json$'
dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/registries.conf$'
dpkg-deb --contents "$deb" | grep -E '/usr/share/containers/registries.d/default.yaml$'

echo "==> Verification passed"
