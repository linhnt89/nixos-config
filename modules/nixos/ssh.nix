{ ... }:

{
  #
  # SSH server
  #
  # Remote terminal access for tools such as the Moshi
  # Android app.
  #
  # Authentication is key-only. Passwords and interactive
  # keyboard authentication are disabled, and root login is
  # forbidden, so a leaked password can never unlock this
  # machine over SSH.
  #
  # NOTE: Enabling sshd also opens TCP 22 in the NixOS
  # firewall (all interfaces) -- NixOS adds it to
  # networking.firewall.allowedTCPPorts automatically.
  # Whether that is the right exposure policy (plain LAN,
  # or restricted to a Tailscale/VPN interface instead) is
  # a captain decision; see docs/moshi-herdr.md. The mosh
  # UDP range is not opened here.
  #

  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
