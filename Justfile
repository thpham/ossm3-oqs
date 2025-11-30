# Istio Proxy with PQC Support - Development Tasks

set shell := ["bash", "-euo", "pipefail", "-c"]

# Configuration

export IMAGE := "your-registry.tld/istio-proxyv2-rhel9-oqs:3.2.1"
export CONTAINER := "envoy-pqc-test"
export PORT := "8443"

# Default recipe: show help
default:
    @just --list

# Build the Docker image (native architecture)
build:
    #!/usr/bin/env bash
    set -euo pipefail
    docker build -t "$IMAGE" .

# Build with no cache
build-clean:
    #!/usr/bin/env bash
    set -euo pipefail
    docker build --no-cache -t "$IMAGE" .

# Build multi-arch image (amd64 + arm64) and push
build-multiarch:
    #!/usr/bin/env bash
    set -euo pipefail
    docker buildx build --platform linux/amd64,linux/arm64 \
        -t "$IMAGE" --push .

# Build multi-arch image and load locally (single arch only)
build-multiarch-load arch="linux/amd64":
    #!/usr/bin/env bash
    set -euo pipefail
    docker buildx build --platform "{{ arch }}" \
        -t "$IMAGE" --load .

# Generate classical RSA certificates (default)
certs:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p certs
    openssl req -x509 -newkey rsa:2048 \
        -keyout certs/tls.key -out certs/tls.crt \
        -days 1 -nodes -subj "/CN=localhost"
    echo "=> RSA certificates generated in ./certs/"

# Generate PQC test certificates (ML-DSA-65 signatures)
certs-pqc:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p certs
    # Generate ML-DSA-65 certificate using OQS provider in container
    docker run --rm -v "$(pwd)/certs:/certs" --entrypoint openssl "$IMAGE" \
        req -x509 -newkey mldsa65 \
        -keyout /certs/tls.key -out /certs/tls.crt \
        -days 1 -nodes -subj "/CN=localhost"
    echo "=> PQC certificates generated (ML-DSA-65) in ./certs/"

# Run Envoy with PQC config (uses alternative OpenSSL config for PQC groups)
run: certs
    #!/usr/bin/env bash
    set -euo pipefail
    docker run --rm -d \
        --name "$CONTAINER" \
        -p "${PORT}:8443" \
        -v "$(pwd)/certs:/etc/envoy/certs:ro" \
        -e OPENSSL_CONF=/etc/pki/tls/openssl-pqc.cnf \
        --entrypoint envoy \
        "$IMAGE" \
        -c /etc/envoy/envoy-pqc.yaml
    echo "=> Envoy running on port $PORT"
    echo "   Test with: just test"

# Stop the test container
stop:
    #!/usr/bin/env bash
    docker stop "$CONTAINER" 2>/dev/null || true
    echo "=> Container stopped"

# Test PQC TLS handshake
test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Testing PQC TLS (X25519MLKEM768) ==="
    echo | openssl s_client -connect "localhost:${PORT}" \
        -groups X25519MLKEM768:X25519 -brief 2>&1 \
        | grep -E "(Protocol|Ciphersuite|Negotiated|error)" || true

# Test with detailed output
test-verbose:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Detailed PQC TLS Test ==="
    echo | openssl s_client -connect "localhost:${PORT}" \
        -groups X25519MLKEM768:X25519 2>&1 \
        | grep -E "(Protocol|Peer|Cipher|PKEY|Negotiated|Verification)"

# Test fallback to classical X25519
test-fallback:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Testing Classical Fallback (X25519) ==="
    echo | openssl s_client -connect "localhost:${PORT}" \
        -groups X25519 2>&1 \
        | grep -E "(Protocol|Cipher|Temp Key)"

# Verify OQS provider in image
verify:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== OQS Provider Status ==="
    docker run --rm --entrypoint openssl "$IMAGE" list -providers
    echo ""
    echo "=== Available PQC KEMs (Key Exchange) ==="
    docker run --rm --entrypoint openssl "$IMAGE" list -kem-algorithms | grep -i mlkem
    echo ""
    echo "=== Available PQC Signatures ==="
    docker run --rm --entrypoint openssl "$IMAGE" list -signature-algorithms | grep -i mldsa

# Show container logs
logs:
    #!/usr/bin/env bash
    docker logs "$CONTAINER"

# Clean up test artifacts
clean: stop
    #!/usr/bin/env bash
    rm -rf certs
    echo "=> Cleaned up test artifacts"

# Full test cycle: build, run, test, stop
all: build run test stop
    @echo "=> Full test cycle completed"

# Quick test: run and test (assumes image is built)
quick: run
    #!/usr/bin/env bash
    sleep 2
    just test
    just stop
