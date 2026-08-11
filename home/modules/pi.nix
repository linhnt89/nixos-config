{ config, ... }:

let
  #
  # Pi configuration authored in the canonical main checkout.
  #
  # Out-of-store symlinks keep the authored files version-controlled
  # while allowing Pi to read/edit them directly.
  #

  piConfigDir =
    "${config.home.homeDirectory}/nixos-config/home/pi";
in
{
  #
  # Authored Pi configuration
  #
  # Credentials, sessions, trust state, and other runtime data
  # remain local under ~/.pi/agent/.
  #

  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/settings.json";

  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/models.json";

  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/AGENTS.md";
}
