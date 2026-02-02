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
      in
      {
        packages = {
          default = mkDeArrow "chrome";
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
