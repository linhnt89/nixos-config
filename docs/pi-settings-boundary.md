# Pi settings boundary (seed-once runtime files)

How Pi configuration is split between the tracked repository and the
runtime-owned home directory, and how to migrate or roll back.

## The two file classes

Pi reads its global configuration from `~/.pi/agent/` (and, for
pi-web-access, `~/.config/pi/web-search.json`). Exactly two of those
files are **written by Pi at runtime**:

| File | Written by | When |
| --- | --- | --- |
| `~/.pi/agent/settings.json` | Pi core | every `/settings` change, `/model` selection, `pi config` package change, and automatically after version updates (`lastChangelogVersion`) |
| `~/.config/pi/web-search.json` | pi-web-access | when a search/fetch provider or workflow changes |

The other three (`models.json`, `AGENTS.md`,
`openai-server-compaction.json`) are read-only at runtime.

`home/modules/pi.nix` therefore uses two mechanisms:

1. **Read-only declarative links** (out-of-store symlinks from the
   canonical checkout) for `models.json`, `AGENTS.md`, and
   `openai-server-compaction.json`.
2. **Seed-once runtime files** for `settings.json` and
   `web-search.json`: a Home Manager activation script copies the
   tracked defaults from `home/pi/` into the runtime locations **only
   when the file does not exist yet**. Afterwards Pi owns them and the
   tracked clone is never written at runtime.

The tracked `home/pi/settings.json` is deliberately minimal: essential
model and package defaults only (`defaultProvider`, `defaultModel`,
`packages`, `enabledModels`). Interactive runtime preferences (thinking
level, theme, UI toggles, steering/follow-up modes, compaction tuning,
changelog metadata) are runtime-owned.

## Re-applying tracked defaults

After deliberately changing `home/pi/settings.json` or
`home/pi/web-search.json` in the repo and rebuilding, copy them into the
runtime files:

```console
$ pi-apply-defaults          # copies tracked defaults to runtime files
$ pi-apply-defaults --dry-run
```

The command refuses to run while the destination is still a symlink
(i.e. before the seed-once module has been switched in).

## Migration (from the old out-of-store-symlink design)

The old design linked the runtime files straight into the tracked clone,
so the live values currently live in the dirty tracked file. Preserve
them before the switch:

```bash
# 1. Preserve current live values into the runtime files (safe to run
#    before or after the switch; the seed skips files that already exist).
install -D -m 600 ~/nixos-config/home/pi/settings.json ~/.pi/agent/settings.json
install -D -m 600 ~/nixos-config/home/pi/web-search.json ~/.config/pi/web-search.json

# 2. Discard the tracked drift so the pull is conflict-free.
git -C ~/nixos-config checkout -- home/pi/settings.json

# 3. Pull the change and switch.
git -C ~/nixos-config pull --ff-only
sudo nixos-rebuild switch --flake .#metacube

# 4. Verify (see below).
```

If step 1 is skipped, the activation seed still creates both files from
the tracked defaults, so nothing breaks — the captain's UI preferences
just reset to Pi defaults (they can be restored from
`~/.pi/agent/settings.json.before-luna`-style backups or re-entered).

## Verification after migration

```bash
test -f ~/.pi/agent/settings.json && test ! -L ~/.pi/agent/settings.json && echo PASS
test -f ~/.config/pi/web-search.json && test ! -L ~/.config/pi/web-search.json && echo PASS
readlink ~/.pi/web-search.json          # -> ~/.config/pi/web-search.json (fallback path)
git -C ~/nixos-config status --porcelain   # stays empty after /settings changes
```

## Rollback

```bash
git -C ~/nixos-config revert <the merge commit>
# restore the runtime values into the tracked clone (they are still in
# the runtime files from the migration):
cp ~/.pi/agent/settings.json ~/nixos-config/home/pi/settings.json
sudo nixos-rebuild switch --flake .#metacube
```

## Security note

Runtime settings may contain `trackingId` (analytics) or an `httpProxy`
with embedded credentials. Because they now live only in the
runtime-owned files (mode 0600), they can no longer leak into the
tracked clone or a future `git add -A`.
