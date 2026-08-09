{ pkgs, ... }:

{
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
  # General development utilities
  #

  home.packages = [
    # HTTP/download tools
    pkgs.curl
    pkgs.wget

    # Structured data
    pkgs.yq-go

    # Project command runner
    pkgs.just
  ];
}
