{
  inputs = {
    nixpkgs.url = "nixpkgs";
    zig.url = "github:silversquirl/zig-flake/compat";
    zls.url = "github:zigtools/zls";

    zig.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.zig-overlay.follows = "zig";
  };

  outputs =
    {
      nixpkgs,
      zig,
      zls,
      ...
    }:
    let
      forAllSystems = f: builtins.mapAttrs f nixpkgs.legacyPackages;
    in
    {
      formatter = forAllSystems (system: pkgs: pkgs.nixfmt-rfc-style);

      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShellNoCC {
            packages = [
              (pkgs.writeShellScriptBin "serve" ''
                ${pkgs.lib.getExe pkgs.caddy} file-server --root ./zig-out/docs/ --listen :8080
              '')

              zig.packages.${system}.nightly
              zls.packages.${system}.zls
            ];
          };

          minimal = pkgs.mkShellNoCC {
            packages = [
              zig.packages.${system}.nightly
            ];
          };
        }
      );

      packages = forAllSystems (
        system: pkgs: {
          docs = pkgs.stdenvNoCC.mkDerivation {
            name = "seiargs-docs";
            src = ./.;

            nativeBuildInputs = [
              zig.packages.${system}.nightly
            ];

            buildPhase = ''
              ZIG_GLOBAL_CACHE_DIR=.zig_cache zig build docs
            '';

            installPhase = ''
              cp -r ./zig-out/docs $out
            '';
          };
        }
      );
    };
}
