{ config
, lib
, pkgs
, ...
}:

#
# User-scope half of the MangoWM + Noctalia desktop experiment (default
# login session while the experiment flag is on).
#
# Generates the Mango and Noctalia configurations declaratively from the
# project design tokens in home/theme.nix. This module is imported by the
# NixOS experiment module (modules/nixos/mango-experiment.nix) and is gated
# by the same single flag; it is inert when the flag is off.
#
# These files are read by the greetd default Mango session, which starts
# Mango through UWSM (`uwsm start -e -D mango mango.desktop` via
# greetd); the Hyprland session never reads them, but Hyprland remains
# installed as the explicit fallback session selectable from the login
# screen. The one exception is the blueman autostart shadow below, which the
# systemd user manager reads in both sessions (it is behaviorally neutral
# in Hyprland).
#
# Versions this configuration is generated for (pinned nixpkgs-unstable):
#   - mango 0.15.6     (config keys verified against assets/config.conf)
#   - noctalia 5.0.0-beta.7 (schema verified against example.toml)
#
# See docs/mango-noctalia-experiment.md for the runbook and rollback path.

let
  cfg = config.metacube.experiments.mangoNoctalia;

  fallbackServices = [
    "waybar"
    "swaync"
    "cliphist"
    "hyprpolkitagent"
    "hypridle"
    "hyprpaper"
  ];

  fallbackServiceCondition = pkgs.writeShellScript "metacube-hyprland-service-condition" ''
    case ":''${XDG_CURRENT_DESKTOP:-}:" in
      *:mango:*) exit 1 ;;
      *) exit 0 ;;
    esac
  '';

  # Legacy blueman tray-applet suppression -----------------------------------
  #
  # `services.blueman.enable` (modules/nixos/desktop.nix) starts the legacy
  # blueman tray applet from its XDG autostart entry, not from a systemd unit:
  # the blueman package ships no share/systemd/user unit (the NixOS module
  # only adds systemPackages/dbus/systemd.packages, the last carrying the
  # system-scope blueman-mechanism service), and NixOS aggregates its
  # etc/xdg/autostart/blueman.desktop into /etc/xdg/autostart via
  # environment.pathsToLink. Both uwsm sessions (Hyprland and Mango) run the
  # entry through systemd's built-in systemd-xdg-autostart-generator, which
  # generates the user unit app-blueman@autostart.service (wanted by
  # xdg-desktop-autostart.target, pulled in by uwsm's
  # wayland-session-xdg-autostart@.target).
  #
  # The file shadows the system entry with the same file name (the XDG
  # autostart search order puts ~/.config/autostart before /etc/xdg/autostart
  # and the generator keeps the first occurrence of a name), adding
  # `NotShowIn=mango`. systemd >= 260 converts OnlyShowIn/NotShowIn into an
  # ExecCondition= evaluated at service start, in the session environment
  # (uwsm injects EnvironmentFile=%t/uwsm/env_session.conf into
  # app-@autostart.service), so the applet is skipped exactly when
  # XDG_CURRENT_DESKTOP contains mango — the same per-session boundary as
  # fallbackServiceCondition — and still starts in Hyprland. This deliberately
  # avoids guessing any unit name in our config and does not disable the
  # general Noctalia `tray` widget: other tray applications are unaffected.
  #
  # blueman-manager (Waybar/Noctalia on-click) and BlueZ/hardware support are
  # untouched; only the duplicate tray applet is suppressed in Mango, where
  # Noctalia's built-in Bluetooth widget is the UI. With the flag off this
  # file does not exist and the system entry behaves exactly as before.

  bluemanAutostartEntry = ''
    [Desktop Entry]
    Name=Blueman Applet
    Comment=Blueman Bluetooth Manager
    Exec=blueman-applet
    Icon=blueman
    Terminal=false
    Type=Application
    NotShowIn=mango
  '';

  theme = import ../theme.nix;
  c = theme.colors;

  # Design-token helpers ------------------------------------------------------

  # "14161c" -> "#14161c" (Noctalia palette/TOML colors)
  hex = color: "#${color}";

  # "14161c" -> "0x14161cff" (Mango config colors)
  mangoHex = color: "0x${color}ff";

  # Same wallpaper as the stable Hyprland session (home/modules/services.nix).
  wallpaper = pkgs.nixos-artwork.wallpapers.nineish-dark-gray.gnomeFilePath;

  # Mango configuration (~/.config/mango/config.conf) -------------------------
  #
  # Key bindings follow the Noctalia Mango docs
  # (docs.noctalia.dev/noctalia/compositor-settings/mango/) plus the stable
  # session conventions (SUPER as mainMod, kitty terminal, XF86 media keys).

  mangoConfig = ''
    # MangoWM configuration — generated from home/theme.nix design tokens.
    # Only read by the experimental Mango session; never by Hyprland.

    # --- Display ---------------------------------------------------------
    # MetaCube's single display; mirrors home/hyprland.lua.
    monitorrule=name:^HDMI-A-1$,width:2560,height:1440,refresh:143.98,x:0,y:0,scale:1

    # --- Desktop shell ---------------------------------------------------
    # Noctalia owns bar, notifications, launcher, OSD, lock, wallpaper and
    # settings in the experiment.
    exec-once=noctalia

    # --- Blur / shadow interplay ----------------------------------------
    # Noctalia docs recommendation: Mango's scenefx layer blur does not filter
    # by surface opacity, so disable Mango layer blur/shadows and let Noctalia
    # render its own drop shadows (Noctalia-side shadows are disabled in the
    # generated config.toml per the same docs page).
    blur=1
    blur_layer=0
    blur_optimized=1
    blur_params_num_passes=2
    blur_params_radius=5
    blur_params_noise=0.02
    blur_params_brightness=0.9
    blur_params_contrast=0.9
    blur_params_saturation=1.0
    layer_animations=0
    shadows=1
    layer_shadows=0
    shadow_only_floating=0
    shadows_size=4
    shadows_blur=12
    shadows_position_x=2
    shadows_position_y=2
    shadowscolor=0x000000ff

    # --- Appearance (theme.nix tokens) -----------------------------------
    gappih=${toString theme.spacing.innerGap}
    gappiv=${toString theme.spacing.innerGap}
    gappoh=${toString theme.spacing.outerGap}
    gappov=${toString theme.spacing.outerGap}
    borderpx=2
    border_radius=${toString theme.radius.window}
    rootcolor=${mangoHex c.background}
    bordercolor=${mangoHex c.border}
    focuscolor=${mangoHex c.accent}
    dropcolor=${mangoHex c.success}
    splitcolor=${mangoHex c.accentDim}
    maximizescreencolor=${mangoHex c.success}
    urgentcolor=${mangoHex c.danger}
    scratchpadcolor=${mangoHex c.accentDim}
    globalcolor=${mangoHex c.accentDim}
    overlaycolor=${mangoHex c.warning}

    # --- Key bindings ----------------------------------------------------
    # keymode=common binds apply in every keymode (docs/bindings/keys.md).
    keymode=common
    bind=SUPER,r,reload_config
    # Media / volume / brightness (bindl = also while locked, as in Hyprland).
    # Volume and brightness go through Noctalia so it can show its OSD.
    bindl=NONE,XF86AudioRaiseVolume,spawn,noctalia msg volume-up
    bindl=NONE,XF86AudioLowerVolume,spawn,noctalia msg volume-down
    bindl=NONE,XF86AudioMute,spawn,noctalia msg volume-mute
    bindl=NONE,XF86AudioMicMute,spawn,noctalia msg mic-mute
    bindl=NONE,XF86MonBrightnessUp,spawn,noctalia msg brightness-up
    bindl=NONE,XF86MonBrightnessDown,spawn,noctalia msg brightness-down
    bindl=NONE,XF86AudioPlay,spawn,playerctl play-pause
    bindl=NONE,XF86AudioPrev,spawn,playerctl previous
    bindl=NONE,XF86AudioNext,spawn,playerctl next
    bindl=NONE,XF86AudioStop,spawn,playerctl stop

    keymode=default
    # Apps
    bind=SUPER,Return,spawn,kitty
    bind=SUPER,e,spawn,thunar
    # Noctalia shell surfaces (IPC binds from the Noctalia Mango docs)
    bind=SUPER,space,spawn,noctalia msg panel-toggle launcher
    bind=SUPER,s,spawn,noctalia msg panel-toggle control-center
    bind=SUPER,comma,spawn,noctalia msg settings-toggle
    bind=SUPER,v,spawn,noctalia msg panel-toggle clipboard
    bind=SUPER+SHIFT,s,spawn,noctalia msg screenshot-region
    bind=SUPER,Escape,spawn,noctalia msg panel-toggle session
    bind=SUPER,l,spawn,noctalia msg session lock
    # Windows
    bind=SUPER,q,killclient,
    bind=SUPER,m,quit
    bind=SUPER,Tab,focusstack,next
    bind=SUPER,Left,focusdir,left
    bind=SUPER,Right,focusdir,right
    bind=SUPER,Up,focusdir,up
    bind=SUPER,Down,focusdir,down
    bind=SUPER+SHIFT,Left,exchange_client,left
    bind=SUPER+SHIFT,Right,exchange_client,right
    bind=SUPER+SHIFT,Up,exchange_client,up
    bind=SUPER+SHIFT,Down,exchange_client,down
    bind=SUPER+SHIFT,f,togglefullscreen,
    bind=SUPER+SHIFT,space,togglefloating,
    bind=SUPER,i,minimized,
    bind=SUPER+SHIFT,i,restore_minimized,1
    # Tags (the Mango counterpart of Hyprland workspaces)
    bind=SUPER,1,view,1,0
    bind=SUPER,2,view,2,0
    bind=SUPER,3,view,3,0
    bind=SUPER,4,view,4,0
    bind=SUPER,5,view,5,0
    bind=SUPER,6,view,6,0
    bind=SUPER,7,view,7,0
    bind=SUPER,8,view,8,0
    bind=SUPER,9,view,9,0
    bind=SUPER+SHIFT,1,tag,1,0
    bind=SUPER+SHIFT,2,tag,2,0
    bind=SUPER+SHIFT,3,tag,3,0
    bind=SUPER+SHIFT,4,tag,4,0
    bind=SUPER+SHIFT,5,tag,5,0
    bind=SUPER+SHIFT,6,tag,6,0
    bind=SUPER+SHIFT,7,tag,7,0
    bind=SUPER+SHIFT,8,tag,8,0
    bind=SUPER+SHIFT,9,tag,9,0

    # Keymode-aware binds: SUPER+f enters a resize mode; arrows resize the
    # focused window, Escape returns to the default mode.
    bind=SUPER,f,setkeymode,resize
    keymode=resize
    bind=NONE,Left,resizewin,-10,0
    bind=NONE,Right,resizewin,+10,0
    bind=NONE,Up,resizewin,0,-10
    bind=NONE,Down,resizewin,0,+10
    bind=NONE,Escape,setkeymode,default
  '';

  # Noctalia configuration (~/.config/noctalia/config.toml) -------------------
  #
  # Palette roles are defined in the generated custom palette
  # (palettes/MetaCube.json); the shell config references the theme tokens
  # directly where the schema takes plain values.

  noctaliaConfig = ''
    # Noctalia configuration — generated from home/theme.nix design tokens.
    # Only used by the experimental Mango session.
    # GUI overrides land in ~/.local/state/noctalia/settings.toml and are
    # intentionally not committed (see docs/mango-noctalia-experiment.md).

    [theme]
    mode = "dark"
    source = "custom"
    custom_palette = "MetaCube"

    [shell]
    font_family = "${theme.fonts.sans}"
    polkit_agent = true

    # Noctalia docs recommendation (compositor-settings/mango): with Mango
    # layer blur/shadows off, also disable Noctalia's rendered surface shadows.
    [bar.default]
    position = "top"
    thickness = 34
    background_opacity = 1.0
    radius = ${toString theme.radius.panel}
    margin_ends = 180
    margin_edge = 10
    padding = ${toString theme.spacing.panelPadding}
    widget_spacing = 6
    scale = 1.0
    shadow = false
    contact_shadow = false
    start = ["launcher", "wallpaper", "workspaces"]
    center = ["clock"]
    end = ["media", "tray", "notifications", "clipboard", "network", "bluetooth", "volume", "brightness", "battery", "control-center", "session"]

    [shell.panel]
    shadow = false

    [dock]
    enabled = false
    shadow = false

    # Same wallpaper as the stable Hyprland session.
    [wallpaper]
    fill_color = "surface"

    [wallpaper.default]
    path = "${wallpaper}"

    # Idle lock at 600 s, mirroring the stable hypridle listener.
    [idle.behavior.lock]
    timeout = 600
    action = "lock"
    enabled = true
  '';

  # Noctalia custom palette (~/.config/noctalia/palettes/MetaCube.json) -------
  #
  # Role mapping from theme.nix tokens. The 16 roles follow the documented
  # palette format; both m-prefixed and unprefixed role keys are accepted by
  # beta.7 (we emit the documented m-prefixed form). Terminal ANSI colors are
  # derived deterministically from the 13-token palette — see the comment in
  # the terminal block.

  noctaliaPalette = {
    dark = {
      mPrimary = hex c.accent; # accent for buttons/links/active
      mOnPrimary = hex c.background;
      mSecondary = hex c.accentDim;
      mOnSecondary = hex c.background;
      mTertiary = hex c.success;
      mOnTertiary = hex c.background;
      mError = hex c.danger;
      mOnError = hex c.background;
      mSurface = hex c.background; # main shell background
      mOnSurface = hex c.text;
      mSurfaceVariant = hex c.surface; # cards / panels
      mOnSurfaceVariant = hex c.textMuted;
      mOutline = hex c.border;
      mShadow = hex c.background;
      mHover = hex c.surfaceHover;
      mOnHover = hex c.text;

      terminal = {
        background = hex c.background;
        foreground = hex c.text;
        cursor = hex c.accent;
        cursorText = hex c.background;
        selectionBg = hex c.accentDim;
        selectionFg = hex c.text;
        # Derived from the 13-token palette: the palette has no dedicated
        # magenta/cyan, so magenta maps to the dim accent and cyan to success;
        # bright variants shift one step (bright.black = border, bright.white =
        # textMuted) so dimmed text still reads in terminals.
        normal = {
          black = hex c.background;
          red = hex c.danger;
          green = hex c.success;
          yellow = hex c.warning;
          blue = hex c.accent;
          magenta = hex c.accentDim;
          cyan = hex c.success;
          white = hex c.text;
        };
        bright = {
          black = hex c.border;
          red = hex c.danger;
          green = hex c.success;
          yellow = hex c.warning;
          blue = hex c.accent;
          magenta = hex c.accent;
          cyan = hex c.accentDim;
          white = hex c.textMuted;
        };
      };
    };
  };

  noctaliaPaletteJson = builtins.toJSON noctaliaPalette;
in
{
  options.metacube.experiments.mangoNoctalia = {
    # Mirror of the NixOS-side flag (modules/nixos/mango-experiment.nix);
    # the NixOS module bridges its own flag into this one so a single flip
    # controls both scopes.
    enable = lib.mkEnableOption "the bounded MangoWM + Noctalia desktop experiment";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services = lib.genAttrs fallbackServices (_: {
      Service.ExecCondition = fallbackServiceCondition;
    });

    xdg.configFile."mango/config.conf".text = mangoConfig;

    xdg.configFile."noctalia/config.toml".text = noctaliaConfig;

    xdg.configFile."noctalia/palettes/MetaCube.json".text = noctaliaPaletteJson;

    # Shadow the system XDG autostart entry so the legacy blueman tray applet
    # is skipped in Mango only (see the lifecycle note above).
    xdg.configFile."autostart/blueman.desktop".text = bluemanAutostartEntry;
  };
}
