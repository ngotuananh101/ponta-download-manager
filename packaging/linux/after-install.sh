#!/bin/sh
# fpm --after-install: put the launcher on PATH.
set -e
ln -sf /opt/pdm/pdm /usr/bin/pdm
