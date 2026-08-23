{
  pkgs,
  lib,
  ...
}:

#
# Dedicated `agent` Unix account for AI-agent runtime responsibility
# (Pi, Firstmate toolchain, Herdr, Claude Code).
#
# All agent runtime work moved off the personal `linhnt` desktop account
# into this restricted account with a kernel-enforced UID boundary:
# deliberately NO wheel/docker/libvirt/networkmanager membership, a
# locked password (SSH key-only access), and SSH connection forwarding
# disabled so a forwarded personal ssh-agent can never reach the tools
# running inside the account.
#
# Home Manager policy for the account lives in home/agent.nix (wired as
# a second Home Manager user in flake.nix). One-time runtime steps
# (fresh-cloning Firstmate under /home/agent, `gh auth login`, pasting
# the dedicated public keys below) happen after the switch and are not
# declared here.
#

{
  users.users.agent = {
    isNormalUser = true;
    description = "AI-agent runtime account";
    home = "/home/agent";
    createHome = true;
    homeMode = "0700";
    linger = true;

    # Locked password: the account is reachable only via its SSH keys
    # (and local console login by an admin). sshd already rejects
    # password auth globally; this keeps console/su consistent.
    hashedPassword = "!";

    # Match the house shell style (programs.zsh.enable in base.nix).
    shell = pkgs.zsh;

    # Deliberately empty: no wheel/docker/libvirt/networkmanager.
    extraGroups = [ ];

    openssh.authorizedKeys.keys = [
      # CAPTAIN ACTION REQUIRED: paste the two DEDICATED public keys here
      # (PC-local key and Haven key) once they are generated for this
      # account. Do NOT reuse linhnt's personal keys, and never commit
      # private key material.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPKBgC2mt7T2JDGIOhfLdW73V/SY3SANucXkboo2GrB"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJIU4Q7fmcxkb9fPzxhXI4laSpcklmjvdlQeiyNgdPu9 metacube-agent"
    ];
  };

  #
  # Per-user SSH hardening for the agent account.
  #
  # This Match block only narrows what the global sshd policy in
  # modules/nixos/ssh.nix already enforces (key-only auth, no root);
  # that file stays untouched. DisableForwarding covers the
  # forwarded-ssh-agent threat while PermitTTY yes still allows
  # interactive Herdr sessions (`ssh -t agent@... herdr`).
  #

  services.openssh.extraConfig = ''
    Match User agent
        DisableForwarding yes
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitTunnel no
        PermitTTY yes
        PermitUserRC no

    Match all
  '';

  #
  # Package-set exception: permit exactly Claude Code (unfree) without
  # turning on a global allowUnfree. Consumed by home/agent.nix via
  # pkgs.claude-code; the desktop user's package set is unaffected.
  #

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code"
    ];
}
