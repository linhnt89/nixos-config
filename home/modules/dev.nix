{ pkgs, pkgsUnstable, ... }:

#
# Local adapter for the portable development profile.
#
# The portable dev module (nixdev-config home/modules/dev.nix, imported
# via the desktop role in flake.nix) owns direnv + nix-direnv wiring, and
# the portable common package set supplies curl/wget/yq-go/just/tree/zip/
# unzip/Node/Python/... packaged by nixdev-config. The desktop role
# profile additionally installs the `gh` package (and never `glab`).
#
# This adapter carries ONLY MetaCube-personal desktop tooling: the gh
# client behavior (SSH protocol, no HTTPS credential helper), the lazygit
# UI, the Pi lane (pkgsUnstable, always owned by this repo), and the
# local Firstmate/treehouse/herdr modules below.
{

  imports = [
    ./pi.nix
    ./treehouse.nix
    ./herdr.nix
    ./firstmate.nix
  ];

  #
  # GitHub CLI — desktop behavior
  #
  # The gh PACKAGE is owned by the portable desktop role profile; this
  # module configures how gh behaves on MetaCube.
  #

  programs.gh = {
    enable = true;

    settings = {
      # Match the SSH-based GitHub setup in git.nix.
      git_protocol = "ssh";

      prompt = "enabled";
    };

    # GitHub access uses SSH, so an HTTPS credential helper
    # is unnecessary.
    gitCredentialHelper.enable = false;
  };

  #
  # Git terminal UI
  #
  # The portable profile ships the lazygit package in the common set;
  # the Home Manager integration (HM program module) stays local.
  #

  programs.lazygit = {
    enable = true;

    # Adds the `lg` Zsh wrapper, including support for
    # changing directory after leaving lazygit.
    enableZshIntegration = true;
  };

  #
  # AI development tools
  #
  # Pi moves significantly faster than the NixOS stable package set, so
  # keep Pi on nixpkgs-unstable — the Pi lane is this repo's ownership.
  #

  home.packages = [
    pkgsUnstable.pi-coding-agent
  ];
}
