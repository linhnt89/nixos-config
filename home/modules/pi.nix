{ config, ... }:

let
  #
  # Pi configuration authored in the canonical main checkout.
  #
  # These are intentionally out-of-store symlinks so Pi settings
  # can be edited in place without rebuilding the system.
  #

  piConfigDir =
    "${config.home.homeDirectory}/nixos-config/home/pi";
in
{
  #
  # Pi authored configuration
  #
  # Do not manage ~/.pi/agent/auth.json here.
  # Credentials and runtime state remain local to Pi.
  #

  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/settings.json";

  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/models.json";
}
