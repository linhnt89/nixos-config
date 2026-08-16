{ ... }:

{
  imports = [
    #
    # Generated hardware facts.
    #
    # We normally do not hand-edit this file.
    #

    ./hardware-configuration.nix

    #
    # Reusable NixOS policy.
    #

    ../../modules/nixos/base.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/hyprland.nix
    ../../modules/nixos/mango-experiment.nix
    ../../modules/nixos/ssh.nix
  ];

  #
  # MangoWM + Noctalia experiment
  #
  # Off by default; the module is inert unless this flag is flipped.
  # When enabled it only adds Mango/Noctalia packages + portal wiring and
  # generates the opt-in session configs; greetd/Hyprland stay untouched.
  # See docs/mango-noctalia-experiment.md.
  #

  metacube.experiments.mangoNoctalia.enable = false;

  #
  # Host identity
  #

  networking.hostName = "metacube";

  #
  # Boot
  #
  # This machine uses UEFI + systemd-boot.
  #

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  #
  # Graphics
  #
  # MetaCube uses the Radeon 780M integrated GPU.
  #

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  #
  # NixOS compatibility version
  #
  # This belongs to the installed machine rather than
  # to a reusable module.
  #

  system.stateVersion = "26.05";
}
