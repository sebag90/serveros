# ba0fde3d-bee7-4307-b97b-17d0d20aff50
# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx

COPY files/system /system_files/
COPY --chmod=0755 files/scripts /build_files/
COPY *.pub /keys/

# Base Image
# Headless AlmaLinux server base: no GNOME, no display manager, no X11/Wayland.
# Roughly equivalent to a minimal server install (systemd + kernel + dnf + sshd).
#
# The default amd64 build of AlmaLinux 10 requires an x86-64-v3 CPU (Haswell/Excavator
# or newer). This is the -amd64_v2 variant, built for the x86-64-v2 baseline, so it
# also runs on older hardware (Sandy Bridge/Ivy Bridge, pre-Haswell VMs, etc.).
# The variant is only published with dated tags; bump both tag and digest when updating.
FROM quay.io/almalinuxorg/almalinux-bootc:10.2-20261031-amd64_v2

ARG IMAGE_NAME
ARG IMAGE_REGISTRY
ARG VARIANT

RUN --mount=type=tmpfs,dst=/opt \
    --mount=type=tmpfs,dst=/tmp \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build_files/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
