# Moshi (Android) → MetaCube with Herdr sessions

Goal: connect the [Moshi](https://getmoshi.app) Android app
(Google Play, Android 10 or newer) to this host and attach to
[Herdr](https://herdr.dev) sessions.

Moshi is a mobile terminal. It does not run anything in a cloud;
your shell, repos, Herdr sessions, and agent CLIs stay on this
machine. Moshi is a window into them.

## What this repository configures declaratively

| Prerequisite | Where | Status |
| --- | --- | --- |
| SSH server (sshd) with key-only auth | `modules/nixos/ssh.nix` | declarative |
| `mosh` (provides `mosh-server`) | `home/modules/moshi.nix` | declarative |
| `tmux` (durable workspaces fallback) | `home/modules/moshi.nix` | declarative |
| `herdr` (agent multiplexer, v0.8.0) | `home/modules/herdr.nix` via flake input | declarative |
| Herdr/mosh/tmux on the non-interactive SSH PATH | NixOS `programs.zsh.enable` generates `/etc/zshenv`, which sources the system `set-environment` for every zsh invocation — so `/etc/profiles/per-user/linhnt/bin` is visible even to `ssh host 'command -v herdr'` | declarative (existing config, verified) |
| Host firewall | NixOS default firewall is active. Enabling sshd automatically opens TCP 22 on **all interfaces** (`networking.firewall.allowedTCPPorts = [22]`); the mosh UDP range 60000-61000 stays closed | **decision needed** (below) |

Nothing here stores phone keys, pairing tokens, or any other
secret — those are runtime state and stay out of Git.

## Open network decision (captain)

Enabling `modules/nixos/ssh.nix` makes NixOS automatically open
TCP 22 on all interfaces (`networking.firewall.allowedTCPPorts =
[22]` — verified by evaluating the built configuration). The mosh
UDP range 60000-61000 is not opened anywhere. Choosing the
exposure policy is a captain decision, because it changes the
firewall shape:

1. **LAN only** — phone on the same Wi-Fi. Accept the automatic
   TCP 22 rule (all interfaces) and add the mosh UDP range:
   ```nix
   networking.firewall.allowedUDPPortRanges = [
     { from = 60000; to = 61000; }
   ];
   ```
   Convenient at home; exposes key-only sshd to the whole LAN.

2. **Tailscale / VPN** — keep the firewall closed to everything
   else and allow SSH/mosh only on the tailnet interface:
   ```nix
   networking.firewall.allowedTCPPorts = lib.mkForce [];
   networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
   networking.firewall.interfaces.tailscale0.allowedUDPPortRanges = [
     { from = 60000; to = 61000; }
   ];
   ```
   Phone connects to the Tailscale IP even from cellular.

3. **Public exposure** — not recommended and explicitly out of
   scope. Moshi's own docs assume a private path (LAN or
   Tailscale); this machine should never be reachable from the
   public internet.

Until the decision lands, do **not switch** this generation: the
currently booted generation has no sshd and no open ports.
Whatever the choice, SSH authentication stays locked down (keys
only, no passwords, no root), so the decision is purely about the
firewall shape.

## Manual steps

These are deliberately not declarative: they involve phone-side
interaction, one-time pairing, and secrets that must not live in
this repository.

### 1. Install Moshi on the phone

Install Moshi from Google Play (Android 10 or newer).

### 2. Host reachability

Pick the network path from the decision above and make sure the
phone can reach the host on it (LAN IP, Tailscale name, etc.).
If SSH is not reachable from the phone, nothing else works.

### 3. Easy Pair (recommended) or manual key

Easy Pair uses the temporary `moshi-hook` installer, which is
**not packaged in this repository** — Moshi's curl installer is
the supported path and it is not a pinned Nix input:

```bash
curl -fsSL https://getmoshi.app/install.sh | sh
moshi-hook host setup        # prints an Easy Pair QR
```

In Moshi onboarding tap **Easy Pair** and scan the QR. Moshi
generates an Ed25519 key on the phone, sends only the public key
over the setup session, and the host installs it in
`~/.ssh/authorized_keys`.

> Treat the Easy Pair QR like a temporary access token: anyone
> who scans it before it expires can claim SSH access to this
> host. The token from `moshi-hook pair` (step 5) is a secret —
> never commit it.

Manual fallback (**New Connection** in Moshi): host = reachable
IP/name, port = 22, user = `linhnt`, authentication = key file.
Let Moshi generate an Ed25519 key, then paste the public key into
`~/.ssh/authorized_keys` on the host (or `ssh-copy-id`).
Passwords are not possible here: sshd rejects them by design.

### 4. Start / attach Herdr sessions

On the host (or over SSH from the phone):

```bash
herdr                        # start the default session and attach
herdr session attach work    # named project session
herdr session list           # running sessions
```

Moshi detects Herdr on connect and shows running sessions in the
session picker under a **Herdr** tab; tapping one attaches.
Sessions whose server is not running are hidden — start one with
`herdr` and reconnect. Anything long-running (agents, builds,
dev servers) belongs inside a Herdr session so a phone network
drop does not kill it.

In-session controls: default prefix `Ctrl-B` (matches Moshi's
Herdr shortcut panel) — `Ctrl-B c` new tab, `Ctrl-B n`/`p` next/
previous tab, `Ctrl-B w` workspace navigation, `Ctrl-B z` zoom
pane. Gestures: swipe = tab, two-finger swipe = pane, two-finger
vertical swipe = workspace, pinch = zoom.

`tmux` is installed as a fallback (`tmux new -A -s work`) and is
detected the same way if you ever prefer it.

### 5. Optional: Moshi agent hooks (`moshi-hook` daemon)

For inbox cards and push events when an agent needs you:

```bash
moshi-hook pair --token <token from the Moshi app>
moshi-hook install   # writes hook entries into agent config files
moshi-hook serve     # long-running daemon; local gateway on 127.0.0.1:24543
```

Keep `moshi-hook serve` alive with a process manager. A systemd
user unit works well on NixOS — create
`~/.config/systemd/user/moshi-hook.service` (outside this repo):

```ini
[Unit]
Description=Moshi hook daemon
After=network-online.target

[Service]
ExecStart=%h/.local/bin/moshi-hook serve
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now moshi-hook.service
moshi-hook status
```

## Verification and troubleshooting

Check what Moshi's non-interactive SSH session sees:

```bash
ssh metacube 'echo $PATH; command -v herdr; command -v tmux; command -v mosh-server'
```

All three should print paths under `/etc/profiles/per-user/linhnt/bin`.
If `command -v herdr` prints nothing, the PATH note in
`home/modules/herdr.nix` explains why it should not.

- **Moshi doesn't detect Herdr** — most common cause is the
  non-interactive PATH, which is already handled here (zsh +
  `/etc/zshenv`). Verify with the command above.
- **`moshi-hook status` reports `herdr: not found`** — the
  daemon does not inherit shell startup files. It searches
  standard Nix profiles, which should cover this install; if it
  still misses, override with
  `systemctl --user edit moshi-hook.service`:

  ```ini
  [Service]
  Environment="MOSHI_HERDR_PATH=$(command -v herdr)"
  ```

  then `systemctl --user daemon-reload` and restart the service.
- **Session list is empty but Herdr is installed** — no Herdr
  server is running; start one with `herdr` or
  `herdr session attach <name>` and reconnect.
- **Mosh cannot connect** — mosh bootstraps over SSH then
  switches to UDP 60000-61000. If SSH works but mosh does not,
  the UDP range is the pending firewall decision; use connection
  type **SSH** as a fallback in the meantime.

Sources: Moshi docs — [Install and prepare a host](https://getmoshi.app/docs/install),
[Herdr](https://getmoshi.app/docs/herdr),
[Hooks](https://getmoshi.app/docs/hooks),
[Troubleshooting](https://getmoshi.app/docs/troubleshooting).
