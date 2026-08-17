{ lib, pkgs, ... }:

#
# Local adapter for the portable shell profile.
#
# The shared portable shell layer is imported from the private
# nixdev-config flake in flake.nix (`nixdev-config.homeManagerModules.desktop`
# -> home/modules/shell.nix there): it owns the *enablement* of zsh /
# starship / fzf / bat / eza and the common package set (fd, ripgrep, jq,
# tree, zip, unzip, curl, wget, yq-go, just, Python, Node, shellcheck, ...).
# See docs/nixdev-config-integration.md for the ownership boundary.
#
# This adapter carries ONLY the MetaCube-personal shell preferences that
# the portable profile deliberately leaves out.
{

  #
  # Zsh (enabled by the portable profile) — personal behavior
  #

  programs.zsh = {
    enableCompletion = true;

    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 50000;
      save = 50000;

      share = true;

      ignoreDups = true;
      ignoreAllDups = true;
      expireDuplicatesFirst = true;

      extended = true;
      ignoreSpace = true;
    };
  };

  #
  # Starship (enabled + shell integrations by the portable profile)
  # — personal settings only
  #

  programs.starship = {
    settings = {
      add_newline = false;
      command_timeout = 1000;
    };
  };

  #
  # Fzf (enabled + shell integrations by the portable profile)
  # — personal widget behavior only
  #

  programs.fzf = {
    fileWidgetCommand =
      "${pkgs.fd}/bin/fd "
      + "--type f "
      + "--hidden "
      + "--exclude .git";

    changeDirWidgetCommand =
      "${pkgs.fd}/bin/fd "
      + "--type d "
      + "--hidden "
      + "--exclude .git";

    defaultOptions = [
      "--height=40%"
      "--layout=reverse"
      "--border"
    ];
  };

  #
  # Eza — one desktop-only override
  #
  # The portable profile enables eza with bash+zsh integration; on this
  # desktop the zsh integration is deliberately OFF so the traditional
  # `ls` alias stays untouched. Everything else (icons, git column) keeps
  # the portable defaults.
  #

  programs.eza.enableZshIntegration = lib.mkForce false;
}
