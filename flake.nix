{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      devshell,
    }:
    let
      systems = [
        "aarch64-darwin"
      ];

      eachSystem =
        function:
        nixpkgs.lib.genAttrs systems (
          system:
          function {
            inherit system;
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ devshell.overlays.default ];
            };
          }
        );
    in
    {
      formatter = eachSystem ({ pkgs, ... }: pkgs.nixfmt-rfc-style);

      devShells = eachSystem (
        { pkgs, ... }:
        {
          default = pkgs.devshell.mkShell {
            name = "lynceus";

            packages = [
              pkgs.zig
              pkgs.zls
            ];

            commands = [
              {
                name = "fix";
                command = ''
                  cd $PRJ_ROOT
                  nix fmt ./*.nix
                  ${pkgs.zig}/bin/zig fmt ./...
                '';
              }
            ];
          };
        }
      );
    };
}
