#!/usr/bin/env bash
# Runs at the end of the live image build (atomic-ci `hook-script`).
#
# This respin is headless: the live environment has no desktop session, so
# livesys never autostarts Anaconda and you end up at a plain login prompt.
# livesys-late starts `/usr/sbin/liveinst --text` when it sees `textinst` on
# the kernel command line, so add that to the ISO's boot entries. Anaconda's
# text UI then comes up by itself on the console.
#
# `anaconda-live` itself is already installed by the atomic-ci live build.
set -euo pipefail

ISO_YAML=/usr/lib/image-builder/bootc/iso.yaml

sed -i -E \
  's/(rd\.live\.image enforcing=0 quiet rhgb)( nomodeset)?/\1 textinst\2/' \
  "${ISO_YAML}"

if ! grep -q 'textinst' "${ISO_YAML}"; then
  echo "hook: failed to add textinst to ${ISO_YAML}" >&2
  exit 1
fi

grep -n 'linux:' "${ISO_YAML}"
