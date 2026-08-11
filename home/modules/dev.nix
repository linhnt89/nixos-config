{ pkgs, pkgsUnstable, ... }:

{
  imports = [
    ./pi.nix
    ./treehouse.nix
  ];

  #
  # GitHub CLI
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

  programs.lazygit = {
    enable = true;

    # Adds the `lg` Zsh wrapper, including support for
    # changing directory after leaving lazygit.
    enableZshIntegration = true;
  };

  #
  # Project environments
  #

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;

    # Use nix-direnv's persistent/cached implementation
    # for Nix development environments.
    nix-direnv.enable = true;
  };

  #
  # AI development tools
  #

  home.packages = [
    # Pi moves significantly faster than the NixOS stable
    # package set, so keep only Pi on nixpkgs-unstable.
    pkgsUnstable.pi-coding-agent

    #
    # General development utilities
    #

    # HTTP/download tools
    pkgs.curl
    pkgs.wget

    # Structured data
    pkgs.yq-go

    # Project command runner
    pkgs.just
  ];
}
