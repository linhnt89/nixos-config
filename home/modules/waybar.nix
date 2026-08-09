{ pkgs, ... }:

{
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

        #
        # Workspaces
        #

        "hyprland/workspaces" = {
          format = "{name}";

          persistent-workspaces = {
            "*" = 5;
          };
        };

        #
        # Clock
        #

        clock = {
          interval = 60;

          format = "{:%H:%M}";
          tooltip-format = "{:%A, %d %B %Y}";
        };

        #
        # Audio
        #

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

        #
        # Network
        #

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

        #
        # Bluetooth
        #

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

        #
        # Tray
        #

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
}
