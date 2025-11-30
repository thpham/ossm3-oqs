# Dockerfile - PQC-enabled Istio Proxy for OpenShift Service Mesh 3
#
# OSSM 3 uses OpenSSL (not BoringSSL) for FIPS compliance.
# This allows the OQS provider to integrate directly with Envoy's TLS.
#
# Multi-arch: amd64, arm64 (use: just build-multiarch)
# Base image: OSSM 3.2.1 (Istio 1.27.3)
ARG OSSM_PROXY_IMAGE=registry.redhat.io/openshift-service-mesh/istio-proxyv2-rhel9@sha256:7d15cebf9b62f3f235c0eab5158ac8ff2fda86a1d193490dc94c301402c99da8
FROM ${OSSM_PROXY_IMAGE}

USER root

# Builder stage: compile liboqs and oqs-provider
FROM registry.access.redhat.com/ubi9/ubi:latest AS builder

RUN dnf install -y git cmake gcc gcc-c++ ninja-build openssl-devel && \
    dnf clean all

# Build liboqs as static library (will be linked into oqsprovider.so)
# Pinned versions for stability and compatibility
ARG LIBOQS_VERSION=0.14.0
ARG OQS_PROVIDER_VERSION=0.10.0

WORKDIR /build
RUN git clone --depth 1 --branch ${LIBOQS_VERSION} https://github.com/open-quantum-safe/liboqs.git && \
    cd liboqs && \
    mkdir build && cd build && \
    cmake -GNinja \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DBUILD_SHARED_LIBS=OFF \
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. && \
    ninja && ninja install

# Build oqs-provider
RUN git clone --depth 1 --branch ${OQS_PROVIDER_VERSION} https://github.com/open-quantum-safe/oqs-provider.git && \
    cd oqs-provider && \
    mkdir build && cd build && \
    cmake -GNinja \
      -DOPENSSL_ROOT_DIR=/usr \
      -Dliboqs_DIR=/usr/local/lib64/cmake/liboqs \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_PREFIX_PATH=/usr/local .. && \
    ninja && ninja install && \
    echo "=== Installed files ===" && \
    find /usr/local -name "*.so*" 2>/dev/null || true

# Copy to final image
FROM ${OSSM_PROXY_IMAGE}

USER root

# Copy oqs-provider (liboqs is statically linked)
COPY --from=builder /usr/lib64/ossl-modules/oqsprovider.so /usr/lib64/ossl-modules/

# OpenSSL config with OQS provider and PQC TLS defaults:
# - TLS 1.3 enforced (required for PQC key exchange)
# - X25519MLKEM768 as preferred key exchange group
# - TLS 1.3 cipher suites
# This config applies to ALL OpenSSL TLS connections including Envoy
COPY --chmod=644 openssl-pqc.cnf /etc/pki/tls/openssl-pqc.cnf
COPY --chmod=644 crypto-policies/opensslcnf.config /etc/crypto-policies/back-ends/opensslcnf.config
ENV OPENSSL_CONF=/etc/pki/tls/openssl-pqc.cnf

# Reference Envoy config for standalone use or testing
RUN mkdir -p /etc/envoy && chmod 755 /etc/envoy
COPY --chmod=644 envoy-pqc.yaml /etc/envoy/envoy-pqc.yaml

USER 1000
