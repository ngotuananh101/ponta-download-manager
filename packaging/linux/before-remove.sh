#!/bin/sh
# fpm --before-remove: drop the PATH symlink.
rm -f /usr/bin/pdm
