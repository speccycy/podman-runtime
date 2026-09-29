# podman-runtime

Build pipeline for a pinned upstream Podman runtime on Debian 13.

This repository does **not** fork or patch Podman source code. It fetches exact
upstream commits, verifies that the expected release tags still resolve to those
commits, builds them on Debian 13, packages the runtime, and publishes CI artifacts.

## Pinned upstream

- Podman 6.1.2 — `04f3aa430e6df81bea059978bc5bafbc846ba3e7`
- Netavark 2.1.0 — `8e91ad1d947ed325327b638f0cb906bea1f7d0ab`
- Aardvark DNS 2.1.0 — `cd7417681229219059939bdd9f0b3bd9ac9abb08`
- Go 1.26.0
- Rust 1.88.0

`containers/common` and `containers/image` are Go module dependencies of
Podman and are resolved from Podman's pinned `go.mod` / `go.sum`; they are
not separately installed runtime binaries.

## Outputs

GitHub Actions produces:

- `podman-runtime_<version>_<arch>.deb`
- `podman-runtime_<version>_<arch>.tar.gz`
- `SHA256SUMS`

The bundle contains Podman, rootlessport, Quadlet, Netavark, and Aardvark DNS.
System runtime dependencies such as conmon and crun remain Debian-managed.

## Local build

Run on Debian 13 with the dependencies mirrored in
`.github/workflows/build-debian13.yml`:

```bash
scripts/build.sh
scripts/package.sh
scripts/verify.sh
```

Artifacts are written to `dist/`.

## Supply-chain rules

1. Never build from a floating upstream branch.
2. Change both version/tag and exact SHA together.
3. The build fails if an upstream tag no longer resolves to the pinned SHA.
4. Do not patch upstream Podman source in this repository.
5. Review dependency/toolchain changes before changing `versions.env`.
