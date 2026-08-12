{ config, ... }:

let
  #
  # Pi configuration authored in the canonical main checkout.
  #
  # Out-of-store symlinks keep the authored files version-controlled
  # while allowing Pi and its extensions to read them directly.
  #

  piConfigDir =
    "${config.home.homeDirectory}/nixos-config/home/pi";
in
{
  #
  # Authored Pi configuration
  #
  # Credentials, sessions, trust state, installed package contents,
  # and other runtime data remain local under ~/.pi/.
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

  home.file.".pi/agent/openai-server-compaction.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/openai-server-compaction.json";

  home.file.".pi/web-search.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/web-search.json";
}
