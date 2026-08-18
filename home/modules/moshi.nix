{ pkgs, ... }:

{
  #
  # Moshi (mobile terminal) host support
  #
  # Packages the Moshi Android app expects to find on the
  # host:
  #
  # - mosh: mosh-server is located over the SSH bootstrap
  #   session when the phone uses the mosh transport.
  # - tmux: durable workspaces across terminal reconnects.
  #   Herdr is the preferred multiplexer on this machine
  #   and is installed by nixdev-config's firstmateTools
  #   module (pinned herdr, enabled via `nixdev.firstmate.enableHerdr`);
  #   tmux remains a
  #   fallback.
  #
  # These land in the Home Manager user profile
  # (/etc/profiles/per-user/linhnt/bin), which NixOS puts
  # on PATH for every zsh invocation -- including the
  # non-interactive SSH sessions Moshi uses for host and
  # session detection.
  #

  home.packages = [
    pkgs.mosh
    pkgs.tmux
  ];
}
