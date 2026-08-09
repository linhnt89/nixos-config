{ pkgs, ... }:

{
  #
  # GTK
  #

  gtk = {
    enable = true;

    colorScheme = "dark";

    font = {
      name = "Inter";
      size = 11;
      package = pkgs.inter;
    };

    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
  };

  #
  # Qt
  #

  qt = {
    enable = true;

    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };

  #
  # Cursor
  #

  home.pointerCursor = {
    package = pkgs.vanilla-dmz;
    name = "Vanilla-DMZ";
    size = 24;

    gtk.enable = true;
    x11.enable = true;
  };

  #
  # Terminal
  #

  programs.kitty = {
    enable = true;

    font = {
      package = pkgs.nerd-fonts.jetbrains-mono;
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };

    settings = {
      background = "#14161c";
      foreground = "#e6e6e6";

      cursor = "#e6e6e6";

      selection_background = "#3b4252";
      selection_foreground = "#ffffff";

      window_padding_width = 8;

      enable_audio_bell = false;
    };
  };

  #
  # Application launcher
  #

  programs.fuzzel = {
    enable = true;

    settings = {
      main = {
        terminal = "${pkgs.kitty}/bin/kitty";

        font = "Inter:size=11";
        "icon-theme" = "Adwaita";

        width = 40;
        lines = 12;
      };

      colors = {
        background = "14161cee";
        text = "e6e6e6ff";
        prompt = "e6e6e6ff";
        placeholder = "888888ff";
        input = "e6e6e6ff";

        match = "89b4faff";

        selection = "3b4252ff";
        "selection-text" = "ffffffff";
        "selection-match" = "89b4faff";

        counter = "888888ff";

        border = "5e81acff";
      };

      border = {
        width = 2;
        radius = 10;
      };
    };
  };
}
