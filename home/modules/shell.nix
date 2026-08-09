{ pkgs, ... }:

{
  #
  # Zsh
  #

  programs.zsh = {
    enable = true;

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
  # Prompt
  #

  programs.starship = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      add_newline = false;
      command_timeout = 1000;
    };
  };

  #
  # Fuzzy finder
  #

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

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
  # CLI viewers
  #

  programs.bat = {
    enable = true;

    config = {
      pager = "less -FR";
    };
  };

  programs.eza = {
    enable = true;

    # Keep traditional ls untouched.
    enableZshIntegration = false;
  };

  #
  # General CLI utilities
  #

  home.packages = [
    pkgs.ripgrep
    pkgs.fd
    pkgs.jq
    pkgs.tree

    pkgs.zip
    pkgs.unzip
  ];
}
