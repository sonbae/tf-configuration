{
  description = "Terraform for Cloudflare tunnels and DNS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      systems = [
        "aarch64-darwin" # Apple Silicon Macs
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f:
        lib.genAttrs systems (system:
          f (import nixpkgs {
            inherit system;
            # Terraform is BUSL-licensed, which nixpkgs marks as unfree.
            # Allow just that package rather than everything unfree.
            config.allowUnfreePredicate = pkg: lib.getName pkg == "terraform";
          }));
    in
    {
      # Non-secret tunnel data written by `terraform apply` (see outputs.tf):
      #   { <tunnel> = { id = "<uuid>"; hostnames = { "<host>" = "<service>"; }; }; }
      # Other flakes read it as `inputs.tf-configuration.lib.tunnels`.
      # Empty until the first apply.
      lib.tunnels =
        if builtins.pathExists ./tunnels.json
        then builtins.fromJSON (builtins.readFile ./tunnels.json)
        else { };

      # The dev shell: terraform, `tf` as a short name for it, and jq.
      # direnv enters it automatically on cd (see .envrc); `nix develop` also works.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.terraform
            (pkgs.writeShellScriptBin "tf" ''exec ${lib.getExe pkgs.terraform} "$@"'')
            pkgs.jq
          ];
        };
      });

      # `nix run .#terraform -- plan`, or `nix profile add .#terraform`.
      packages = forAllSystems (pkgs: {
        terraform = pkgs.terraform;
        default = pkgs.terraform;
      });
    };
}
