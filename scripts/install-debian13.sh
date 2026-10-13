#!/usr/bin/env bash
# Compatibility entry point for existing Debian deployment documentation.
set -euo pipefail
[ -r /etc/os-release ] || { echo "Cannot identify OS" >&2; exit 1; }
. /etc/os-release
[ "$ID:$VERSION_ID" = "debian:13" ] || {
  echo "This legacy alias is Debian 13 only; use scripts/install.sh for Ubuntu 24.04." >&2
  exit 1
}
exec bash "$(dirname "$0")/install.sh" "$@"
