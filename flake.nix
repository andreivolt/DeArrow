{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    maze-utils = {
      url = "github:ajayyy/maze-utils";
      flake = false;
    };
    locales = {
      url = "github:ajayyy/ExtensionTranslations";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, maze-utils, locales }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nodejs = pkgs.nodejs_22;

        mkDeArrow = browser: pkgs.buildNpmPackage {
          pname = "dearrow-${browser}";
          version = "0.0.0-dev";
          src = self;
          inherit nodejs;

          npmDepsHash = "sha256-50UVWOKWPHJeSsyUwi7iCcH1wYyLNdDGUoVZhGP5Ws8=";
          makeCacheWritable = true;

          env.CHROMEDRIVER_SKIP_DOWNLOAD = "true";
          npmFlags = [ "--ignore-scripts" ];

          postPatch = ''
            cp -r ${maze-utils}/ maze-utils
            cp -r ${locales}/ public/_locales
          '';

          buildPhase = ''
            runHook preBuild
            cp config.json.example config.json
            npm run build:${browser}
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share/chromium-extension
            cp -r dist/* $out/share/chromium-extension/
            runHook postInstall
          '';

          dontNpmInstall = true;
        };

        extension = mkDeArrow "chrome";

        manifest = builtins.fromJSON (builtins.readFile "${extension}/share/chromium-extension/manifest.json");

        extId = builtins.readFile (pkgs.runCommand "dearrow-ext-id" {
          nativeBuildInputs = [ pkgs.python3 pkgs.openssl ];
        } ''
          python3 ${./nix/crx-id.py} ${./keys/signing.pem} > $out
        '');

        crx = pkgs.runCommand "dearrow-crx" {
          nativeBuildInputs = [ pkgs.python3 pkgs.openssl ];
        } ''
          mkdir -p $out
          python3 ${./nix/pack-crx3.py} ${extension}/share/chromium-extension ${./keys/signing.pem} $out/extension.crx
        '';

      in
      {
        packages = {
          inherit extension;
          default = pkgs.linkFarm "dearrow" [
            { name = "share/chromium/extensions/${extId}.json";
              path = pkgs.writeText "${extId}.json" (builtins.toJSON {
                external_crx = "${crx}/extension.crx";
                external_version = manifest.version;
              });
            }
          ];
          chrome = mkDeArrow "chrome";
          firefox = mkDeArrow "firefox";
          safari = mkDeArrow "safari";
          edge = mkDeArrow "edge";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            nodejs
            pkgs.web-ext
          ];
        };
      }
    );
}
