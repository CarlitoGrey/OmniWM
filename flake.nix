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

      pins = lib.listToAttrs (
        map (line: {
          name = lib.head (lib.splitString "=" line);
          value = lib.concatStringsSep "=" (lib.tail (lib.splitString "=" line));
        }) (lib.filter (line: builtins.match "[A-Z0-9_]+=.*" line != null) (lib.splitString "\n" (builtins.readFile ./Scripts/dev-tools.env)))
      );

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

      tools =
        pkgs:
        [
          pkgs.python3
          pkgs.fish
          pkgs.nushell
          pkgs.gnumake
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          (releaseTool pkgs "swiftformat" pins.SWIFTFORMAT_VERSION
            "https://github.com/nicklockwood/SwiftFormat/releases/download/${pins.SWIFTFORMAT_VERSION}/swiftformat.zip"
            pins.OMNIWM_SWIFTFORMAT_ZIP_SHA256
          )
          (releaseTool pkgs "swiftlint" pins.SWIFTLINT_VERSION
            "https://github.com/realm/SwiftLint/releases/download/${pins.SWIFTLINT_VERSION}/portable_swiftlint.zip"
            pins.OMNIWM_SWIFTLINT_ZIP_SHA256
          )
        ];
    in
    {
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
        }
      );

      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShellNoCC {
          packages = tools nixpkgs.legacyPackages.${system};
        };
      });

      checks = forAllSystems (system: {
        tools = self.packages.${system}.default;
      });
    };
}
