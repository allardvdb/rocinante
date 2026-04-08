ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin:stable
# Pinned kernel to avoid AMD MES scheduler hang on Strix Point / gfx1150.
# See docs/amdgpu-strix-point-gpu-hang.md and build/05-kernel-pin.sh.
ARG KERNEL_PIN=6.17.12-300.fc43.x86_64
ARG AKMODS_FLAVOR=coreos-stable-43

# Akmods sources for the pinned kernel. These stages are only pulled to
# provide the kernel + matching kmod RPMs via bind mounts during the RUN
# step; nothing from them ends up in the final image layer.
FROM ghcr.io/ublue-os/akmods:${AKMODS_FLAVOR}-${KERNEL_PIN} AS akmods-src
FROM ghcr.io/ublue-os/akmods-zfs:${AKMODS_FLAVOR}-${KERNEL_PIN} AS akmods-zfs-src
FROM ghcr.io/ublue-os/akmods-nvidia-open:${AKMODS_FLAVOR}-${KERNEL_PIN} AS akmods-nvidia-open-src

FROM scratch AS ctx
COPY build /build
COPY custom /custom
COPY SKILL.md /SKILL.md
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /oci/brew

FROM ${BASE_IMAGE}

## Build variants:
# rocinante:        ghcr.io/ublue-os/bluefin:stable (default)
# rocinante-nvidia: ghcr.io/ublue-os/bluefin-nvidia-open:stable
# rocinante-aurora: ghcr.io/ublue-os/aurora:stable

ARG BASE_IMAGE
ARG KERNEL_PIN
ARG FIRMWARE_VERSION=20260309
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=akmods-src,source=/,target=/akmods-src \
    --mount=type=bind,from=akmods-zfs-src,source=/,target=/akmods-zfs-src \
    --mount=type=bind,from=akmods-nvidia-open-src,source=/,target=/akmods-nvidia-open-src \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    BASE_IMAGE=${BASE_IMAGE} \
    KERNEL_PIN=${KERNEL_PIN} \
    FIRMWARE_VERSION=${FIRMWARE_VERSION} \
    /ctx/build/10-build.sh

RUN bootc container lint
