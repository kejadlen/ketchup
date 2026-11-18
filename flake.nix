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
          #
          # bundix tags the dependencies of development gems (activesupport via steep, websocket-driver
          # via ferrum, ...) as [ "default" "development" ], so filtering on "default" alone ships them.
          # Count a gem as default only when that's its sole group; bundlerEnv adds back the dependency
          # closure of those gems (rack, rake, prism, ...) on its own.
          #
          # That assumes each top-level gem in the Gemfile's default group is tagged only "default". If
          # one ever becomes a dependency of a development gem too, add it to `extraDefaultGems`.
          extraDefaultGems = [ ];
          gemset = lib.mapAttrs
            (name: attrs:
              if attrs.groups == [ "default" ] || lib.elem name extraDefaultGems then attrs
              else attrs // { groups = lib.remove "default" attrs.groups; })
            (import ./gemset.nix);

          gems = pkgs.bundlerEnv {
            name = "ketchup-gems";
            ruby = pkgs.ruby_4_0;
            gemfile = ./Gemfile;
            lockfile = ./Gemfile.lock;
            inherit gemset;
            groups = [ "default" ];
          };

          app = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [ ./config.ru ./lib ./db/migrate ./public ];
          };

          # CI passes the push's head commit timestamp with `--impure`, the same value the Dockerfile
          # build gets. Pure builds fall back to the commit time in UTC, in the same ISO 8601 shape.
          buildDate =
            let
              env = builtins.getEnv "BUILD_DATE";
              d = self.lastModifiedDate;
              s = lib.substring;
            in
            if env != "" then env
            else "${s 0 4 d}-${s 4 2 d}-${s 6 2 d}T${s 8 2 d}:${s 10 2 d}:${s 12 2 d}Z";

          # Flakes can't see jj change IDs, so CI passes one in with `--impure`; pure builds get "".
          changeId = builtins.getEnv "CHANGE_ID";
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
                ++ lib.optional (self ? lastModifiedDate) "BUILD_DATE=${buildDate}"
                ++ lib.optional (changeId != "") "CHANGE_ID=${changeId}";
            };
          };
        });
    };
}
