# Base Image - configurable via build arg for multi-variant builds
# ARG must be before any FROM to be usable in FROM instructions
ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin-dx:latest

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

FROM ${BASE_IMAGE}

## Build variants:
# nedtop:        ghcr.io/ublue-os/bluefin-dx:latest (default)
# nedtop-nvidia: ghcr.io/ublue-os/bluefin-dx-nvidia:latest
#
# Other possible base images:
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.
COPY system_files /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh && \
    ostree container commit
    
### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
