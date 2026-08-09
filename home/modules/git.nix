{ pkgs, ... }:

{
  #
  # SSH agent environment
  #
  # NixOS starts ssh-agent and creates its socket at:
  #
  #   $XDG_RUNTIME_DIR/ssh-agent
  #
  # UWSM imports this file when starting the graphical
  # session, so GUI apps and systemd user services inherit
  # SSH_AUTH_SOCK too.
  #

  xdg.configFile."uwsm/env.d/10-ssh-agent".text = ''
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
  '';

  #
  # Git
  #

  programs.git = {
    enable = true;

    package = pkgs.gitFull;

    settings = {
      user = {
        # Keep your actual values here.
        name = "Linh Nguyen";
        email = "linhtramnguyen@gmail.com";
      };

      init.defaultBranch = "main";

      fetch.prune = true;

      pull.ff = "only";

      push = {
        default = "simple";
        autoSetupRemote = true;
      };

      rebase.autoStash = true;

      diff.algorithm = "histogram";

      merge.conflictStyle = "zdiff3";
    };
  };

  #
  # Git diff viewer
  #

  programs.delta = {
    enable = true;

    enableGitIntegration = true;

    options = {
      line-numbers = true;
      navigate = true;
      side-by-side = false;
    };
  };

  #
  # SSH client
  #

  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;

    settings = {
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
      };

      "github.com" = {
        HostName = "github.com";
        User = "git";

        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = true;

        AddKeysToAgent = "yes";
      };
    };
  };
}
