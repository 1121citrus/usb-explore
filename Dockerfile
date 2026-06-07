# syntax=docker/dockerfile:1

ARG BASE_IMAGE=ubuntu:24.04
ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_DATE=unknown
ARG AUTHORS="1121 Citrus"
ARG LICENSE=AGPL-3.0-or-later

# hadolint ignore=DL3006
# BASE_IMAGE defaults to ubuntu:24.04 (explicitly tagged); the ARG pattern
# is intentional to allow platform overrides at build time.
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG VERSION
ARG GIT_COMMIT
ARG BUILD_DATE
ARG AUTHORS
ARG LICENSE

# Embed build metadata as environment variables for runtime inspection
ENV APP_VERSION="${VERSION}"
ENV APP_BASE_IMAGE="${BASE_IMAGE}"
ENV APP_COMMIT="${GIT_COMMIT}"
ENV APP_BUILD_DATE="${BUILD_DATE}"

LABEL org.opencontainers.image.title="usb-explore"
LABEL org.opencontainers.image.description="Explore Linux USB disk images from macOS via Docker"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/1121citrus/usb-explore"
LABEL org.opencontainers.image.vendor="1121 Citrus"
LABEL org.opencontainers.image.licenses="${LICENSE}"
LABEL org.opencontainers.image.authors="${AUTHORS}"

# Version pinning omitted: Trivy/Grype CVE scans the final image, making
# apt version pins redundant overhead for this developer tool.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      util-linux \
      fdisk \
      e2fsprogs \
      xfsprogs \
      rsync \
      diffutils \
      file \
      jq \
 && rm -rf /var/lib/apt/lists/*

COPY src/container/ /usr/local/lib/usb-explore/

RUN chmod +x /usr/local/lib/usb-explore/*.sh \
          /usr/local/lib/usb-explore/drivers/*.sh \
 && mkdir -p /mnt/part /out /ref

# Runs as root: losetup and mount require CAP_SYS_ADMIN.
# See SECURITY.md for the full explanation.
ENTRYPOINT ["/usr/local/lib/usb-explore/entrypoint.sh"]
CMD ["info"]
