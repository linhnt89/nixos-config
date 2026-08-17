{ pkgs, noMistakes, ... }:

let
  #
  # Firstmate universal runtime
  #
  # Use the shared `pkgs.nodejs` (the same Node the portable profile
  # installs in the user profile via the common package set). Pinning a
  # separate nodejs_22 here would put two different `node` binaries in
  # the same Home Manager profile and collide at generation time;
  # nixdev-config owns the Node package for the dev layer.
  #

  nodejs = pkgs.nodejs;

  nodeToolsRoot =
    ../firstmate/node-tools;

  nodeModules =
    pkgs.importNpmLock.buildNodeModules {
      npmRoot = nodeToolsRoot;
      inherit nodejs;
    };

  firstmateNodeTools =
    pkgs.runCommand
      "firstmate-node-tools"
      {
        nativeBuildInputs = [
          pkgs.makeWrapper
        ];
      }
      ''
        mkdir -p "$out/bin"

        for tool in \
          gh-axi \
          chrome-devtools-axi \
          lavish-axi \
          tasks-axi \
          quota-axi
        do
          makeWrapper \
            "${nodeModules}/node_modules/.bin/$tool" \
            "$out/bin/$tool" \
            --prefix PATH : \
              "${nodeModules}/node_modules/.bin:${pkgs.lib.makeBinPath [ nodejs ]}"
        done
      '';

  #
  # no-mistakes
  #

  noMistakesPackage =
    pkgs.runCommand
      "no-mistakes-1.46.0"
      { }
      ''
        mkdir -p "$out/bin"

        install \
          -m755 \
          "${noMistakes}/no-mistakes" \
          "$out/bin/no-mistakes"
      '';
in
{
  #
  # Firstmate universal toolchain
  #

  home.packages = [
    nodejs
    firstmateNodeTools
    noMistakesPackage
  ];
}
