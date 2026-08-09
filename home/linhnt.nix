{ pkgs, ... }:

let
  wallpaper =
    pkgs.nixos-artwork.wallpapers.nineish-dark-gray.gnomeFilePath;
in
{
  home.username = "linhnt";
  home.homeDirectory = "/home/linhnt";

  #
  # Git
  #

  programs.git = {
    enable = true;

    settings = {
      user = {
        # Keep your actual values here.
        name = "Linh Nguyen";
        email = "linhtramnguyen@gmail.com";
      };
    };
  };

  #
  # Appearance
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

  qt = {
    enable = true;

    platformTheme.name = "adwaita";
    style.name = "adwaita-dark";
  };

  home.pointerCursor = {
    package = pkgs.vanilla-dmz;
    name = "Vanilla-DMZ";
    size = 24;

    gtk.enable = true;
    x11.enable = true;
  };

  #
  # Shell
  #

  programs.zsh.enable = true;

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
  # Browser
  #

  programs.firefox.enable = true;

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

  #
  # Media player
  #

  programs.mpv = {
    enable = true;

    # Expose mpv through the standard MPRIS media-control interface.
    scripts = [
      pkgs.mpvScripts.mpris
    ];

    config = {
      # Let mpv choose a supported hardware decoder.
      hwdec = "auto-safe";

      # Remember where we stopped a file.
      save-position-on-quit = true;

      # Keep the window open when playing audio-only media.
      force-window = true;
    };
  };

  # Provides playerctl plus the playerctld MPRIS daemon.
  services.playerctld.enable = true;

  #
  # PDF/document viewer
  #

  programs.zathura.enable = true;

  #
  # Packages without dedicated configuration modules
  #

  home.packages = [
    # Notifications
    pkgs.libnotify

    # Clipboard
    pkgs.wl-clipboard
    pkgs.cliphist

    # Screenshots
    pkgs.grim
    pkgs.slurp

    # Audio control
    pkgs.pavucontrol

    # NetworkManager connection editor
    pkgs.networkmanagerapplet

    # Archive manager
    pkgs.xarchiver

    # Image viewer
    pkgs.imv
  ];

  #
  # Default applications
  #

  xdg.mimeApps = {
    enable = true;

    defaultApplicationPackages = [
      pkgs.thunar
      pkgs.xarchiver
      pkgs.imv
      pkgs.zathura
      pkgs.mpv
    ];
  };

  #
  # Polkit authentication agent
  #

  services.hyprpolkitagent.enable = true;

  #
  # Notifications
  #

  services.mako = {
    enable = true;

    settings = {
      anchor = "top-right";

      font = "Inter 11";

      background-color = "#14161cee";
      text-color = "#e6e6e6ff";

      border-color = "#5e81acff";
      border-size = 2;
      border-radius = 10;

      width = 360;

      margin = 12;
      padding = 12;

      default-timeout = 5000;

      icons = true;
    };
  };

  # Explicit systemd service because D-Bus activation did not
  # work correctly in our UWSM session.
  systemd.user.services.mako = {
    Unit = {
      Description = "Mako notification daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.mako}/bin/mako";
      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  #
  # Clipboard history
  #

  systemd.user.services.cliphist = {
    Unit = {
      Description = "Wayland clipboard history";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart =
        "${pkgs.wl-clipboard}/bin/wl-paste --watch "
        + "${pkgs.cliphist}/bin/cliphist store";

      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  #
  # Screen locking
  #

  programs.hyprlock = {
    enable = true;

    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = true;
      };

      background = [
        {
          monitor = "";
          color = "rgb(14161c)";
        }
      ];

      "input-field" = [
        {
          monitor = "";

          size = "260, 52";
          position = "0, -60";

          halign = "center";
          valign = "center";

          outline_thickness = 3;
          rounding = 12;

          dots_center = true;
          fade_on_empty = false;

          inner_color = "rgb(1c1f26)";
          outer_color = "rgb(5e81ac)";
          font_color = "rgb(e6e6e6)";

          placeholder_text = "Password...";
        }
      ];
    };
  };

  #
  # Idle management
  #
  # Lock only.
  # DPMS remains disabled for now.
  #

  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
      };

      listener = [
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
      ];
    };
  };

  #
  # Wallpaper
  #

  services.hyprpaper = {
    enable = true;

    settings = {
      splash = false;

      wallpaper = [
        {
          monitor = "";
          path = wallpaper;
          fit_mode = "cover";
        }
      ];
    };
  };

  #
  # Waybar
  #

  programs.waybar = {
    enable = true;

    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 32;
        spacing = 8;

        modules-left = [
          "hyprland/workspaces"
        ];

        modules-center = [
          "clock"
        ];

        modules-right = [
          "pulseaudio"
          "network"
          "bluetooth"
          "tray"
        ];

        "hyprland/workspaces" = {
          format = "{name}";

          persistent-workspaces = {
            "*" = 5;
          };
        };

        clock = {
          interval = 60;

          format = "{:%H:%M}";
          tooltip-format = "{:%A, %d %B %Y}";
        };

        pulseaudio = {
          format = "VOL {volume}%";
          format-muted = "MUTED";

          on-click =
            "${pkgs.pavucontrol}/bin/pavucontrol";

          on-click-right =
            "${pkgs.wireplumber}/bin/wpctl "
            + "set-mute @DEFAULT_AUDIO_SINK@ toggle";

          on-scroll-up =
            "${pkgs.wireplumber}/bin/wpctl "
            + "set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";

          on-scroll-down =
            "${pkgs.wireplumber}/bin/wpctl "
            + "set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        };

        network = {
          format-wifi =
            "Wi-Fi {essid} {signalStrength}%";

          format-ethernet =
            "LAN {ifname}";

          format-disconnected =
            "Offline";

          tooltip-format-wifi =
            "{essid}\n{ifname}: {ipaddr}";

          tooltip-format-ethernet =
            "{ifname}: {ipaddr}";

          tooltip-format-disconnected =
            "Network disconnected";

          on-click =
            "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
        };

        bluetooth = {
          format = "BT {status}";
          format-disabled = "BT off";
          format-connected = "BT {num_connections}";

          tooltip-format-connected =
            "{controller_alias}\n{device_enumerate}";

          tooltip-format-enumerate-connected =
            "{device_alias}";

          on-click = "blueman-manager";
        };

        tray = {
          spacing = 8;
        };
      };
    };

    style = ''
      * {
        border: none;
        border-radius: 0;

        font-family: Inter, sans-serif;
        font-size: 13px;

        min-height: 0;
      }

      window#waybar {
        background: rgba(20, 22, 28, 0.92);
        color: #e6e6e6;
      }

      #workspaces button {
        padding: 0 9px;

        color: #a8a8a8;
        background: transparent;
      }

      #workspaces button.active {
        color: #ffffff;
        background: #3b4252;
      }

      #workspaces button.urgent {
        color: #ffffff;
        background: #8f3f3f;
      }

      #clock,
      #pulseaudio,
      #network,
      #bluetooth,
      #tray {
        padding: 0 10px;
      }

      #pulseaudio.muted {
        color: #888888;
      }

      #network.disconnected,
      #bluetooth.disabled {
        color: #888888;
      }
    '';
  };

  #
  # Hyprland native Lua configuration
  #

  xdg.configFile."hypr/hyprland.lua".source =
    ./hyprland.lua;

  #
  # Home Manager compatibility version
  #

  home.stateVersion = "26.05";
}
