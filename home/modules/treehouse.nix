{ pkgs, treehouse, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  #
  # Treehouse
  #
  # Reusable isolated Git worktrees for development and
  # agent sessions.
  #

  home.packages = [
    treehouse.packages.${system}.default
  ];

  #
  # Treehouse configuration
  #
  # Start with a deliberately small pool. Increase this only
  # when actual parallel workloads justify it.
  #
  # No lifecycle hooks are configured yet.
  #

  xdg.configFile."treehouse/config.toml".text = ''
    max_trees = 4
  '';
}
