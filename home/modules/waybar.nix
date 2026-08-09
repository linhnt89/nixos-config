{ pkgs, ... }:

let
  theme = import ../theme.nix;

  c = theme.colors;
  r = theme.radius;

  #
  # MetaCube hardware status
  #
  # Reads directly from kernel sysfs interfaces.
  #
  # No lm_sensors process is required at runtime.
  #

  metacubeStatus = pkgs.writeShellScript "metacube-waybar-status" ''
    cpu_temp_raw=""
    soc_power_raw=""
    gpu_busy=""
    profile="unknown"

    #
    # Find sensors by hwmon name rather than hwmon number.
    #
    # hwmon numbers can change between boots.
    #

    for hwmon in /sys/class/hwmon/hwmon*; do
      [ -r "$hwmon/name" ] || continue

      IFS= read -r hwmon_name < "$hwmon/name"

      case "$hwmon_name" in
        k10temp)
          if [ -r "$hwmon/temp1_input" ]; then
            IFS= read -r cpu_temp_raw < "$hwmon/temp1_input"
          fi
          ;;

        amdgpu)
          if [ -r "$hwmon/power1_input" ]; then
            IFS= read -r soc_power_raw < "$hwmon/power1_input"
          elif [ -r "$hwmon/power1_average" ]; then
            IFS= read -r soc_power_raw < "$hwmon/power1_average"
          fi
          ;;
      esac
    done

    #
    # GPU utilization
    #

    for card in /sys/class/drm/card[0-9]*; do
      busy_file="$card/device/gpu_busy_percent"

      if [ -r "$busy_file" ]; then
        IFS= read -r gpu_busy < "$busy_file"
        break
      fi
    done

    #
    # Firmware platform profile
    #

    if [ -r /sys/firmware/acpi/platform_profile ]; then
      IFS= read -r profile \
        < /sys/firmware/acpi/platform_profile
    fi

    #
    # Convert millidegrees Celsius to degrees Celsius.
    #

    temp_c="?"

    if [[ "$cpu_temp_raw" =~ ^[0-9]+$ ]]; then
      temp_c=$((cpu_temp_raw / 1000))
    fi

    #
    # Convert microwatts to watts.
    #

    power_w="?"

    if [[ "$soc_power_raw" =~ ^[0-9]+$ ]]; then
      power_w=$(((soc_power_raw + 500000) / 1000000))
    fi

    #
    # GPU value fallback.
    #

    if ! [[ "$gpu_busy" =~ ^[0-9]+$ ]]; then
      gpu_busy="?"
    fi

    #
    # Temperature state for Waybar CSS.
    #

    status_class="normal"

    if [[ "$temp_c" =~ ^[0-9]+$ ]]; then
      if ((temp_c >= 85)); then
        status_class="critical"
      elif ((temp_c >= 75)); then
        status_class="warning"
      fi
    fi

    #
    # Waybar JSON output.
    #

    printf \
      '{"text":"%s°  %sW","tooltip":"CPU temperature: %s°C\\nSoC power: %s W\\nGPU busy: %s%%\\nPlatform profile: %s","class":"%s"}\n' \
      "$temp_c" \
      "$power_w" \
      "$temp_c" \
      "$power_w" \
      "$gpu_busy" \
      "$profile" \
      "$status_class"
  '';
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
            "custom/metacube"
            "pulseaudio"
            "network"
            "bluetooth"
          ];
        };

        #
        # CPU utilization
        #

        cpu = {
          interval = 10;

          format = " {usage}%";

          tooltip-format =
            "CPU usage: {usage}%\n" + "Load: {load1}\n" + "Average frequency: {avg_frequency} GHz";

          states = {
            warning = 70;
            critical = 90;
          };
        };

        #
        # MetaCube hardware status
        #

        "custom/metacube" = {
          exec = "${metacubeStatus}";

          interval = 10;

          return-type = "json";

          format = "{}";

          tooltip = true;
        };

        #
        # Audio
        #

        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = "";

          format-icons = {
            headphone = "";
            headset = "";

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
          format-ethernet = "";
          format-disconnected = "";

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
          format-disabled = "";
          format-connected = " {num_connections}";

          tooltip-format = "{controller_alias}";

          tooltip-format-connected = "{controller_alias}\n{device_enumerate}";

          tooltip-format-enumerate-connected = "{device_alias}";

          on-click = "blueman-manager";
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

      /*
       * Use one font for the complete status area.
       *
       * This prevents mixed Inter / Nerd Font metrics from
       * making icons and numerical values look vertically
       * misaligned.
       */

      #cpu,
      #custom-metacube,
      #pulseaudio,
      #network,
      #bluetooth {
        margin: 3px 0;
        padding: 0 9px;

        border-radius: ${toString r.control}px;

        font-family: "${theme.fonts.mono}";

        color: #${c.textMuted};
        background: transparent;
      }

      #cpu:hover,
      #custom-metacube:hover,
      #pulseaudio:hover,
      #network:hover,
      #bluetooth:hover {
        color: #${c.text};
        background: #${c.surfaceAlt};
      }

      /*
       * CPU utilization states
       */

      #cpu.warning {
        color: #${c.warning};
      }

      #cpu.critical {
        color: #${c.danger};
      }

      /*
       * MetaCube thermal states
       */

      #custom-metacube.warning {
        color: #${c.warning};
      }

      #custom-metacube.critical {
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
       * Power
       */

      #custom-power {
        min-width: 34px;

        padding: 0 2px;

        font-family: "${theme.fonts.mono}";

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
