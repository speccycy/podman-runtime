# Podman Runtime 6.1.4

Native Podman runtime packages for **Debian 13 (Trixie)** and **Ubuntu 24.04 LTS (Noble)**, x86_64/amd64.

**ภาษาไทย:** [คู่มือติดตั้งแบบทีละขั้น](INSTALL_TH.md) | **English:** [Installation guide](INSTALL.md)

The project builds exact upstream commits on **each target OS separately**. It includes Podman, Quadlet, Netavark, Aardvark DNS and a Podman-private crun 1.30.1 built for each OS. The host conmon remains APT-managed. This avoids Ubuntu 24.04's older crun failing to understand the OCI spec emitted by Podman 6.1.4, without replacing /usr/bin/crun used by other software. The upstream Podman source is not modified.

## Easy installation

On a fresh Debian 13 or Ubuntu 24.04 server:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl python3
curl -fsSL https://raw.githubusercontent.com/speccycy/podman-runtime/main/scripts/install.sh -o podman-install.sh
sudo bash podman-install.sh
```

The installer automatically detects the OS and downloads the **matching native package** from a fixed versioned GitHub Release. It cross-checks its SHA-256 with GitHub asset metadata and SHA256SUMS, simulates the APT transaction, and verifies the runtime and protected services. Do not pipe an unreviewed download directly into `sudo bash`.

To preview without installing: `sudo bash podman-install.sh --dry-run`.

**Important:** Stop running Podman workloads and plan a maintenance window for an upgrade. The installer refuses active rootful containers and unknown source-built or distro Podman installations; see the migration section in the guide. Rootless user workloads require separate administrator review.

## Supported platforms and assets

| OS | Architecture | Release asset |
| --- | --- | --- |
| Debian 13 | amd64 | `podman-runtime_6.1.4-2_debian13_amd64.deb` |
| Ubuntu 24.04 LTS | amd64 | `podman-runtime_6.1.4-2_ubuntu24.04_amd64.deb` |

The `v6.1.4-2` release assets become installable **only after** both native builds and CI tests pass and GitHub publishes the release. Until then, use the last verified platform-specific release for Debian; Ubuntu is not approved.

### Pinned upstream versions

- Podman 6.1.4 — `464c15fec06f0074c916f9eff87c4806869c2833`
- Netavark 2.1.0 — `8e91ad1d947ed325327b638f0cb906bea1f7d0ab`
- Aardvark DNS 2.1.0 — `cd7417681229219059939bdd9f0b3bd9ac9abb08`
- crun 1.30.1 — `079ff6a7a16d029460af882f9ea44674e6a510b6` (includes recent security fixes)
- Go 1.26.0 and Rust 1.88.0 are **CI build tools**, not required on production hosts.

Podman's upstream dependencies use the pinned go.mod/go.sum. Note that the upstream gvproxy 0.9.0 CVE fix **does not install gvproxy**: this runtime bundle does not ship that binary.

## CI and release

`.github/workflows/build-runtime.yml` runs:
1. Native Debian 13 and Ubuntu 24.04 source builds, package validation and SHA-256 generation.
2. Clean install smoke tests on each OS.
3. Ubuntu host container-run smoke test and upgrade from Ubuntu distro Podman.
4. Debian upgrade tests from previous release packages.
5. Release publishing **only after all jobs succeed on main/tag pushes**.

GitHub Release includes both .deb packages, both tarballs and a combined `SHA256SUMS`. Builds use versioned `versions.env` pins. The production server does not need a compiler.

This repository manages the **Podman runtime**, not the INFH-WEB application release. The INFH-WEB deployment documentation has a separate acceptance gate.
