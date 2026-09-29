# Install on Debian 13

The supported production path is to install the approved GitHub Release package.
Do not build Podman on the production server.

## Supported release

- Release: `v6.1.2-2`
- Debian: 13 (trixie)
- Architecture: amd64
- Package: `podman-runtime_6.1.2-2_amd64.deb`

The installer pins both the release tag and the exact SHA-256 digests of the
release package and `SHA256SUMS`. Package revision `6.1.2-2` also removes the
unnecessary Debian containers-common dependency from the first release.

## Production installation

From a trusted checkout of this repository:

```bash
sudo bash scripts/install-debian13.sh
```

The installer refuses legacy source-built leftovers, downloads only the pinned
release, verifies the exact asset hashes, installs the local Debian package,
checks Podman/Netavark/Aardvark plus cgroup v2 and the Netavark backend, and
verifies that any pre-existing Docker/containerd/cloudflared/AMP services remain
healthy. If Docker was already active, the exact set of running Docker container
IDs must also remain unchanged.

The installer does not enable `podman.service` or `podman.socket`. Podman
remains daemonless unless those units are enabled separately.

## Manual package install

For troubleshooting only, download the three assets from release
`v6.1.2-2`, verify `SHA256SUMS`, then install:

```bash
sudo apt-get install ./podman-runtime_6.1.2-2_amd64.deb
```
