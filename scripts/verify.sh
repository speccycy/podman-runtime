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

"$STAGE/usr/bin/podman" --version | grep -F "podman version $PODMAN_VERSION"
"$STAGE/usr/libexec/podman/netavark" --version | grep -F "$NETAVARK_VERSION"
"$STAGE/usr/libexec/podman/aardvark-dns" --version | grep -F "$AARDVARK_VERSION"

grep -F "podman_sha=$PODMAN_SHA" "$STAGE/BUILD-METADATA"
grep -F "netavark_sha=$NETAVARK_SHA" "$STAGE/BUILD-METADATA"
grep -F "aardvark_sha=$AARDVARK_SHA" "$STAGE/BUILD-METADATA"

(
  cd "$DIST"
  sha256sum -c SHA256SUMS
)

deb="$(find "$DIST" -maxdepth 1 -name 'podman-runtime_*.deb' -print -quit)"
test -n "$deb"
dpkg-deb --info "$deb"
dpkg-deb --contents "$deb" | grep -E '/usr/bin/podman$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/netavark$'
dpkg-deb --contents "$deb" | grep -E '/usr/libexec/podman/aardvark-dns$'

echo "==> Verification passed"
