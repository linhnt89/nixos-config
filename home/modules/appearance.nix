{ pkgs, ... }:

let
  theme = import ../theme.nix;
  c = theme.colors;
in
{
  #
  # Desktop appearance preference
  #
  # Use the freedesktop / GNOME color-scheme preference
  # instead of Home Manager's gtk.colorScheme option.
  #
  # gtk.colorScheme currently produces a GTK4 setting that
  # GTK4/libadwaita rejects on Home Manager 26.05.
  #

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      "color-scheme" = "prefer-dark";
    };
  };

  #
  # GTK
  #

  gtk = {
    enable = true;

    font = {
      name = theme.fonts.sans;
      size = 11;
      package = pkgs.inter;
    };

    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    #
    # GTK3 still understands this preference directly.
    #
    # Do not put it into GTK4 settings.ini because
    # libadwaita does not use that mechanism.
    #

    gtk3.extraConfig = {
      "gtk-application-prefer-dark-theme" = true;
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
