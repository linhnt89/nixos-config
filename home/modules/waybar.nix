{ pkgs, ... }:

let
  theme = import ../theme.nix;

  c = theme.colors;
  r = theme.radius;
in
{
  programs.waybar = {
    enable = true;

    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";

        height = 38;

        margin-top = 8;
        margin-left = 10;
        margin-right = 10;

        spacing = 8;

        modules-left = [
          "hyprland/workspaces"
        ];

        modules-center = [
          "clock"
        ];

        modules-right = [
          "group/status"
          "tray"
          "custom/power"
        ];

        #
        # Workspaces
        #

        "hyprland/workspaces" = {
          format = "{icon}";

          format-icons = {
            active = "";
            empty = "";
            persistent = "";
            default = "";
            urgent = "";
          };

          persistent-workspaces = {
            "*" = 5;
          };

          tooltip = false;
        };

        #
        # Clock
        #

        clock = {
          interval = 60;

          format = "{:%a %d %b  ·  %H:%M}";
          tooltip-format = "{:%A, %d %B %Y}";
        };

        #
        # Unified status island
        #

        "group/status" = {
          orientation = "horizontal";

          modules = [
            "cpu"
            "pulseaudio"
            "network"
            "bluetooth"
          ];
        };

        #
        # CPU
        #

        cpu = {
          interval = 10;

          format = " {usage}%";

          tooltip-format =
            "CPU usage: {usage}%\n" + "Load: {load1}\n" + "Average frequency: {avg_frequency} GHz";

          states = {
            warning = 70;
            critical = 90;
          };
        };

        #
        # Audio
        #

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "󰝟";

          format-icons = {
            headphone = "";
            headset = "󰋎";

            default = [
              ""
              ""
              ""
            ];
          };

          tooltip-format = "{desc}\nVolume: {volume}%";

          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";

          on-click-right = "${pkgs.wireplumber}/bin/wpctl " + "set-mute @DEFAULT_AUDIO_SINK@ toggle";

          on-scroll-up = "${pkgs.wireplumber}/bin/wpctl " + "set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";

          on-scroll-down = "${pkgs.wireplumber}/bin/wpctl " + "set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        };

        #
        # Network
        #

        network = {
          format-wifi = " {signalStrength}%";
          format-ethernet = "󰈀";
          format-disconnected = "󰖪";

          tooltip-format-wifi = "{essid}\n" + "{ifname}: {ipaddr}\n" + "Signal: {signalStrength}%";

          tooltip-format-ethernet = "{ifname}: {ipaddr}";

          tooltip-format-disconnected = "Network disconnected";

          on-click = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
        };

        #
        # Bluetooth
        #

        bluetooth = {
          format = "";
          format-disabled = "󰂲";
          format-connected = " {num_connections}";

          tooltip-format = "{controller_alias}";

          tooltip-format-connected = "{controller_alias}\n{device_enumerate}";

          tooltip-format-enumerate-connected = "{device_alias}";

          on-click = "blueman-manager";
        };

        #
        # Tray
        #

        tray = {
          spacing = 8;
        };

        #
        # Power menu
        #

        "custom/power" = {
          format = "";

          tooltip = false;

          on-click = "power-menu";
        };
      };
    };

    style = ''
      /*
       * Global
       */

      * {
        border: none;

        font-family:
          "${theme.fonts.sans}",
          "${theme.fonts.mono}",
          sans-serif;

        font-size: 13px;

        min-height: 0;
      }

      window#waybar {
        background: transparent;
        color: #${c.text};
      }

      /*
       * Shared floating surfaces
       */

      #workspaces,
      #clock,
      #status,
      #tray,
      #custom-power {
        background: #${c.surface};

        border: 1px solid #${c.border};
        border-radius: ${toString r.panel}px;
      }

      /*
       * Workspaces
       */

      #workspaces {
        padding: 4px 5px;
      }

      #workspaces button {
        min-width: 22px;

        margin: 0 1px;
        padding: 0 5px;

        border-radius: ${toString r.control}px;

        color: #${c.textDim};
        background: transparent;
      }

      #workspaces button:hover {
        color: #${c.text};
        background: #${c.surfaceAlt};
      }

      #workspaces button.active {
        color: #${c.accent};
        background: #${c.surfaceAlt};
      }

      #workspaces button.persistent {
        color: #${c.textMuted};
      }

      #workspaces button.persistent.active {
        color: #${c.accent};
      }

      #workspaces button.urgent {
        color: #${c.danger};
        background: #${c.surfaceAlt};
      }

      /*
       * Clock
       */

      #clock {
        padding: 0 14px;
      }

      /*
       * Unified status island
       */

      #status {
        padding: 0 4px;
      }

      #cpu,
      #pulseaudio,
      #network,
      #bluetooth {
        margin: 3px 0;
        padding: 0 9px;

        border-radius: ${toString r.control}px;

        color: #${c.textMuted};
        background: transparent;
      }

      #cpu:hover,
      #pulseaudio:hover,
      #network:hover,
      #bluetooth:hover {
        color: #${c.text};
        background: #${c.surfaceAlt};
      }

      /*
       * CPU states
       */

      #cpu.warning {
        color: #${c.warning};
      }

      #cpu.critical {
        color: #${c.danger};
      }

      /*
       * Audio states
       */

      #pulseaudio.muted {
        color: #${c.textDim};
      }

      /*
       * Network states
       */

      #network.disconnected {
        color: #${c.textDim};
      }

      /*
       * Bluetooth states
       */

      #bluetooth.disabled {
        color: #${c.textDim};
      }

      #bluetooth.connected {
        color: #${c.accent};
      }

      /*
       * System tray
       */

      #tray {
        padding: 0 11px;
      }

      /*
       * Power
       */

      #custom-power {
        min-width: 34px;

        padding: 0 2px;

        color: #${c.textMuted};
      }

      #custom-power:hover {
        color: #${c.danger};
        background: #${c.surfaceAlt};
      }

      /*
       * Tooltips
       */

      tooltip {
        background: #${c.surface};
        color: #${c.text};

        border: 1px solid #${c.border};
        border-radius: ${toString r.panel}px;
      }

      tooltip label {
        color: #${c.text};
        padding: 6px;
      }
    '';
  };
}
