# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG PIXI_VERSION=v0.61.0
ARG PIXI_HOME=/opt/pixi
ARG PIXI_PROJECT_DIR=/opt/fibertools
ARG UCSC_BIN_DIR=/opt/ucsc/bin
ARG UCSC_BASE_URL=https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64
ARG UCSC_UTILS="bedGraphToBigWig bedToBigBed bigBedToBed bigWigAverageOverBed bigWigToBedGraph wigToBigWig"

ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND} \
    TZ=America/Chicago \
    PIXI_HOME=${PIXI_HOME} \
    PIXI_PROJECT_DIR=${PIXI_PROJECT_DIR} \
    UCSC_BIN_DIR=${UCSC_BIN_DIR} \
    UCSC_BASE_URL=${UCSC_BASE_URL} \
    UCSC_UTILS=${UCSC_UTILS}

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      ca-certificates \
      curl \
      gawk \
      git \
      less \
      openssh-client \
      pkg-config \
      tzdata \
      unzip \
      wget \
      xz-utils \
      zip \
    && rm -rf /var/lib/apt/lists/*

# Install a pinned pixi CLI, but keep package versions in pixi.toml.
RUN mkdir -p "${PIXI_HOME}" "${PIXI_PROJECT_DIR}" \
    && curl -fsSL https://pixi.sh/install.sh | PIXI_VERSION="${PIXI_VERSION}" PIXI_HOME="${PIXI_HOME}" PIXI_NO_PATH_UPDATE=1 bash \
    && "${PIXI_HOME}/bin/pixi" --version

# Install from manifest only. Resolution happens fresh during image build.
COPY pixi.toml ${PIXI_PROJECT_DIR}/pixi.toml
RUN "${PIXI_HOME}/bin/pixi" install --manifest-path "${PIXI_PROJECT_DIR}/pixi.toml" --environment default

# UCSC binaries are distributed as standalone executables. Keep them in a
# dedicated prefix and expose that prefix through PATH.
RUN set -eu; \
    install -d -m 0755 "${UCSC_BIN_DIR}"; \
    for tool in ${UCSC_UTILS}; do \
      curl --fail --location --show-error --silent \
        --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 300 \
        "${UCSC_BASE_URL}/${tool}" -o "${UCSC_BIN_DIR}/${tool}"; \
      chmod 0755 "${UCSC_BIN_DIR}/${tool}"; \
    done

# pixi-managed executables (python + tools) take precedence in Podman/Singularity.
ENV PATH=${PIXI_PROJECT_DIR}/.pixi/envs/default/bin:${PIXI_HOME}/bin:${UCSC_BIN_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#