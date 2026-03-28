{
  inputs = {
    nixpkgs.url = "nixpkgs";
    zig.url = "github:silversquirl/zig-flake";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      zig,
      ...
    }:
    let
      forAllSystems =
        f: builtins.mapAttrs (system: pkgs: f pkgs zig.packages.${system}.nightly) nixpkgs.legacyPackages;
    in
    {
      formatter = forAllSystems (pkgs: zig: pkgs.nixfmt-rfc-style);

      devShells = forAllSystems (
        pkgs: zig: {
          default = pkgs.mkShellNoCC {
            name = "seiargs";

            ZIG_BUILD_ERROR_STYLE = "verbose_clear";

            packages = [
              (pkgs.writeShellScriptBin "serve" ''
                ${pkgs.lib.getExe pkgs.caddy} file-server --root ./zig-out/docs/ --listen :8080
              '')

              zig
              zig.zls
            ];
          };

          minimal = pkgs.mkShellNoCC {
            packages = [
              zig
            ];
          };
        }
      );

      packages = forAllSystems (
        pkgs: zig: {
          docs = pkgs.stdenvNoCC.mkDerivation {
            name = "seiargs-docs";
            src = ./.;

            nativeBuildInputs = [
              zig
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
