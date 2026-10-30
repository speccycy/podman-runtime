# Installation — Debian 13 / Ubuntu 24.04 / Ubuntu 26.04 (amd64)

For a step-by-step Thai guide, see [INSTALL_TH.md](INSTALL_TH.md).

## Requirements

- Debian 13 (Trixie), Ubuntu 24.04 LTS (Noble) **or** Ubuntu 26.04 LTS (Resolute), 64-bit Intel/AMD.
- `sudo`, internet access to GitHub and your distro's APT repositories.
- cgroup v2, Netavark backend.
- For upgrades: backups and a maintenance window. Stop running Podman containers and review **rootless** containers and Quadlet units separately.

## Install in three commands (after prerequisites)

```bash
sudo apt-get update && sudo apt-get install -y ca-certificates curl python3
curl -fsSL https://raw.githubusercontent.com/speccycy/podman-runtime/main/scripts/install.sh -o podman-install.sh
sudo bash podman-install.sh
```

The script prints the OS and selected file; checks that the versioned release exists, that the package hash matches GitHub's independent asset digest and `SHA256SUMS`; displays APT's simulated package changes; refuses unexpected package removals and active Podman workloads; installs and verifies Podman 6.1.4, Netavark 2.1.0, Aardvark DNS 2.1.0 and private crun 1.30.1; and confirms protected Docker/containerd/cloudflared/AMP services were not interrupted.

Preview only: `sudo bash podman-install.sh --dry-run`.

Podman uses `/usr/libexec/podman/crun` bundled with the runtime; `/usr/bin/crun` from the OS is unchanged. Custom `/etc/containers` overrides can change runtime selection and are detected by the installer.

The runtime is daemonless by default. The script does **not** automatically enable `podman.socket` or `podman.service`.

## Troubleshooting

- **Unsupported OS**: do not install the Debian .deb manually on Ubuntu or vice versa.
- **Previous distro Podman detected**: inspect `podman ps -a`, `podman images`, `podman volume ls`, rootless containers and Quadlet units; back up and plan a controlled migration before uninstalling the distro package. Automatic removal is intentionally disabled.
- **Podman containers running**: stop the affected services during maintenance and retry.
- **APT wants to remove unrelated software**: stop and review the simulation; never force dependency removal on a production host.
- **GitHub release not found**: the new multi-OS release is not yet published; do not bypass checksum verification.
- **Ubuntu missing conmon/crun**: ensure Ubuntu `universe` is enabled, then run `sudo apt-get update` and retry.
- **After installation**: check `podman --version`, `podman info`, `sudo podman run --rm docker.io/library/alpine:3.21 echo OK`, and your systemd/Quadlet services.

## Exact release

- Intended tag: `v6.1.4-3` (must be published after successful CI).
- Debian asset: `podman-runtime_6.1.4-3_debian13_amd64.deb`
- Ubuntu 24.04 asset: `podman-runtime_6.1.4-3_ubuntu24.04_amd64.deb`
- Ubuntu 26.04 asset: `podman-runtime_6.1.4-3_ubuntu26.04_amd64.deb`
- Repository: https://github.com/speccycy/podman-runtime/releases

**Release pending:** Do not use these new asset names until Owner approval, successful CI and publication.

The installer uses GitHub's per-asset SHA-256 digest as a pinned-release integrity check; `SHA256SUMS` alone is not treated as an independent trust anchor. Existing production workloads are not upgraded automatically by merging the repository.
