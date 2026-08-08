{ ... }:

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

  # Keep Hyprland's native Lua config as a normal file for now.
  xdg.configFile."hypr/hyprland.lua".source =
    ./hyprland.lua;

  home.stateVersion = "26.05";
}
