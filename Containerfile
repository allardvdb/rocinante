ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin:stable
# Pre-built kmod RPMs for the kernel ${BASE_IMAGE} ships. Bind-mounted
# during the build RUN; nothing from this stage ends up in the final
# image layer. The version is supplied by the workflow via skopeo
# inspect of ${BASE_IMAGE}'s ostree.linux label — there is no local
# kernel pin.
ARG BASE_KERNEL
FROM ghcr.io/ublue-os/akmods:coreos-stable-43-${BASE_KERNEL} AS akmods-src

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
ARG BASE_KERNEL
ARG FIRMWARE_VERSION=20260309
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=bind,from=akmods-src,source=/,target=/akmods-src \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    BASE_IMAGE=${BASE_IMAGE} \
    BASE_KERNEL=${BASE_KERNEL} \
    FIRMWARE_VERSION=${FIRMWARE_VERSION} \
    /ctx/build/10-build.sh

RUN bootc container lint
