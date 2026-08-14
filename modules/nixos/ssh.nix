{ ... }:

{
  #
  # Remote access (SSH + mosh) for tools such as the Moshi
  # Android app, plus Tailscale for external access.
  #
  # Access policy (captain decision, see docs/moshi-herdr.md):
  #
  # - sshd is key-only: passwords and interactive keyboard
  #   auth are disabled, root login is forbidden.
  # - Tailscale runs as a declarative client daemon; logging
  #   in (`tailscale up`) stays a manual one-time step so no
  #   auth key ever lands in this repository.
  # - TCP 22 and mosh UDP 60000-61000 are allowed ONLY on the
  #   trusted wired LAN interface (eno1) and the tailnet
  #   interface (tailscale0). sshd's automatic all-interface
  #   firewall rule is disabled via services.openssh.openFirewall
  #   = false; WAN/public interfaces and currently unused
  #   ports (enp5s0, wlp4s0) stay closed.
  #

  services.openssh = {
    enable = true;

    # No implicit all-interface TCP 22 rule; the firewall
    # rules below are scoped explicitly.
    openFirewall = false;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  #
  # Tailscale client (external access path)
  #

  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--netfilter-mode=off" ];
  };

  #
  # Interface-scoped firewall
  #

  networking.firewall.interfaces = {
    # Trusted wired LAN (currently connected home network).
    eno1 = {
      allowedTCPPorts = [ 22 ];
      allowedUDPPortRanges = [
        { from = 60000; to = 61000; }
      ];
    };

    # Tailnet; reachable from anywhere the device is logged in.
    tailscale0 = {
      allowedTCPPorts = [ 22 ];
      allowedUDPPortRanges = [
        { from = 60000; to = 61000; }
      ];
    };
  };
}
