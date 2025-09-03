#!/bin/bash

set -ouex pipefail

systemctl enable podman.socket
systemctl disable pcscd.socket
