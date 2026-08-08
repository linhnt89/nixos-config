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

  home.packages = [
    pkgs.libnotify
  ];

  # Keep Hyprland's native Lua config as a normal file for now.
  xdg.configFile."hypr/hyprland.lua".source =
    ./hyprland.lua;

  home.stateVersion = "26.05";
}
