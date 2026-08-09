{ pkgs, ... }:

let
  #
  # Shared theme
  #

  theme = import ../theme.nix;
  c = theme.colors;

  #
  # Wallpaper
  #

  wallpaper = pkgs.nixos-artwork.wallpapers.nineish-dark-gray.gnomeFilePath;

  #
  # Session / power menu
  #

  powerMenu = pkgs.writeShellApplication {
    name = "power-menu";

    runtimeInputs = [
      pkgs.fuzzel
      pkgs.uwsm
      pkgs.systemd
    ];

    text = ''
      choice="$(
        printf '%s\n' \
          "Lock" \
          "Logout" \
          "Reboot" \
          "Shutdown" |
          fuzzel \
            --dmenu \
            --prompt="Power > "
      )" || exit 0

      confirm_action() {
        action="$1"

        answer="$(
          printf '%s\n' \
            "No" \
            "Yes" |
            fuzzel \
              --dmenu \
              --prompt="$action? > "
        )" || return 1

        [ "$answer" = "Yes" ]
      }

      case "$choice" in
        "Lock")
          loginctl lock-session
          ;;

        "Logout")
          if confirm_action "Logout"; then
            uwsm stop
          fi
          ;;

        "Reboot")
          if confirm_action "Reboot"; then
            systemctl reboot
          fi
          ;;

        "Shutdown")
          if confirm_action "Shutdown"; then
            systemctl poweroff
          fi
          ;;
      esac
    '';
  };
in
{
  #
  # Session utilities
  #

  home.packages = [
    powerMenu
  ];

  #
  # XDG autostart overrides
  #
  # Network status and controls are provided by Waybar.
  #
  # Keep NetworkManager and nm-connection-editor available,
  # but do not run the redundant nm-applet tray application.
  #

  xdg.configFile."autostart/nm-applet.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=NetworkManager Applet
    Exec=nm-applet
    Hidden=true
  '';

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

      font = "${theme.fonts.sans} 11";

      background-color = "#${c.surface}f2";
      text-color = "#${c.text}ff";

      border-color = "#${c.border}ff";
      border-size = 1;
      border-radius = theme.radius.panel;

      width = 360;

      margin = 12;
      padding = 12;

      default-timeout = 5000;

      icons = true;
    };
  };

  #
  # Explicit systemd service because D-Bus activation did not
  # work correctly in our UWSM session.
  #

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
      ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch " + "${pkgs.cliphist}/bin/cliphist store";

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
          color = "rgb(${c.background})";
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
          rounding = theme.radius.panel;

          dots_center = true;
          fade_on_empty = false;

          inner_color = "rgb(${c.surface})";
          outer_color = "rgb(${c.accentDim})";
          font_color = "rgb(${c.text})";

          placeholder_text = "Password...";
        }
      ];
    };
  };

  #
  # Idle management
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
  # Hyprland native Lua configuration
  #

  xdg.configFile."hypr/hyprland.lua".source = ../hyprland.lua;
}
