{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }:
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

      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) lib;

          # Regenerate gemset.nix with `bundix` whenever Gemfile.lock changes.
          gems = pkgs.bundlerEnv {
            name = "ketchup-gems";
            ruby = pkgs.ruby_4_0;
            gemdir = ./.;
            groups = [ "default" ];
          };

          app = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [ ./config.ru ./lib ./db/migrate ./public ];
          };

          buildDate =
            let d = self.lastModifiedDate;
            in "${lib.substring 0 4 d}-${lib.substring 4 2 d}-${lib.substring 6 2 d}";
        in
        {
          inherit gems;

          docker = pkgs.dockerTools.buildLayeredImage {
            name = "ghcr.io/kejadlen/ketchup";
            tag = self.shortRev or "dirty";
            contents = [ pkgs.cacert pkgs.tzdata ];
            config = {
              Cmd = [ "${gems}/bin/rackup" "-o" "0.0.0.0" ];
              WorkingDir = "${app}";
              ExposedPorts."9292/tcp" = { };
              Env = [ "COMMIT_SHA=${self.shortRev or "dirty"}" ]
                ++ lib.optional (self ? lastModifiedDate) "BUILD_DATE=${buildDate}";
            };
          };
        });
    };
}
