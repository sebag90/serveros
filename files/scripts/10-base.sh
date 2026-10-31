#!/usr/bin/env bash

set -xeuo pipefail

# Start customizing your image here

# This is a headless server image: the base layer has no GNOME, no display manager
# and no X11/Wayland. Boot straight to multi-user rather than waiting on a
# graphical session that will never come up.
ln -sf /usr/lib/systemd/system/multi-user.target /etc/systemd/system/default.target

# sshd is installed in the base image and enabled by default preset, but a
# headless box is only reachable over the network, so be explicit about it.
systemctl enable sshd.service

# Examples:
# dnf install -y 'dnf-command(config-manager)'
# dnf config-manager --set-enabled crb
#
# Server-y things you may want:
# dnf install -y firewalld && systemctl enable firewalld   # not in the base image
# dnf install -y cockpit cockpit-podman && systemctl enable --now cockpit.socket

echo "Hello, headless Atomic AlmaLinux respin world!."
