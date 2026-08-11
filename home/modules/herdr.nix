{ pkgs, herdr, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  #
  # Herdr
  #
  # Persistent agent-aware terminal/session runtime.
  #
  # Configuration is intentionally left mutable for now while
  # we learn the default workflow and decide which preferences
  # are worth managing declaratively.
  #

  home.packages = [
    herdr.packages.${system}.default
  ];
}
