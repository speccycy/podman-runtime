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
clone_exact "$CRUN_REPO" "$CRUN_TAG" "$CRUN_SHA" "$SRC/crun"
clone_exact "$CONTAINER_LIBS_REPO" "$COMMON_TAG" "$COMMON_SHA" "$SRC/container-libs-common"
clone_exact "$CONTAINER_LIBS_REPO" "$IMAGE_TAG" "$IMAGE_SHA" "$SRC/container-libs-image"

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
make -C "$SRC/podman" PREFIX=/usr -j"$JOBS" podman rootlessport quadlet
make -C "$SRC/podman" PREFIX=/usr DESTDIR="$STAGE" \
  install.bin install.systemd install.completions

echo "==> Building Netavark"
(
  cd "$SRC/netavark"
  CARGO_TARGET_DIR=targets cargo build --release --locked
  install -D -m0755 targets/release/netavark "$STAGE/usr/libexec/podman/netavark"
)

echo "==> Building Aardvark DNS"
(
  cd "$SRC/aardvark-dns"
  CARGO_TARGET_DIR=targets cargo build --release --locked
  install -D -m0755 targets/release/aardvark-dns "$STAGE/usr/libexec/podman/aardvark-dns"
)

echo "==> Building pinned crun $CRUN_VERSION"
(
  cd "$SRC/crun"
  # Exact pinned checkout; autogen fetches the referenced submodules.
  ./autogen.sh
  ./configure --prefix=/usr --disable-shared --disable-libcrun
  make -j"$JOBS"
  install -D -m0755 crun "$STAGE/usr/libexec/podman/crun"
  "$STAGE/usr/libexec/podman/crun" --version | grep -F "$CRUN_VERSION"
)

echo "==> Installing pinned vendor configuration"
install -D -m0644   "$SRC/container-libs-common/common/pkg/config/containers.conf"   "$STAGE/usr/share/containers/containers.conf"
install -D -m0644   "$SRC/container-libs-common/common/pkg/seccomp/seccomp.json"   "$STAGE/usr/share/containers/seccomp.json"
install -D -m0644   "$SRC/container-libs-image/image/default-policy.json"   "$STAGE/usr/share/containers/policy.json"
install -D -m0644   "$SRC/container-libs-image/image/registries.conf"   "$STAGE/usr/share/containers/registries.conf"
install -D -m0644   "$SRC/container-libs-image/image/default.yaml"   "$STAGE/usr/share/containers/registries.d/default.yaml"

# Podman-only OCI runtime selection. Keep /usr/bin/crun distro-managed.
install -d -m0755 "$STAGE/usr/share/containers/containers.conf.d"
cat > "$STAGE/usr/share/containers/containers.conf.d/99-infh-pinned-crun.conf" <<EOF
[engine]
runtime = "crun"

[engine.runtimes]
crun = ["/usr/libexec/podman/crun"]
EOF

# Netavark 2.x no longer accepts the legacy iptables firewall driver.
# Ubuntu 26.04 can retain that driver from its distro Podman configuration;
# select nftables for this native package without changing older platforms.
if [ "$(. /etc/os-release; echo "$ID:$VERSION_ID")" = "ubuntu:26.04" ]; then
  cat > "$STAGE/usr/share/containers/containers.conf.d/98-infh-netavark-nftables.conf" <<'EOF'
[network]
firewall_driver = "nftables"
EOF
fi

cat > "$STAGE/BUILD-METADATA" <<EOF
podman_version=$PODMAN_VERSION
podman_sha=$PODMAN_SHA
netavark_version=$NETAVARK_VERSION
netavark_sha=$NETAVARK_SHA
aardvark_version=$AARDVARK_VERSION
aardvark_sha=$AARDVARK_SHA
crun_version=$CRUN_VERSION
crun_sha=$CRUN_SHA
common_version=$COMMON_VERSION
common_sha=$COMMON_SHA
image_version=$IMAGE_VERSION
image_sha=$IMAGE_SHA
package_revision=$PACKAGE_REVISION
build_platform=$( . /etc/os-release; echo "$ID:$VERSION_ID" )
go_version=$GO_VERSION
rust_version=$RUST_VERSION
source_date_epoch=$SOURCE_DATE_EPOCH
EOF

echo "==> Build complete"
