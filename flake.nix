{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ];
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            # fd and entr, for `rake dev`.
            packages = [ pkgs.ruby_4_0 pkgs.fd pkgs.entr ];

            RUBYOPT = "--enable-frozen-string-literal";
          };
        });
    };
}
