# MetaCube (RDP client) → Windows 11 Pro laptop over the LAN

Goal: from the MetaCube NixOS desktop (Hyprland), open the Windows 11
Pro laptop's desktop with the built-in Windows Remote Desktop (RDP),
scoped to the trusted LAN. This is the first implemented step of the
LAN remote-use plan from the completed scout report
(`nixos-lan-laptop-remote-use-scout`, 2026-08-17): full graphical
control of a Windows Pro-class laptop over RDP with Remmina as the
client.

This PC is the **RDP client only**. It runs no remote-access server,
opens no inbound firewall port, and exposes nothing to the WAN or
Tailscale for this purpose.

## Client/server placement and why Remmina

| Side | Machine | Role |
| --- | --- | --- |
| Client | MetaCube (this NixOS PC) | Remmina connects **outbound** to the laptop's RDP server |
| Server | Windows 11 Pro laptop | Built-in Remote Desktop host (TCP 3389), enabled on Windows |

Why Remmina:

- RDP is the native protocol for Windows Pro/Enterprise/Education
  hosts — no third-party server software on the laptop (Microsoft
  docs, see [Sources](#sources)).
- Remmina is the standard open-source GTK remote-desktop client
  (GPL-2.0+), packaged in nixpkgs, and runs as a normal desktop app
  on the Wayland/Hyprland session. Its RDP engine is FreeRDP, which
  arrives automatically as remmina's own dependency — nothing extra
  is added to the profile.
- The NixOS firewall filters **incoming** connections only; outbound
  client traffic (RDP to the laptop) needs no firewall rule and no
  change to `modules/nixos/ssh.nix` or any NixOS module.
- The scout report's decision matrix rated RDP best-in-class for LAN
  latency with clipboard, drive/folder redirection and audio support,
  and unattended access to the Windows session (it works against the
  locked desktop / login screen).

## What this repository configures declaratively

| Prerequisite | Where | Status |
| --- | --- | --- |
| Remmina RDP client package | `home/modules/apps.nix` (`home.packages`, `pkgs.remmina`) | declarative |
| RDP server, firewall rule, address, credentials | **not in this repository** — Windows-side state and runtime profile state | deliberately out of Git |

Nothing here stores the laptop's address, username, password, or any
other secret — the connection profile is created at runtime in
Remmina's per-user config directory and stays out of Git.

## Prerequisites (captain to confirm on the laptop)

1. **Windows 11 Pro** (or Enterprise/Education). Home editions cannot
   host Remote Desktop — they are client-only.
2. **Remote Desktop enabled**: Settings → System → Remote Desktop →
   On. Enabling it adds the Windows Firewall allow rule for RDP.
3. **Reachable LAN hostname or IP**: the laptop must be on the same
   trusted LAN (`192.168.1.0/24` per the existing SSH policy in
   `modules/nixos/ssh.nix`). No WAN address, no port forwarding, no
   VPN/Tailscale involvement — RDP stays on the LAN.
4. **A permitted Windows account**: the signing-in user must be a
   member of the Remote Desktop Users group on the laptop (an admin
   account works; a standard account needs adding under
   Settings → System → Remote Desktop → "Select users that can
   remotely access this PC").
5. **No WAN/public exposure**: Remote Desktop is only useful while
   the laptop is on the trusted LAN. Microsoft explicitly recommends
   enabling it only on trusted networks; this plan never enables
   outside-network access (that would require port forwarding or a
   VPN, which are out of scope).

## Launching Remmina and creating a profile (no secrets committed)

1. Start Remmina from the application menu (installed via Home
   Manager as `remmina`; launcher entry "Remmina").
2. **New connection** (the `+` button) → protocol **RDP — Remote
   Desktop Protocol**.
3. Fill in:
   - **Server**: the laptop's LAN hostname or IP (e.g. `192.168.1.x`
     or a mDNS/NetBIOS name resolvable on the LAN). This is runtime
     profile data — never commit it to the repository.
   - **Username**: optionally the Windows account name.
   - **Password**: leave **empty**. Remmina prompts for the password
     at connect time, so no credential is stored on disk.
4. Save the profile under a descriptive name. Profiles live in
   `~/.local/share/remmina/` — a runtime-owned directory, not part of
   this repository.
5. Connect. You are authenticating to the **Windows** host: use the
   Windows account credentials, which are provided at the prompt and
   never stored here.

The PC-side configuration is complete at this point: outbound RDP
needs no firewall change, no service, and no NixOS module.

## NLA/TLS and Windows Firewall expectations

- Windows Remote Desktop uses **Network Level Authentication (NLA)**
  (CredSSP): the user authenticates before the remote session is
  established, and the session is protected by TLS. Keep NLA
  **enabled** on the laptop (it is the default). Microsoft documents
  NLA as an extra security layer; the [MS-RDPBCGR] protocol spec
  defines it as authentication at the network layer before the RDP
  handshake.
- Enabling Remote Desktop on Windows automatically adds the firewall
  rule that permits RDP; the laptop's Windows Firewall remains the
  laptop owner's responsibility. The NixOS PC opens **nothing**
  inbound.
- Microsoft's guidance applies on the Windows side: only enable
  Remote Desktop on trusted networks, ensure remote accounts have
  strong passwords, and **disable Remote Desktop when it is no longer
  needed**. Restricting RDP to the trusted LAN and turning it off
  when unused is the Windows side's job — this repository cannot and
  does not enforce it.

## Windows desktop vs WSL2

RDP connects to the **Windows desktop session** of the laptop —
the same screen a user sees logged in at the laptop (including
apps, files, and network resources on Windows).

The laptop also runs Arch Linux under **WSL2**. WSL2 is a VM *inside*
Windows: it has no independent graphical session of its own, and RDP
does not reach "into" WSL2. What you see over RDP is Windows; WSL2
terminal/GUI content appears only as Windows-hosted windows (e.g.
via Windows Terminal or WSLg on the Windows desktop).

Reaching WSL2 itself — an interactive shell or files *inside* the
Arch environment — is a **separate follow-up** (for example SSH into
WSL2, or Windows-side WSLg configuration), not part of this step.
This repository configures none of: WSL2, Windows settings, SSH into
the laptop, credentials, or a fixed laptop address.

## Safe manual validation checklist

A worker cannot test the captain's laptop; this checklist is for a
manual session by the captain. Each step is safe and reversible:

1. On the laptop: confirm Settings → System → Remote Desktop is On,
   the account is permitted, and the laptop is on the trusted LAN.
2. On the PC, reachability probe (ICMP only — no port scans without
   the laptop owner's consent):

   ```console
   ping -c1 <laptop-hostname-or-ip>
   ```

3. Launch Remmina, create the RDP profile per above (password left
   empty), and connect to the laptop's LAN address.
4. Expect an NLA authentication prompt; sign in with the permitted
   Windows account.
5. Confirm you see the **Windows** desktop (not a WSL terminal) and
   that keyboard/mouse/clipboard behave as expected.
6. Disconnect, and on the laptop toggle Remote Desktop **Off** when
   the session is done.

## Rollback

- **Remove the package**: delete the `pkgs.remmina` entry from
  `home/modules/apps.nix` and rebuild — the application disappears
  from the user profile. No system service or firewall rule is
  involved, so there is nothing else to undo on the PC.
- **Remove runtime profiles**: delete `~/.local/share/remmina/` (or
  the individual profile) — no repository change needed.
- **On the laptop**: Settings → System → Remote Desktop → Off. This
  closes the RDP listener and the firewall allowance.
- Nothing in this plan ever opened a port on the PC, touched WSL2,
  or stored a laptop address or credential in the repository, so
  rollback is complete with the two steps above.

## Sources

- Microsoft Learn — "Enable Remote Desktop on your PC":
  https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-allow-access
  (enable steps, trusted-network guidance, NLA recommendation,
  firewall rule added by enabling)
- Microsoft Learn — "Remote Desktop client - supported configuration":
  https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remotepc/remote-desktop-supported-config
  (host editions: Windows 11/10 Pro and Enterprise; Home cannot host)
- Microsoft Learn — "Ports That Are Used by RDS":
  https://learn.microsoft.com/en-us/troubleshoot/windows-server/remote/ports-used-by-rds
  (standard RDP port TCP 3389)
- Microsoft Open Specifications — [MS-RDPBCGR] glossary (NLA /
  CredSSP definition):
  https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rdpbcgr/ab35aee7-1cf7-42dc-ac74-d0d7f4ca64f7
- Remmina — features (RDP/VNC/SSH protocols, profile management):
  https://remmina.org/remmina-features/
- Remmina — project site:
  https://remmina.org/
- Scout report (2026-08-17) — LAN remote-use decision matrix and
  staged path recommending RDP/Remmina for a Windows Pro laptop:
  `nixos-lan-laptop-remote-use-scout` (firstmate data directory)
