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
  # Moshi (mobile terminal) visibility note:
  #
  # herdr lands in /etc/profiles/per-user/<user>/bin, and
  # NixOS's /etc/zshenv sources the system set-environment
  # script for every zsh invocation, so `herdr` is already on
  # the non-interactive SSH PATH that Moshi probes for session
  # detection. See docs/moshi-herdr.md.
  #

  home.packages = [
    herdr.packages.${system}.default
  ];
}
