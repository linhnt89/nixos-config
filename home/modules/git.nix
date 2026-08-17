{ ... }:

#
# Local adapter for the portable git/delta profile.
#
# The portable git module (nixdev-config home/modules/git.nix, imported
# via the desktop role in flake.nix) owns git *structure*: it enables
# programs.git with gitFull, sets init.defaultBranch = "main" and
# push.autoSetupRemote, and enables delta with git integration.
#
# This adapter carries ONLY MetaCube-personal content: the SSH-agent UWSM
# environment, personal git identity and workflow preferences, the delta
# UI options, and the SSH client identity — which the portable profile
# deliberately never contains.
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
  # Git — personal identity and workflow
  #
  # programs.git itself (enablement, gitFull package, defaultBranch,
  # autoSetupRemote) is owned by the portable profile.
  #

  programs.git.settings = {
    user = {
      # Keep your actual values here.
      name = "Linh Nguyen";
      email = "linhtramnguyen@gmail.com";
    };

    fetch.prune = true;

    pull.ff = "only";

    push = {
      default = "simple";
    };

    rebase.autoStash = true;

    diff.algorithm = "histogram";

    merge.conflictStyle = "zdiff3";
  };

  #
  # Git diff viewer — personal UI options
  #
  # programs.delta enablement + git integration are owned by the
  # portable profile; only the MetaCube UI preferences stay here.
  #

  programs.delta.options = {
    line-numbers = true;
    navigate = true;
    side-by-side = false;
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
