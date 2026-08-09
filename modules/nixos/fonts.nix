{ pkgs, ... }:

{
  #
  # Installed fonts
  #

  fonts.packages = [
    pkgs.inter

    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
    pkgs.noto-fonts-color-emoji

    pkgs.nerd-fonts.jetbrains-mono
  ];

  #
  # Default font families
  #

  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Inter"
      "Noto Sans"
    ];

    serif = [
      "Noto Serif"
    ];

    monospace = [
      "JetBrainsMono Nerd Font"
    ];

    emoji = [
      "Noto Color Emoji"
    ];
  };
}
