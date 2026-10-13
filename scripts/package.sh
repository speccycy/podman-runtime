#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"

STAGE="$ROOT/work/stage"
DIST="$ROOT/dist"
ARCH="$(dpkg --print-architecture)"
PKGROOT="$ROOT/work/pkg"
VERSION="$PODMAN_VERSION-$PACKAGE_REVISION"
. /etc/os-release
case "$ID:$VERSION_ID" in
  debian:13) PLATFORM=debian13; SUBID_PKG=libsubid5 ;;
  ubuntu:24.04) PLATFORM=ubuntu24.04; SUBID_PKG=libsubid4 ;;
  *) echo "Unsupported packaging host: $ID $VERSION_ID" >&2; exit 1 ;;
esac
[ "$ARCH" = amd64 ] || { echo "Only amd64 supported" >&2; exit 1; }

test -x "$STAGE/usr/bin/podman" || {
  echo "build output missing; run scripts/build.sh first" >&2
  exit 1
}

rm -rf "$DIST" "$PKGROOT"
mkdir -p "$DIST" "$PKGROOT/DEBIAN"
cp -a "$STAGE/." "$PKGROOT/"

cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: podman-runtime
Version: $VERSION
Section: admin
Priority: optional
Architecture: $ARCH
Maintainer: speccycy
Depends: conmon, crun | runc, init-system-helpers, libc6, libdevmapper1.02.1, libgpgme11t64, libseccomp2, libsqlite3-0, $SUBID_PKG
Recommends: uidmap, passt, slirp4netns, fuse-overlayfs, iptables, nftables
Conflicts: podman, podman-remote, golang-github-containers-common, golang-github-containers-image, netavark, aardvark-dns
Replaces: podman, podman-remote, golang-github-containers-common, golang-github-containers-image, netavark, aardvark-dns
Provides: podman
Description: Pinned upstream Podman runtime bundle for $PLATFORM
 Podman $PODMAN_VERSION with Netavark $NETAVARK_VERSION and
 Aardvark DNS $AARDVARK_VERSION, built from exact upstream commits.
EOF

dpkg-deb --root-owner-group --build "$PKGROOT" \
  "$DIST/podman-runtime_${VERSION}_${PLATFORM}_${ARCH}.deb"

tar --sort=name \
  --mtime="@$(stat -c %Y "$STAGE/BUILD-METADATA")" \
  --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" -czf "$DIST/podman-runtime_${VERSION}_${PLATFORM}_${ARCH}.tar.gz" .

(
  cd "$DIST"
  sha256sum *.deb *.tar.gz > "SHA256SUMS.$PLATFORM"
)

echo "==> Packages written to $DIST"
