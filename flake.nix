{
  inputs = {
    nixpkgs.url = "nixpkgs";
    zig.url = "github:silversquirl/zig-flake";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    zig,
    ...
  }: let
    forAllSystems = f:
      builtins.mapAttrs
      (system: pkgs: f pkgs zig.packages.${system}.zig_0_17_0)
      nixpkgs.legacyPackages;
  in {
    formatter = forAllSystems (pkgs: zig: pkgs.alejandra);

    devShells = forAllSystems (pkgs: zig: {
      default = pkgs.mkShellNoCC {
        packages = [
          pkgs.caddy
          zig
          # zig.zls
        ];
      };
    });

    packages = forAllSystems (pkgs: zig: {
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
    });
  };
}
