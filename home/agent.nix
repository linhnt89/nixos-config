{
  pkgs,
  pkgsUnstable,
  ...
}:

#
# MetaCube Home Manager entry point for the dedicated `agent` account.
#
# This account owns all AI-agent runtime responsibility (Pi, Firstmate
# toolchain, Herdr, Claude Code); see modules/nixos/agent-runtime.nix
# for the account itself. The portable layers come from the nixdev-config
# flake in flake.nix (`homeManagerModules.firstmate` role profile —
# shell/git/dev structure plus the Firstmate toolchain — and
# `homeManagerModules.assistant`, the opt-in Pi module).
#
# GitHub access here is deliberately HTTPS via gh's credential helper
# (one runtime `gh auth login`), NOT linhnt's SSH-based github.com git
# config — the agent account holds no personal SSH keys.
#

{
  imports = [
    ./modules/pi.nix
    ./modules/firstmate-timer.nix
  ];

  #
  # Shared Firstmate toolchain — MetaCube choices
  #
  # This machine's configured Firstmate backend is Herdr, so enable the
  # pinned herdr binary the firstmate role ships opt-in (binary only;
  # Firstmate drives all Herdr lifecycle). The Dependabot sweep timer is
  # MetaCube-only by construction: the firstmate-timer module above is
  # imported here and nowhere else. Both units use %h, so they resolve
  # to /home/agent/firstmate automatically.
  #

  nixdev.firstmate.enableHerdr = true;

  metacube.firstmate.fmDependabotSweep.enable = true;

  #
  # Pi — enabled only here, never on the desktop account
  #
  # Pi moves significantly faster than the NixOS stable package set, so
  # keep Pi on nixpkgs-unstable. The declarative Pi defaults under
  # home/pi/ are wired user-independently by ./modules/pi.nix.
  #

  nixdev.assistant.enable = true;
  nixdev.assistant.package = pkgsUnstable.pi-coding-agent;

  #
  # Claude Code — Nix-owned in this account
  #
  # A machine-local choice for MetaCube's restricted agent account
  # (nixdev-config's shared policy keeps Claude native-installed and is
  # intentionally unchanged; claude-code's unfree mark is permitted
  # narrowly in modules/nixos/agent-runtime.nix). The Nix package
  # disables Claude's own updater, so Nix stays the version authority.
  #

  home.packages = [
    pkgs.claude-code
  ];

  #
  # Git identity — reuse the existing MetaCube identity
  #
  # programs.git itself (enablement, defaultBranch, autoSetupRemote) is
  # owned by the portable profile. No SSH-based github.com host block:
  # the agent account pushes over HTTPS through gh's credential helper.
  #

  programs.git.settings = {
    user = {
      name = "Linh Nguyen";
      email = "linhtramnguyen@gmail.com";
    };

    # GitHub over HTTPS via gh's OAuth token. Declared here instead of
    # the imperative 'gh auth setup-git', which cannot edit this
    # HM-generated file (read-only store symlink).
    credential."https://github.com".helper =
      "${pkgs.gh}/bin/gh auth git-credential";
  };

  #
  # GitHub CLI — agent behavior
  #
  # The gh PACKAGE is owned by the portable firstmate role; this module
  # configures how gh behaves in this account: HTTPS protocol with an
  # HTTPS credential helper, so no SSH key material is needed here.
  #

  programs.gh = {
    enable = true;

    settings = {
      # HTTPS + credential helper instead of linhnt's SSH setup.
      git_protocol = "https";

      prompt = "enabled";
    };

    gitCredentialHelper.enable = true;
  };

  #
  # Zsh behavior - mirrors the machine-local preferences in
  # home/modules/shell.nix (imported only for linhnt): autosuggestions,
  # syntax highlighting, and shared tuned history.
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
  # User identity
  #

  home.username = "agent";
  home.homeDirectory = "/home/agent";

  #
  # XDG base directories
  #

  xdg.enable = true;

  #
  # Home Manager compatibility version
  #

  home.stateVersion = "26.05";
}
