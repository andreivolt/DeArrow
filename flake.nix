{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-webext.url = "github:rivavolt/nix-webext";
    flake-utils.url = "github:numtide/flake-utils";
    # Pinned to the exact revs the .gitmodules submodules record: the build replaces the submodule trees with these inputs (postPatch cp), and DeArrow's source moves in lockstep with maze-utils' API (a floating master drifts — e.g. metadataFetcher's getChannelID — and breaks the webpack typecheck on every upstream push).
    maze-utils = {
      url = "github:ajayyy/maze-utils/c1e0d65ed4536225fe3502ebdf4059260b17e598";
      flake = false;
    };
    locales = {
      url = "github:ajayyy/ExtensionTranslations/2f498a8579334ad067fd85803f4f00404799a390";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nix-webext, flake-utils, maze-utils, locales }:
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
            rm -rf maze-utils public/_locales
            cp -r ${maze-utils} maze-utils
            cp -r ${locales} public/_locales
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

        # Chrome CRX signed at activation from the sops key (build is keyless);
        # extId is the stable Chrome ID the old committed key derived. The npm
        # build emits the Chrome manifest already, so no MV3 projection.
        ext = nix-webext.lib.mkBrowserExtension {
          inherit pkgs extension;
          pname = "dearrow";
          version = (builtins.fromJSON (builtins.readFile ./manifest/manifest.json)).version;
          extId = "akhldaacfjcmilfhamkhdbeookhgpimc";
          firefox = false;
          transformManifest = false;
        };
      in
      {
        packages = {
          inherit extension;
          # Expose the nix-webext metadata (extId, chromeContent) so nixos-config's
          # activation signer can pack + sign the CRX from the sops key.
          inherit (ext) default chrome extId chromeContent;
          # Firefox/Safari/Edge native builds (consumed elsewhere as needed).
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
