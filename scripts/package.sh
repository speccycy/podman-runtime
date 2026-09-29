#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"

STAGE="$ROOT/work/stage"
DIST="$ROOT/dist"
ARCH="$(dpkg --print-architecture)"
PKGROOT="$ROOT/work/pkg"
VERSION="$PODMAN_VERSION"

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
Depends: conmon, crun | runc, golang-github-containers-common, init-system-helpers, libc6, libgpgme11t64, libseccomp2, libsqlite3-0, libsubid5
Recommends: uidmap, passt, slirp4netns, fuse-overlayfs, iptables, nftables
Conflicts: podman
Replaces: podman
Provides: podman
Description: Pinned upstream Podman runtime bundle for Debian 13
 Podman $PODMAN_VERSION with Netavark $NETAVARK_VERSION and
 Aardvark DNS $AARDVARK_VERSION, built from exact upstream commits.
EOF

dpkg-deb --root-owner-group --build "$PKGROOT" \
  "$DIST/podman-runtime_${VERSION}_${ARCH}.deb"

tar --sort=name \
  --mtime="@$(stat -c %Y "$STAGE/BUILD-METADATA")" \
  --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" -czf "$DIST/podman-runtime_${VERSION}_${ARCH}.tar.gz" .

(
  cd "$DIST"
  sha256sum *.deb *.tar.gz > SHA256SUMS
)

echo "==> Packages written to $DIST"
