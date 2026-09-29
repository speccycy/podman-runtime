#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/versions.env"

WORK="$ROOT/work"
SRC="$WORK/src"
STAGE="$WORK/stage"
JOBS="${JOBS:-$(nproc)}"

rm -rf "$WORK"
mkdir -p "$SRC" "$STAGE"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

for cmd in git go cargo rustc make install sha256sum; do
  require "$cmd"
done

clone_exact() {
  local repo="$1"
  local tag="$2"
  local sha="$3"
  local dest="$4"

  git clone --filter=blob:none --no-checkout "$repo" "$dest"
  git -C "$dest" fetch --force --depth=1 origin "$sha"
  git -C "$dest" checkout --detach "$sha"

  local actual
  actual="$(git -C "$dest" rev-parse HEAD)"
  test "$actual" = "$sha" || {
    echo "SHA mismatch for $repo: expected $sha got $actual" >&2
    exit 1
  }

  local remote_tag
  remote_tag="$(git ls-remote "$repo" "refs/tags/$tag^{}" | awk 'NR==1 {print $1}')"
  if [ -z "$remote_tag" ]; then
    remote_tag="$(git ls-remote "$repo" "refs/tags/$tag" | awk 'NR==1 {print $1}')"
  fi
  test "$remote_tag" = "$sha" || {
    echo "tag $tag no longer resolves to pinned SHA $sha for $repo" >&2
    exit 1
  }
}

echo "==> Fetching exact upstream sources"
clone_exact "$PODMAN_REPO" "$PODMAN_TAG" "$PODMAN_SHA" "$SRC/podman"
clone_exact "$NETAVARK_REPO" "$NETAVARK_TAG" "$NETAVARK_SHA" "$SRC/netavark"
clone_exact "$AARDVARK_REPO" "$AARDVARK_TAG" "$AARDVARK_SHA" "$SRC/aardvark-dns"

echo "==> Verifying toolchains"
go version
rustc --version
cargo --version
test "$(go env GOVERSION)" = "go$GO_VERSION" || {
  echo "expected Go $GO_VERSION" >&2
  exit 1
}
test "$(rustc --version | awk '{print $2}')" = "$RUST_VERSION" || {
  echo "expected Rust $RUST_VERSION" >&2
  exit 1
}

echo "==> Building Podman"
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH="$(git -C "$SRC/podman" show -s --format=%ct "$PODMAN_SHA")"
make -C "$SRC/podman" -j"$JOBS" podman rootlessport quadlet
make -C "$SRC/podman" PREFIX=/usr DESTDIR="$STAGE" \
  install.bin install.systemd install.completions

echo "==> Building Netavark"
(
  cd "$SRC/netavark"
  cargo build --release --locked
  install -D -m0755 targets/release/netavark "$STAGE/usr/libexec/podman/netavark"
)

echo "==> Building Aardvark DNS"
(
  cd "$SRC/aardvark-dns"
  cargo build --release --locked
  install -D -m0755 targets/release/aardvark-dns "$STAGE/usr/libexec/podman/aardvark-dns"
)

cat > "$STAGE/BUILD-METADATA" <<EOF
podman_version=$PODMAN_VERSION
podman_sha=$PODMAN_SHA
netavark_version=$NETAVARK_VERSION
netavark_sha=$NETAVARK_SHA
aardvark_version=$AARDVARK_VERSION
aardvark_sha=$AARDVARK_SHA
go_version=$GO_VERSION
rust_version=$RUST_VERSION
source_date_epoch=$SOURCE_DATE_EPOCH
EOF

echo "==> Build complete"
