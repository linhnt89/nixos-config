{ pkgs, ... }:

let
  theme = import ../theme.nix;
  c = theme.colors;
in
{
  #
  # GTK
  #

  gtk = {
    enable = true;

    colorScheme = "dark";

    font = {
      name = theme.fonts.sans;
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
      name = theme.fonts.mono;
      size = 11;
    };

    settings = {
      background = "#${c.background}";
      foreground = "#${c.text}";

      cursor = "#${c.text}";

      selection_background = "#${c.surfaceAlt}";
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

        font = "${theme.fonts.sans}:size=11";
        "icon-theme" = "Adwaita";

        width = 40;
        lines = 12;
      };

      colors = {
        background = "${c.background}ee";
        text = "${c.text}ff";
        prompt = "${c.text}ff";
        placeholder = "${c.textDim}ff";
        input = "${c.text}ff";

        match = "${c.accent}ff";

        selection = "${c.surfaceAlt}ff";
        "selection-text" = "ffffffff";
        "selection-match" = "${c.accent}ff";

        counter = "${c.textDim}ff";

        border = "${c.accentDim}ff";
      };

      border = {
        width = 2;
        radius = theme.radius.panel;
      };
    };
  };
}
