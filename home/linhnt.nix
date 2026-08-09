{ pkgs, ... }:

{
  home.username = "linhnt";
  home.homeDirectory = "/home/linhnt";

  programs.git = {
    enable = true;
	
    settings = {
      user = {
        name = "Linh Nguyen";
	email = "linhtramnguyen@gmail.com";
      };
    };
  };

  programs.zsh.enable = true;

  # Bootstrap browser
  programs.firefox.enable = true;

  # Bootstrap terminal. We can replace this later.
  programs.kitty.enable = true;

  # Bootstrap application launcher
  programs.fuzzel.enable = true;
  
  # Authentication
  services.hyprpolkitagent.enable = true;
  # Notification
  services.mako.enable = true;
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

  # Run clipboard history as a user service
  systemd.user.services.cliphist = {
    Unit = {
      Description = "Wayland clipboard history";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart =
        "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";

      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  home.packages = [
    pkgs.libnotify
    
    # Clipboard
    pkgs.wl-clipboard
    pkgs.cliphist

    # Screenshots
    pkgs.grim
    pkgs.slurp
  ];

  # Keep Hyprland's native Lua config as a normal file for now.
  xdg.configFile."hypr/hyprland.lua".source =
    ./hyprland.lua;

  # Hyprlock config
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
          color = "rgb(111318)";
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

          inner_color = "rgb(1e1e2e)";
          outer_color = "rgb(89b4fa)";
          font_color = "rgb(cdd6f4)";

          placeholder_text = "Password...";
        }
      ];
    };
  };

  # Hypridle
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";

        after_sleep_cmd =
          "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
      };

      listener = [
        {
          # Lock after 10 minutes.
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }

        #{
          # Turn displays off 30 seconds after locking.
         # timeout = 630;

          #on-timeout =
           # "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";

          #on-resume =
           # "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
        #}
      ];
    };
  };

  home.stateVersion = "26.05";
}
