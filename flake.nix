{
  description = "Istio Proxy with Post-Quantum Cryptography (PQC) Support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "istio-pqc-dev";

          buildInputs = with pkgs; [
            # Build tools
            just

            # TLS testing
            openssl

            # Utilities
            curl
            jq
          ];

          shellHook = ''
            echo "== Istio PQC Development Environment"
            echo ""
            echo "Available commands (via just):"
            echo "  just build    - Build the Docker image"
            echo "  just certs    - Generate test certificates"
            echo "  just run      - Run Envoy with PQC config"
            echo "  just test     - Test PQC TLS handshake"
            echo "  just stop     - Stop the test container"
            echo "  just clean    - Clean up test artifacts"
            echo ""
          '';
        };
      }
    );
}
