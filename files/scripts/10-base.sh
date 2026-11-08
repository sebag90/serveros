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

# Auto-create user home directories:
# 1. Configure useradd to create home directories by default
sed -i 's/^CREATE_HOME.*/CREATE_HOME yes/' /etc/login.defs || echo "CREATE_HOME yes" >> /etc/login.defs

# 2. Enable PAM mkhomedir so first-time logins auto-create home from /etc/skel if missing
authselect select local with-mkhomedir --force || true

# Essential server tooling
dnf install -y git

# Examples:
# dnf install -y 'dnf-command(config-manager)'
# dnf config-manager --set-enabled crb
#
# Server-y things you may want:
# dnf install -y firewalld && systemctl enable firewalld   # not in the base image
# dnf install -y cockpit cockpit-podman && systemctl enable --now cockpit.socket

echo "Hello, headless Atomic AlmaLinux respin world!."
