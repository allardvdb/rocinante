ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin:stable

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

ARG FIRMWARE_VERSION=20260309
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    FIRMWARE_VERSION=${FIRMWARE_VERSION} \
    /ctx/build/10-build.sh

RUN bootc container lint
