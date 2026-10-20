#!/bin/zsh
# Installs a local development build as "Tiley Dev" so it is distinguishable
# from the standalone Tiley.app in Finder and System Settings > Login Items.
# The plain build_and_install_app.sh (display name "Tiley") is reserved for
# the real install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Tiley Dev}" exec "$SCRIPT_DIR/build_and_install_app.sh"
