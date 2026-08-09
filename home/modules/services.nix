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
  # Wi-Fi quick setting
  #

  wifiToggle = pkgs.writeShellApplication {
    name = "metacube-wifi-toggle";

    runtimeInputs = [
      pkgs.networkmanager
    ];

    text = ''
      set -u

      if [ "''${SWAYNC_TOGGLE_STATE:-false}" = "true" ]; then
        nmcli radio wifi on
      else
        nmcli radio wifi off
      fi
    '';
  };

  wifiState = pkgs.writeShellApplication {
    name = "metacube-wifi-state";

    runtimeInputs = [
      pkgs.networkmanager
    ];

    text = ''
      if [ "$(nmcli radio wifi)" = "enabled" ]; then
        echo true
      else
        echo false
      fi
    '';
  };

  #
  # Bluetooth quick setting
  #
  # A Bluetooth controller can be disabled at two levels:
  #
  # 1. kernel RFKill
  # 2. BlueZ controller power
  #
  # When the controller is RFKill blocked, clear that state
  # first through the privileged NixOS pkexec wrapper.
  #
  # Do not RFKill the controller again when simply turning
  # Bluetooth off. This allows later on/off operations to
  # stay unprivileged in the normal case.
  #

  bluetoothToggle = pkgs.writeShellApplication {
    name = "metacube-bluetooth-toggle";

    runtimeInputs = [
      pkgs.bluez
      pkgs.gnugrep
      pkgs.libnotify
    ];

    text = ''
      set -u

      requested_state="''${SWAYNC_TOGGLE_STATE:-false}"

      is_powered() {
        bluetoothctl show 2>/dev/null \
          | grep -q 'Powered: yes'
      }

      is_soft_blocked() {
        for rfkill in /sys/class/rfkill/rfkill*; do
          [ -r "$rfkill/type" ] || continue
          [ -r "$rfkill/soft" ] || continue

          IFS= read -r type < "$rfkill/type"

          [ "$type" = "bluetooth" ] || continue

          IFS= read -r soft < "$rfkill/soft"

          if [ "$soft" = "1" ]; then
            return 0
          fi
        done

        return 1
      }

      if [ "$requested_state" = "true" ]; then
        #
        # RFKill must be cleared before BlueZ can control
        # the adapter.
        #

        if is_soft_blocked; then
          if ! /run/wrappers/bin/pkexec \
            ${pkgs.util-linux}/bin/rfkill \
            unblock bluetooth
          then
            notify-send \
              "Bluetooth" \
              "Bluetooth could not be unblocked."

            exit 1
          fi

          #
          # On this MetaCube the controller can become
          # Powered=yes automatically after RFKill is
          # cleared. Give the kernel and BlueZ a moment
          # to settle before issuing another command.
          #

          for _ in 1 2 3 4 5; do
            if is_powered; then
              exit 0
            fi

            sleep 0.4
          done
        fi

        #
        # If RFKill did not automatically power the
        # controller, ask BlueZ explicitly.
        #
        # Retry briefly because BlueZ can report Busy
        # immediately after an RFKill transition.
        #

        if is_powered; then
          exit 0
        fi

        for _ in 1 2 3 4 5; do
          if bluetoothctl power on >/dev/null 2>&1; then
            exit 0
          fi

          sleep 0.5
        done

        notify-send \
          "Bluetooth" \
          "Bluetooth could not be powered on."

        exit 1
      else
        #
        # Leave RFKill unblocked.
        #
        # Only ask BlueZ to turn the controller off.
        #

        if is_powered; then
          if ! bluetoothctl power off; then
            notify-send \
              "Bluetooth" \
              "Bluetooth could not be powered off."

            exit 1
          fi
        fi
      fi
    '';
  };

  bluetoothState = pkgs.writeShellApplication {
    name = "metacube-bluetooth-state";

    runtimeInputs = [
      pkgs.bluez
      pkgs.gnugrep
    ];

    text = ''
      #
      # RFKill blocked always means effectively off.
      #

      for rfkill in /sys/class/rfkill/rfkill*; do
        [ -r "$rfkill/type" ] || continue
        [ -r "$rfkill/soft" ] || continue

        IFS= read -r type < "$rfkill/type"

        [ "$type" = "bluetooth" ] || continue

        IFS= read -r soft < "$rfkill/soft"

        if [ "$soft" = "1" ]; then
          echo false
          exit 0
        fi
      done

      if bluetoothctl show \
        | grep -q 'Powered: yes'
      then
        echo true
      else
        echo false
      fi
    '';
  };

  #
  # Privileged platform-profile setter
  #

  platformProfileSetter = pkgs.writeShellScript "metacube-set-platform-profile" ''
    set -eu

    profile_file="/sys/firmware/acpi/platform_profile"
    choices_file="/sys/firmware/acpi/platform_profile_choices"

    if [ "$#" -ne 1 ]; then
      echo \
        "Usage: metacube-set-platform-profile PROFILE" \
        >&2

      exit 2
    fi

    profile="$1"

    case "$profile" in
      low-power|balanced|performance)
        ;;
      *)
        echo "Unsupported profile: $profile" >&2
        exit 2
        ;;
    esac

    if [ ! -r "$choices_file" ]; then
      echo \
        "Platform profile choices are unavailable." \
        >&2

      exit 1
    fi

    choices="$(
      ${pkgs.coreutils}/bin/cat "$choices_file"
    )"

    case " $choices " in
      *" $profile "*)
        ;;
      *)
        echo \
          "Profile is not offered by firmware: $profile" \
          >&2

        exit 2
        ;;
    esac

    printf '%s\n' "$profile" > "$profile_file"
  '';

  #
  # Platform-profile chooser
  #

  platformProfileMenu = pkgs.writeShellApplication {
    name = "metacube-profile-menu";

    runtimeInputs = [
      pkgs.fuzzel
      pkgs.libnotify
      pkgs.swaynotificationcenter
    ];

    text = ''
            set -u

            profile_file="/sys/firmware/acpi/platform_profile"
            choices_file="/sys/firmware/acpi/platform_profile_choices"

            if [ ! -r "$profile_file" ] || [ ! -r "$choices_file" ]; then
              notify-send \
                "Power profile" \
                "Platform profiles are not available on this system."

              exit 1
            fi

            current="$(cat "$profile_file")"
            choices="$(cat "$choices_file")"

            #
            # Close SwayNC before Fuzzel opens.
            #

            swaync-client -t >/dev/null 2>&1 || true

            sleep 0.1

            menu=""

            for profile in $choices; do
              case "$profile" in
                low-power)
                  label="Low power"
                  ;;

                balanced)
                  label="Balanced"
                  ;;

                performance)
                  label="Performance"
                  ;;

                *)
                  label="$profile"
                  ;;
              esac

              if [ "$profile" = "$current" ]; then
                label="$label  •"
              fi

              if [ -n "$menu" ]; then
                menu="$menu
      "
              fi

              menu="$menu$label"
            done

            choice="$(
              printf '%s\n' "$menu" |
                fuzzel \
                  --dmenu \
                  --prompt="Power profile > "
            )" || exit 0

            case "$choice" in
              "Low power"|"Low power  •")
                profile="low-power"
                ;;

              "Balanced"|"Balanced  •")
                profile="balanced"
                ;;

              "Performance"|"Performance  •")
                profile="performance"
                ;;

              *)
                exit 0
                ;;
            esac

            #
            # No action is necessary when the selected profile
            # is already active.
            #

            if [ "$profile" = "$current" ]; then
              exit 0
            fi

            #
            # IMPORTANT:
            #
            # Use the NixOS setuid pkexec wrapper explicitly.
            #
            # Do not use plain "pkexec" here. A Nix package in
            # PATH can shadow /run/wrappers/bin/pkexec with the
            # non-setuid store binary.
            #

            if /run/wrappers/bin/pkexec \
              ${pkgs.bash}/bin/bash \
              ${platformProfileSetter} \
              "$profile"
            then
              case "$profile" in
                low-power)
                  name="Low power"
                  ;;

                balanced)
                  name="Balanced"
                  ;;

                performance)
                  name="Performance"
                  ;;

                *)
                  name="$profile"
                  ;;
              esac

              notify-send \
                "Power profile" \
                "Switched to $name."
            else
              #
              # Normal urgency is intentional.
              #
              # Critical notifications are configured to remain
              # visible until dismissed.
              #

              notify-send \
                "Power profile" \
                "The profile could not be changed."

              exit 1
            fi
    '';
  };

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
      # Main display
      #

      "control-center-preferred-output" = "HDMI-A-1";
      "notification-window-preferred-output" = "HDMI-A-1";

      "notification-window-width" = 420;

      #
      # Notification behavior
      #

      timeout = 6;
      "timeout-low" = 4;

      #
      # Critical notifications intentionally remain until
      # dismissed.
      #

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

      widgets = [
        "title"
        "dnd"
        "buttons-grid"
        "mpris"
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

        #
        # Quick settings
        #
        # update-command runs when the control center is
        # opened, so the visual state is resynchronized
        # with the real device state.
        #

        "buttons-grid" = {
          "buttons-per-row" = 3;

          actions = [
            {
              label = "Wi-Fi";
              type = "toggle";
              active = false;

              command = "${wifiToggle}/bin/metacube-wifi-toggle";

              "update-command" = "${wifiState}/bin/metacube-wifi-state";
            }

            {
              label = "Bluetooth";
              type = "toggle";
              active = false;

              command = "${bluetoothToggle}/bin/metacube-bluetooth-toggle";

              "update-command" = "${bluetoothState}/bin/metacube-bluetooth-state";
            }

            {
              label = "Profile";
              type = "normal";

              command = "${platformProfileMenu}/bin/metacube-profile-menu";
            }
          ];
        };

        #
        # Media controls
        #

        mpris = {
          autohide = true;

          "show-album-art" = "when-available";

          "loop-carousel" = false;
        };

        #
        # Volume
        #

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

    style = ''
      /*
       * Shared SwayNC variables
       */

      :root {
        --cc-bg: #${c.background};

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

        --mpris-album-art-icon-size: 72px;
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
       * Notification actions
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
       * Do Not Disturb
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
       * Quick settings
       */

      .widget-buttons-grid {
        margin: 6px 10px;
        padding: 0;

        background: transparent;
      }

      .widget-buttons-grid
      > flowbox
      > flowboxchild
      > button {
        min-height: 38px;

        margin: 0 3px;
        padding: 0 10px;

        color: #${c.textMuted};
        background: #${c.surface};

        border: 1px solid #${c.border};
        border-radius: ${toString theme.radius.control}px;

        box-shadow: none;
      }

      .widget-buttons-grid
      > flowbox
      > flowboxchild:first-child
      > button {
        margin-left: 0;
      }

      .widget-buttons-grid
      > flowbox
      > flowboxchild:last-child
      > button {
        margin-right: 0;
      }

      .widget-buttons-grid
      > flowbox
      > flowboxchild
      > button:hover {
        color: #${c.text};

        background: #${c.surfaceAlt};
      }

      .widget-buttons-grid
      > flowbox
      > flowboxchild
      > button.toggle:checked {
        color: #${c.background};
        background: #${c.accent};

        border-color: #${c.accent};
      }

      /*
       * MPRIS media card
       */

      .widget-mpris {
        margin: 6px 10px;
        padding: 0;

        color: #${c.text};

        background: transparent;
      }

      .widget-mpris-player {
        margin: 0;
        padding: 10px;

        color: #${c.text};
        background: #${c.surface};

        border: 1px solid #${c.border};
        border-radius: ${toString theme.radius.panel}px;

        box-shadow: none;
      }

      .mpris-overlay {
        background: transparent;
      }

      .widget-mpris-album-art {
        border-radius: ${toString theme.radius.control}px;

        box-shadow: none;
      }

      .widget-mpris-title {
        color: #${c.text};

        font-size: 13px;
        font-weight: 600;
      }

      .widget-mpris-subtitle {
        color: #${c.textMuted};

        font-size: 12px;
      }

      .widget-mpris button {
        margin: 2px;
        padding: 4px;

        color: #${c.textMuted};
        background: transparent;

        border: none;
        border-radius: ${toString theme.radius.control}px;

        box-shadow: none;
      }

      .widget-mpris button:hover {
        color: #${c.text};
        background: #${c.surfaceAlt};
      }

      .widget-mpris button:disabled {
        color: #${c.textDim};
        opacity: 0.6;
      }

      .widget-mpris button image {
        -gtk-icon-size: 18px;
      }

      /*
       * Volume
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
