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
  # Notifications / control center
  #
  # SwayNC replaces Mako as the notification daemon.
  #

  services.swaync = {
    enable = true;

    settings = {
      #
      # Window placement
      #

      positionX = "right";
      positionY = "top";

      "control-center-positionX" = "right";
      "control-center-positionY" = "top";

      layer = "overlay";
      "control-center-layer" = "overlay";

      "layer-shell" = true;
      "layer-shell-cover-screen" = true;

      #
      # Keep the panel aligned with our floating Waybar.
      #
      # Waybar:
      #   top margin  = 8 px
      #   height      = 38 px
      #
      # 8 + 38 + 8 = 54 px
      #

      "control-center-margin-top" = 54;
      "control-center-margin-right" = 10;
      "control-center-margin-bottom" = 10;
      "control-center-margin-left" = 10;

      #
      # Control center geometry
      #

      "fit-to-screen" = false;

      "control-center-width" = 420;
      "control-center-height" = 620;

      #
      # Use the MetaCube's main display explicitly.
      #

      "control-center-preferred-output" = "HDMI-A-1";
      "notification-window-preferred-output" = "HDMI-A-1";

      "notification-window-width" = 420;

      #
      # Notification behavior
      #

      timeout = 6;
      "timeout-low" = 4;

      # Critical notifications remain until dismissed.
      "timeout-critical" = 0;

      "relative-timestamps" = true;
      "notification-grouping" = true;

      "notification-2fa-action" = true;
      "notification-inline-replies" = false;

      "hide-on-action" = true;
      "hide-on-clear" = false;

      "keyboard-shortcuts" = true;

      #
      # Keep animations quick.
      #

      "transition-time" = 150;

      #
      # Prevent external GTK themes from changing SwayNC.
      #

      "ignore-gtk-theme" = true;
      cssPriority = "user";

      #
      # Control center layout
      #
      # Keep this intentionally small for the first version.
      #

      widgets = [
        "title"
        "dnd"
        "volume"
        "notifications"
      ];

      "widget-config" = {
        title = {
          text = "Notifications";

          "clear-all-button" = true;
          "button-text" = "Clear";
        };

        dnd = {
          text = "Do not disturb";
        };

        volume = {
          label = "";

          "show-per-app" = false;
        };

        notifications = {
          vexpand = true;
        };
      };
    };

    #
    # Theme
    #
    # SwayNC supplies the structure and widgets.
    # We override its visual language to match Waybar,
    # Fuzzel, Kitty, and the rest of our desktop.
    #

    style = ''
      /*
       * Shared SwayNC variables
       */

      :root {
        --cc-bg: #${c.background};

        /*
         * SwayNC expects this variable as RGB components
         * because its default CSS uses rgba(var(--noti-bg), ...).
         *
         * 1c1f26 = rgb(28, 31, 38)
         */

        --noti-bg: 28, 31, 38;
        --noti-bg-alpha: 1;

        --noti-border-color: #${c.border};

        --noti-bg-darker: #${c.background};
        --noti-bg-hover: #${c.surfaceAlt};
        --noti-bg-focus: #${c.surfaceHover};

        --noti-close-bg: #${c.surfaceAlt};
        --noti-close-bg-hover: #${c.surfaceHover};

        --text-color: #${c.text};
        --text-color-disabled: #${c.textDim};

        --bg-selected: #${c.accent};

        --border: 1px solid #${c.border};
        --border-radius: ${toString theme.radius.panel}px;

        --notification-shadow: none;

        --font-size-body: 13px;
        --font-size-summary: 13px;

        --notification-icon-size: 48px;
      }

      /*
       * Typography
       */

      * {
        font-family:
          "${theme.fonts.sans}",
          "${theme.fonts.mono}",
          sans-serif;
      }

      /*
       * Transparent layer-shell windows
       */

      notificationwindow,
      blankwindow,
      .blank-window,
      .floating-notifications {
        background: transparent;
      }

      /*
       * Floating notification placement
       *
       * Keep popups below the floating Waybar.
       */

      .floating-notifications {
        padding-top: 54px;
        padding-right: 10px;
      }

      /*
       * Notification cards
       */

      .notification-row {
        outline: none;
        background: transparent;
      }

      .notification {
        background: #${c.surface};

        border: 1px solid #${c.border};
        border-radius: ${toString theme.radius.panel}px;

        box-shadow: none;
      }

      .notification.critical {
        border-color: #${c.danger};
      }

      .notification-default-action {
        color: #${c.text};

        background: transparent;

        border: none;
        border-radius: ${toString theme.radius.panel}px;
      }

      .notification-default-action:hover {
        background: #${c.surfaceAlt};
      }

      .notification-content .summary {
        color: #${c.text};

        font-size: 13px;
        font-weight: 600;
      }

      .notification-content .body {
        color: #${c.textMuted};

        font-size: 13px;
      }

      .notification-content .time {
        color: #${c.textDim};

        font-size: 11px;
      }

      /*
       * Close button
       */

      .close-button {
        min-width: 24px;
        min-height: 24px;

        padding: 0;

        color: #${c.textMuted};
        background: #${c.surfaceAlt};

        border: none;
        border-radius: 999px;

        box-shadow: none;
      }

      .close-button:hover {
        color: #${c.text};
        background: #${c.surfaceHover};
      }

      /*
       * Alternative notification actions
       */

      .notification-action > button {
        color: #${c.text};

        background: #${c.surfaceAlt};

        border: none;
        border-radius: ${toString theme.radius.control}px;

        box-shadow: none;
      }

      .notification-action > button:hover {
        background: #${c.surfaceHover};
      }

      /*
       * Control center
       */

      .control-center {
        color: #${c.text};
        background: #${c.background};

        border: 1px solid #${c.border};
        border-radius: ${toString theme.radius.panel}px;

        box-shadow: none;
      }

      .control-center-list {
        background: transparent;
      }

      .control-center-list-placeholder {
        color: #${c.textDim};
      }

      /*
       * Shared widget geometry
       */

      .widget {
        margin: 6px 10px;
        padding: 10px 12px;

        border-radius: ${toString theme.radius.panel}px;
      }

      /*
       * Header
       */

      .widget-title {
        margin-top: 10px;
        margin-bottom: 2px;

        background: transparent;
      }

      .widget-title > label {
        color: #${c.text};

        font-size: 15px;
        font-weight: 600;
      }

      .widget-title > button {
        padding: 5px 10px;

        color: #${c.textMuted};
        background: #${c.surfaceAlt};

        border: 1px solid #${c.border};
        border-radius: ${toString theme.radius.control}px;

        box-shadow: none;
      }

      .widget-title > button:hover {
        color: #${c.text};
        background: #${c.surfaceHover};
      }

      /*
       * Do Not Disturb card
       */

      .widget-dnd {
        background: #${c.surface};

        border: 1px solid #${c.border};
      }

      .widget-dnd label {
        color: #${c.text};
      }

      .widget-dnd switch {
        background: #${c.surfaceAlt};

        border: 1px solid #${c.border};
        border-radius: 999px;

        box-shadow: none;
      }

      .widget-dnd switch:checked {
        background: #${c.accent};
      }

      .widget-dnd switch slider {
        background: #${c.text};

        border-radius: 999px;

        box-shadow: none;
      }

      /*
       * Volume card
       */

      .widget-volume {
        color: #${c.text};
        background: #${c.surface};

        border: 1px solid #${c.border};
      }

      .widget-volume label {
        color: #${c.textMuted};

        font-family: "${theme.fonts.mono}";
      }

      .widget-volume scale trough {
        min-height: 6px;

        background: #${c.surfaceAlt};

        border-radius: 999px;
      }

      .widget-volume scale highlight {
        min-height: 6px;

        background: #${c.accent};

        border-radius: 999px;
      }

      .widget-volume scale slider {
        min-width: 14px;
        min-height: 14px;

        background: #${c.text};

        border: none;
        border-radius: 999px;

        box-shadow: none;
      }
    '';
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
