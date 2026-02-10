# Istio Proxy with Post-Quantum Cryptography (PQC) Support

Custom OpenShift Service Mesh 3 proxy image with OQS (Open Quantum Safe) provider for PQC-enabled TLS at the edge.

> **Note**: This project is for **demonstration purposes only**. OpenShift Service Mesh is expected to provide native PQC support in a future release.

## Why Post-Quantum Cryptography?

**["Harvest Now, Decrypt Later"](https://en.wikipedia.org/wiki/Harvest_now,_decrypt_later)** - Adversaries can capture encrypted traffic today and store it until quantum computers become powerful enough to break current encryption. Data with long-term sensitivity (healthcare, financial, government, intellectual property) is at risk now, not when quantum computers arrive.

### Industry Adoption

Major organizations are already rolling out PQC:

| Organization   | Status                                                                                                                              |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Cloudflare** | [>50% of traffic protected](https://blog.cloudflare.com/pq-2025/) with PQC (2025)                                                   |
| **Google**     | [ML-KEM in Chrome 131](https://security.googleblog.com/2024/08/post-quantum-cryptography-standards.html), internal comms since 2022 |
| **Apple**      | [PQ3 protocol for iMessage](https://en.wikipedia.org/wiki/Post-quantum_cryptography) (2024)                                         |
| **NIST**       | [Final PQC standards](https://csrc.nist.gov/pubs/fips/203/final) published August 2024                                              |

### Regulatory Deadlines

- **NSA CNSA 2.0**: Migration deadlines 2030-2033
- **US Federal**: Full migration target 2035
- **Australia**: Aggressive 2030 deadline
- **EU**: Roadmap with 2030/2035 deadlines

**Don't wait for Q-Day** - protect long-lived data now with hybrid PQC (X25519MLKEM768).

## Prerequisites

- **OpenShift cluster must NOT be in FIPS mode** - FIPS mode restricts OpenSSL to FIPS-validated algorithms only, which excludes the post-quantum algorithms provided by the OQS provider.
- **The base image is not included in this repository** - it requires a valid licensed OpenShift cluster with access to `registry.redhat.io/openshift-service-mesh/istio-proxyv2-rhel9`.

## Architecture

**Requires OpenSSL-based Envoy** (not BoringSSL). This project is designed for:

- **OpenShift Service Mesh 3** (OSSM 3) - uses OpenSSL for FIPS compliance
- **Envoy builds with OpenSSL** - any Envoy compiled with `--define boringssl=disabled`

> **Note**: Since [Istio 1.25+](https://github.com/istio/istio/pull/55589), upstream Istio supports `X25519MLKEM768` natively via BoringSSL.
> This project uses an alternative approach via the OQS provider on OpenSSL, which is specific to OpenShift Service Mesh (OSSM) builds.

Base image: `registry.redhat.io/openshift-service-mesh/istio-proxyv2-rhel9` (OSSM 3.2.1 / Istio 1.27.3)

```
┌─────────────────────────────────────────────────────────┐
│                      Istio Gateway                      │
│                            │                            │
│    ┌───────────────────────┼───────────────────────┐    │
│    │                       ▼                       │    │
│    │   istiod (xDS) ──► Envoy TLS Config           │    │
│    │                       │                       │    │
│    │                       ▼                       │    │
│    │                    OpenSSL                    │    │
│    │                       │                       │    │
│    │       ┌───────────────┴─────────────┐         │    │
│    │       ▼                             ▼         │    │
│    │  Default Provider              OQS Provider   │    │
│    │                                (from image)   │    │
│    │                                     │         │    │
│    │                                     ▼         │    │
│    │                              X25519MLKEM768   │    │
│    └───────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

**Important**: For Istio-managed gateways:

- `openssl.cnf` → Loads OQS provider (makes PQC algorithms **available**)
- `EnvoyFilter` → Configures Envoy to **use** PQC algorithms (required!)

The xDS config from istiod overrides OpenSSL defaults, so an EnvoyFilter is needed.

## Image Contents

| File                                     | Purpose                               |
| ---------------------------------------- | ------------------------------------- |
| `/usr/lib64/ossl-modules/oqsprovider.so` | OQS provider with PQC algorithms      |
| `/etc/pki/tls/openssl.cnf`               | Loads OQS provider into OpenSSL       |
| `/etc/envoy/envoy-pqc.yaml`              | Reference config for standalone Envoy |

## Development

This project uses [Nix](https://nixos.org/) for development environment and [Just](https://just.systems/) for task automation.

### Prerequisites

```bash
# Enter development shell (with direnv)
direnv allow

# Or manually
nix develop
```

### Available Tasks

| Command                     | Description                              |
| --------------------------- | ---------------------------------------- |
| `just build`                | Build the Docker image (native arch)     |
| `just build-clean`          | Build with no cache                      |
| `just build-multiarch`      | Build for amd64 + arm64 and push         |
| `just build-multiarch-load` | Build for specific arch and load locally |
| `just certs`                | Generate PQC certificates (ML-DSA-65)    |
| `just certs-rsa`            | Generate classical RSA certificates      |
| `just run`                  | Run Envoy with PQC config                |
| `just test`                 | Test PQC TLS handshake                   |
| `just test-verbose`         | Test with detailed output                |
| `just test-fallback`        | Test classical X25519 fallback           |
| `just verify`               | Verify OQS provider in image             |
| `just stop`                 | Stop the test container                  |
| `just clean`                | Clean up test artifacts                  |
| `just quick`                | Run, test, and stop (quick cycle)        |
| `just all`                  | Full cycle: build, run, test, stop       |

### Quick Start

```bash
# Build and run full test cycle
just all

# Or step by step
just build
just quick
```

## Deployment (2 Steps Required)

### Step 1: Deploy PQC-enabled Gateway Image

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istio-ingressgateway
  namespace: istio-system
spec:
  template:
    spec:
      containers:
        - name: istio-proxy
          image: your-registry.tld/istio-proxyv2-rhel9-oqs:1.27.3
```

### Step 2: Apply EnvoyFilter for PQC TLS

The EnvoyFilter tells Envoy to use X25519MLKEM768 for key exchange.
See [envoyfilter-pqc-gateway.yaml](envoyfilter-pqc-gateway.yaml) for the full configuration.

## Verification

On OpenShift, verify the deployment:

```bash
# 1. Check OQS provider is loaded (inside container)
oc exec -n istio-system deploy/istio-ingressgateway -- \
  openssl list -providers

# 2. Check PQC algorithms available
oc exec -n istio-system deploy/istio-ingressgateway -- \
  openssl list -kem-algorithms | grep -i mlkem

# 3. Test TLS connection with PQC
echo | openssl s_client -connect your-gateway:443 \
  -groups X25519MLKEM768:X25519 2>&1 | grep -i "Negotiated"
```

For local testing, use `just verify` and `just test`.

## Supported PQC Algorithms

### Key Exchange (KEM)

| Algorithm           | Description                               |
| ------------------- | ----------------------------------------- |
| `X25519MLKEM768`    | Hybrid: ML-KEM-768 + X25519 (recommended) |
| `mlkem512/768/1024` | Pure ML-KEM variants                      |
| `x25519_mlkem512`   | Hybrid: ML-KEM-512 + X25519               |
| `x448_mlkem768`     | Hybrid: ML-KEM-768 + X448                 |

### Digital Signatures (Certificate Signing)

| Algorithm    | Description                             |
| ------------ | --------------------------------------- |
| `mldsa65`    | ML-DSA-65 (Dilithium) - used by default |
| `mldsa44/87` | ML-DSA variants (NIST levels 1/5)       |

Test certificates are generated with ML-DSA-65 (`just certs`). Use `just certs-rsa` for classical RSA certificates.

## Pinned Versions

| Component    | Version |
| ------------ | ------- |
| liboqs       | 0.14.0  |
| oqs-provider | 0.10.0  |

## References

- [NIST FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) - ML-KEM Standard (Key Exchange)
- [NIST FIPS 204](https://csrc.nist.gov/pubs/fips/204/final) - ML-DSA Standard (Digital Signatures)
- [OQS Provider](https://github.com/open-quantum-safe/oqs-provider)
- [Istio EnvoyFilter](https://istio.io/latest/docs/reference/config/networking/envoy-filter/)
- [Quantum-secure gateways in Red Hat OpenShift Service Mesh 3.2](https://developers.redhat.com/articles/2025/12/18/quantum-secure-gateways-openshift-service-mesh)
