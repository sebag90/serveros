#!/usr/bin/env bash
# Runs at the end of the live image build (atomic-ci `hook-script`).
#
# Configures a headless live environment that boots directly into an interactive
# text installer on the console (display, serial, or SSH) without desktop bloat.
set -euo pipefail

ISO_YAML=/usr/lib/image-builder/bootc/iso.yaml

# 1. Pre-seed default keyboard and language configuration for Anaconda.
# In a headless environment without a desktop session, Anaconda must have
# default localization in interactive-defaults.ks so it does not attempt to
# query GNOME Shell's gsettings via a non-existent desktop live user.
cat >> /usr/share/anaconda/interactive-defaults.ks <<'EOKS'

keyboard --vckeymap=de --xlayouts='de'
lang en_US.UTF-8
EOKS

# Set German keyboard layout for the live console
echo 'KEYMAP="de"' > /etc/vconsole.conf

# 2. Ensure liveuser account exists in /etc/passwd so any user lookups succeed.
if ! id -u liveuser >/dev/null 2>&1; then
  useradd -m -c "Live System User" -G wheel liveuser || true
  passwd -d liveuser >/dev/null 2>&1 || true
fi
passwd -d root >/dev/null 2>&1 || true

# 3. Check for desktop live environment (local build with a desktop base).
if compgen -G "/usr/share/wayland-sessions/*.desktop" >/dev/null ||
   compgen -G "/usr/share/xsessions/*.desktop" >/dev/null; then
  mkdir -p /etc/xdg/autostart
  cat > /etc/xdg/autostart/liveinst.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Install
Comment=Install the system to the hard disk
Exec=/usr/bin/liveinst
TryExec=/usr/bin/liveinst
NoDisplay=true
X-GNOME-AutoRestart=false
EOF
  echo "hook: desktop live environment detected, Anaconda will autostart in the session"
  exit 0
fi

# 4. Headless live installer:
# Upstream /usr/bin/liveinst was designed for desktop live media and hardcodes
# "anaconda --liveinst --graphical". On a headless server:
# - "--liveinst" calls screensaver inhibition (which fails without a desktop session)
#   and sets provides_liveuser=True (which queries GNOME Shell input sources).
# - "--graphical" attempts to launch a GUI where no display server exists.
#
# Replace both /usr/bin/liveinst and /usr/sbin/liveinst with a headless wrapper that:
# - Strips --graphical and --liveinst.
# - Guarantees --text.
# - Drops empty arguments.
# - Loads storage kernel modules.
# - Directly launches anaconda in text mode.
cat > /usr/bin/liveinst <<'EOF'
#!/bin/bash
set -e

args=()
has_text=false
for a in "$@"; do
  [ -z "$a" ] && continue
  [ "$a" = "--graphical" ] && continue
  [ "$a" = "-G" ] && continue
  [ "$a" = "--liveinst" ] && continue
  [ "$a" = "--text" ] && has_text=true
  [ "$a" = "-T" ] && has_text=true
  args+=("$a")
done

if [ "$has_text" = false ]; then
  args+=("--text")
fi

if [ -z "${PKEXEC_UID:-}" ]; then
  LIVE_UID=$(id -u liveuser 2>/dev/null || echo 1000)
  export PKEXEC_UID="${LIVE_UID}"
fi

for mod in raid0 raid1 raid5 raid6 raid456 raid10 dm-mod dm-zero dm-mirror dm-snapshot dm-multipath dm-round-robin vfat dm-crypt cbc sha256 lrw xts iscsi_tcp iscsi_ibft; do
  /sbin/modprobe "$mod" 2>/dev/null || true
done

exec /usr/sbin/anaconda "${args[@]}"
EOF
chmod 0755 /usr/bin/liveinst
cp -f /usr/bin/liveinst /usr/sbin/liveinst

# 5. Enable root autologin on console (tty1) and serial console (ttyS0).
# Instead of running Anaconda as an early-boot systemd oneshot unit (which has no
# real TTY, blocks boot, and causes black screens with blinking cursors), we let
# systemd boot normally to multi-user.target, autologin root, and start the text
# installer cleanly inside a real login session.
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
Type=idle
EOF

mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
cat > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --keep-baud 115200,38400,9600 --autologin root %I $TERM
Type=idle
EOF

# Clean up any leftover oneshot drop-ins on livesys-late
rm -rf /etc/systemd/system/livesys-late.service.d

# 6. Auto-start the installer upon root console login.
# If the user cancels or exits the installer, they get dropped into a functional root shell.
cat > /etc/profile.d/serveros-installer.sh <<'EOF'
if [ "$(id -u)" -eq 0 ] && [ -z "${SERVEROS_INSTALLER_RAN:-}" ] && [ -t 0 ]; then
  case "$(tty 2>/dev/null)" in
    /dev/tty1|/dev/ttyS0|/dev/console)
      export SERVEROS_INSTALLER_RAN=1
      echo ""
      echo "=================================================="
      echo "   Starting ServerOS Headless Installer...        "
      echo "=================================================="
      echo ""
      /usr/bin/liveinst || true
      echo ""
      echo "Installer exited. Run 'liveinst' to restart it."
      echo ""
      ;;
  esac
fi
EOF
chmod 0644 /etc/profile.d/serveros-installer.sh

# 7. Enable passwordless SSH in the live environment for headless convenience.
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-live.conf <<'EOF'
PermitRootLogin yes
PermitEmptyPasswords yes
EOF

# 8. Skip plymouth in livesys-late if plymouth is not installed.
if ! command -v plymouth >/dev/null 2>&1; then
  sed -i -E 's|^(\s*)plymouth --quit$|\1:|' /usr/libexec/livesys/livesys-late
fi

# 9. Update iso.yaml:
# - Remove 'quiet rhgb' (which causes a black screen with blinking cursor on headless hardware).
# - Add 'audit=0' to suppress SELinux AVC audit denial messages from spamming the console.
# - Add 'vconsole.keymap=de' to load German keyboard during early boot.
# - Add serial and virtual console outputs so boot progress and installer are visible everywhere.
sed -i -E \
  's/rd\.live\.image enforcing=0 quiet rhgb( nomodeset)?/rd.live.image enforcing=0 audit=0 vconsole.keymap=de console=tty0 console=ttyS0,115200\1/' \
  "${ISO_YAML}"

grep -n 'linux:' "${ISO_YAML}"
ls -l /usr/sbin/liveinst /usr/bin/liveinst
