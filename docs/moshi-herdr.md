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
| Host firewall | TCP 22 + mosh UDP 60000-61000 allowed **only** from the trusted LAN IPv4 range (`192.168.1.0/24`) on `eno1`, plus all tailnet peers on `tailscale0` (the LAN source restriction applies only to `eno1`); sshd's automatic all-interface open is disabled; Tailscale UDP 41641 is opened separately for `tailscaled`; SSH/mosh stay closed on WAN/public and unused interfaces | declarative |
| Tailscale client | `services.tailscale.enable` (daemon); `tailscale up` login is manual — no auth keys in the repo | daemon declarative, auth manual |
| Tailscale netfilter mode | `services.tailscale.extraSetFlags` | persistently `off`, so the host firewall remains authoritative |
| Tailscale transport | `services.tailscale.openFirewall` | UDP 41641 is open for direct authenticated peer handshakes and is handled by `tailscaled`, not SSH or mosh |

Nothing here stores phone keys, pairing tokens, or any other
secret — those are runtime state and stay out of Git.

## Network access policy (implemented)

Captain decision: trusted local-LAN **and** external Tailscale
access, with SSH and mosh not opened on WAN/public interfaces.
Tailscale's own UDP transport port (41641) is the deliberate
exception, opened for direct authenticated peer handshakes.

TCP 22 and mosh UDP 60000-61000 are allowed **only** from:

- `192.168.1.0/24` on `eno1` — the trusted wired LAN
  (currently connected home network), and
- `tailscale0` — the Tailscale tailnet interface, reachable from
  anywhere the device is logged in (cellular included).

`eno1` also carries a globally routable IPv6 prefix, but the LAN
exception is IPv4-only, so those public IPv6 addresses do not
receive SSH or mosh port exceptions. The SSH/mosh exceptions do not apply to the spare wired port
(`enp5s0`), Wi-Fi (`wlp4s0`), or any WAN/public interface. UDP
41641 is separately open for Tailscale transport; it is handled by
`tailscaled`, not an SSH or mosh listener. sshd's implicit "open 22
everywhere" firewall rule is disabled
(`services.openssh.openFirewall = false`); the Tailscale SSH/mosh
rules are interface-scoped and the LAN source rules are in
`networking.firewall.extraCommands` in `modules/nixos/ssh.nix`.
Tailscale's netfilter mode is persistently set to `off` through
`services.tailscale.extraSetFlags`, so its packet hooks do not
bypass these interface-scoped rules.

Keeping the boundary honest:

- The LAN source scope is the current `192.168.1.0/24` subnet. If
  the trusted router changes subnets, update the source rules in
  `modules/nixos/ssh.nix` before using the LAN path.
- If `eno1` ever joins an untrusted network (travel, a public
  LAN), remove its source rules and use the Tailscale path instead.
- To also serve SSH over the spare wired port or home Wi-Fi, add
  source-scoped rules for `enp5s0` / `wlp4s0` only once that
  interface is on the trusted LAN.

SSH authentication is key-only everywhere (no passwords, no
root), so the firewall boundary is the only access control on top
of the keys.

## Manual steps

These are deliberately not declarative: they involve phone-side
interaction, one-time pairing, and secrets that must not live in
this repository.

### 1. Install Moshi on the phone

Install Moshi from Google Play (Android 10 or newer).

### 2. Host reachability

Two supported paths; pick whichever fits where the phone is.

**Path A — LAN** (phone on the same home network): the host is
reachable on `eno1`'s IPv4 address in `192.168.1.0/24`:

```bash
ip -4 -o addr show eno1
```

**Path B — Tailscale** (cellular, travel, anywhere): use the
same tailnet on MetaCube and the Android phone.

On MetaCube, log in once interactively and keep the netfilter
setting explicit:

```bash
sudo tailscale up --netfilter-mode=off  # browser login; never commit auth keys
tailscale ip -4                         # or use the MagicDNS name
```

On Android, install **Tailscale** from Google Play, sign in to
the same tailnet as MetaCube, approve the device if requested,
and tap **Connect** to allow its VPN connection. Keep Tailscale
connected while using Moshi over cellular or another network.

In Moshi, use the MetaCube Tailscale IP or MagicDNS name as the
host. If SSH is not reachable from the phone, nothing else works.

### 3. Easy Pair (recommended) or manual key

Easy Pair uses the temporary `moshi-hook` installer, which is
**not packaged in this repository** — Moshi's curl installer is
the supported path and it is not a pinned Nix input:

```bash
curl -fsSL https://getmoshi.app/install.sh | sh
/home/linhnt/.local/bin/moshi-hook host setup  # prints an Easy Pair QR
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
`~/.ssh/authorized_keys` on the host. If an already-authorized
SSH key or local console is available, `ssh-copy-id` can install
the new key; it cannot bootstrap the first connection because
password and keyboard-interactive authentication are disabled.
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

The installer places `moshi-hook` at
`/home/linhnt/.local/bin/moshi-hook`. That directory is not added
by this configuration, so use the absolute path below:

For inbox cards and push events when an agent needs you:

```bash
/home/linhnt/.local/bin/moshi-hook pair --token <token from the Moshi app>
/home/linhnt/.local/bin/moshi-hook install   # writes hook entries into agent config files
/home/linhnt/.local/bin/moshi-hook serve     # long-running daemon; local gateway on 127.0.0.1:24543
```

Keep `moshi-hook serve` alive with a process manager. A systemd
user unit works well on NixOS — create
`~/.config/systemd/user/moshi-hook.service` (outside this repo):

```ini
[Unit]
Description=Moshi hook daemon
After=network-online.target

[Service]
ExecStart=/home/linhnt/.local/bin/moshi-hook serve
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now moshi-hook.service
/home/linhnt/.local/bin/moshi-hook status
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
- **`/home/linhnt/.local/bin/moshi-hook status` reports `herdr: not found`** — the
  daemon does not inherit shell startup files. It searches
  standard Nix profiles, which should cover this install; if it
  still misses, first find the executable:

  ```bash
  command -v herdr
  ```

  On this configuration it prints
  `/etc/profiles/per-user/linhnt/bin/herdr`. Use that absolute
  path in the override; systemd does not perform shell command
  substitution:

  ```ini
  [Service]
  Environment="MOSHI_HERDR_PATH=/etc/profiles/per-user/linhnt/bin/herdr"
  ```

  then `systemctl --user daemon-reload` and restart the service.
- **Session list is empty but Herdr is installed** — no Herdr
  server is running; start one with `herdr` or
  `herdr session attach <name>` and reconnect.
- **Mosh cannot connect** — mosh bootstraps over SSH then
  switches to UDP 60000-61000. If SSH works but mosh does not,
  confirm the phone is on one of the allowed paths (home LAN via
  `eno1`, or Tailscale via `tailscale0`) — the UDP range is
  deliberately not open on other interfaces. Over cellular, use
  the Tailscale path; over an untrusted LAN, connect the phone to
  the same tailnet and use Tailscale instead of that LAN directly.
  Use connection type **SSH** as a fallback only on the trusted
  LAN or through Tailscale, where TCP 22 is reachable.

Sources: Moshi docs — [Install and prepare a host](https://getmoshi.app/docs/install),
[Herdr](https://getmoshi.app/docs/herdr),
[Hooks](https://getmoshi.app/docs/hooks),
[Troubleshooting](https://getmoshi.app/docs/troubleshooting).
