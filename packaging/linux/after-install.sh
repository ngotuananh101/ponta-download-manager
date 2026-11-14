#!/bin/sh
# fpm --after-install: put the launcher on PATH.
# Do not register browsers here: package hooks run as root, whereas native
# messaging manifests belong to each desktop user's home. The bundled host
# and extension are registered by PDM on the user's first release launch.
set -e
ln -sf /opt/pdm/pdm /usr/bin/pdm
