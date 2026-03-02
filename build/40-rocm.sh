#!/usr/bin/bash
set -eoux pipefail

echo "::group:: Install ROCm Runtime and Utilities"
dnf5 install -y --skip-unavailable \
    rocm-core \
    rocm-runtime \
    rocm-device-libs \
    rocm-hip-runtime \
    rocm-opencl-runtime \
    rocm-smi \
    rocm-clinfo \
    rocminfo
echo "::endgroup::"
