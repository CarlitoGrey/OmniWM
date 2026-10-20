{
  description = "OmniWM developer tooling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      toolchain = {
        swift = {
          version = "6.5";
          snapshot = "main-snapshot-2026-10-11";
        };
        swiftformat = {
          version = "0.63.0";
          sha256 = "28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f";
        };
        swiftlint = {
          version = "0.65.1";
          sha256 = "c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0";
        };
      };

      releaseTool =
        pkgs: name: version: url: sha256:
        pkgs.stdenvNoCC.mkDerivation {
          pname = name;
          inherit version;
          src = pkgs.fetchurl { inherit url sha256; };
          nativeBuildInputs = [ pkgs.unzip ];
          sourceRoot = ".";
          dontConfigure = true;
          dontBuild = true;
          installPhase = "install -Dm755 ${name} $out/bin/${name}";
          meta.platforms = lib.platforms.darwin;
        };

      swiftToolchain =
        pkgs:
        pkgs.writeShellScriptBin "swift-toolchain" ''
          set -euo pipefail
          SWIFTLY_HOME_DIR="''${SWIFTLY_HOME_DIR:-$HOME/.swiftly}"
          SWIFTLY="$SWIFTLY_HOME_DIR/bin/swiftly"
          SWIFT_ORG_TEAM_ID="V9AUD2URP3"
          if [ ! -x "$SWIFTLY" ]; then
            WORK_DIR="$(mktemp -d)"
            trap 'rm -rf "$WORK_DIR"' EXIT
            curl --fail --silent --show-error --location --output "$WORK_DIR/swiftly.pkg" \
              https://download.swift.org/swiftly/darwin/swiftly.pkg
            if ! pkgutil --check-signature "$WORK_DIR/swiftly.pkg" | grep -q "($SWIFT_ORG_TEAM_ID)"; then
              echo "swift-toolchain: swiftly.pkg is not signed by Swift.org ($SWIFT_ORG_TEAM_ID)" >&2
              exit 1
            fi
            installer -pkg "$WORK_DIR/swiftly.pkg" -target CurrentUserHomeDirectory
            "$SWIFTLY" init --assume-yes --no-modify-profile --skip-install --quiet-shell-followup
          fi
          "$SWIFTLY" install --assume-yes ${toolchain.swift.snapshot}
          "$SWIFTLY" use ${toolchain.swift.snapshot}
          if [ -n "''${GITHUB_PATH:-}" ]; then
            echo "$SWIFTLY_HOME_DIR/bin" >> "$GITHUB_PATH"
          fi
          "$SWIFTLY_HOME_DIR/bin/swift" --version
        '';

      tools =
        pkgs:
        [
          pkgs.python3
          pkgs.fish
          pkgs.nushell
          pkgs.gnumake
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          (releaseTool pkgs "swiftformat" toolchain.swiftformat.version
            "https://github.com/nicklockwood/SwiftFormat/releases/download/${toolchain.swiftformat.version}/swiftformat.zip"
            toolchain.swiftformat.sha256
          )
          (releaseTool pkgs "swiftlint" toolchain.swiftlint.version
            "https://github.com/realm/SwiftLint/releases/download/${toolchain.swiftlint.version}/portable_swiftlint.zip"
            toolchain.swiftlint.sha256
          )
          (swiftToolchain pkgs)
        ];
    in
    {
      inherit toolchain;

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.buildEnv {
            name = "omniwm-dev-tools";
            paths = tools pkgs;
          };
          swift-toolchain = swiftToolchain pkgs;
        }
      );

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = tools nixpkgs.legacyPackages.${system};
          shellHook = ''
            export SWIFT_VERSION="${toolchain.swift.version}"
            export SWIFT_SNAPSHOT="${toolchain.swift.snapshot}"
          '';
        };
      });

      checks = forAllSystems (system: {
        tools = self.packages.${system}.default;
      });
    };
}
