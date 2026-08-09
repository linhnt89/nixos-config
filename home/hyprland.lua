-- Hyprland configuration
--
-- Managed by Home Manager from:
-- ~/nixos-config/home/hyprland.lua

----------------
-- MONITOR
----------------

-- ViewSonic VX2758-2K-PRO
hl.monitor({
  output = "HDMI-A-1",
  mode = "2560x1440@143.98",
  position = "0x0",
  scale = 1,
})

----------------
-- APPLICATIONS
----------------

local terminal = "kitty"
local launcher = "fuzzel"
local fileManager = "thunar"

local mainMod = "SUPER"

----------------
-- LOOK AND FEEL
----------------

hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 10,

    border_size = 2,

    col = {
      active_border = "rgba(5e81acff)",
      inactive_border = "rgba(3b4252cc)",
    },

    resize_on_border = true,
    allow_tearing = false,

    layout = "dwindle",
  },

  decoration = {
    rounding = 8,
    rounding_power = 2,

    active_opacity = 1.0,
    inactive_opacity = 1.0,

    shadow = {
      enabled = true,
      range = 4,
      render_power = 2,
      color = 0x66000000,
    },

    blur = {
      enabled = false,
    },
  },

  animations = {
    enabled = true,
  },

  misc = {
    disable_hyprland_logo = true,
    force_default_wallpaper = 0,

    mouse_move_enables_dpms = true,
    key_press_enables_dpms = true,
  },
})

----------------
-- ANIMATIONS
----------------

hl.curve(
  "quickEase",
  {
    type = "bezier",
    points = {
      { 0.20, 1.00 },
      { 0.30, 1.00 },
    },
  }
)

hl.animation({
  leaf = "global",
  enabled = true,
  speed = 2.0,
  bezier = "quickEase",
})

hl.animation({
  leaf = "windowsIn",
  enabled = true,
  speed = 1.6,
  bezier = "quickEase",
  style = "popin 96%",
})

hl.animation({
  leaf = "windowsOut",
  enabled = true,
  speed = 1.2,
  bezier = "quickEase",
  style = "popin 96%",
})

hl.animation({
  leaf = "workspaces",
  enabled = true,
  speed = 1.8,
  bezier = "quickEase",
  style = "fade",
})

hl.animation({
  leaf = "fade",
  enabled = true,
  speed = 1.5,
  bezier = "quickEase",
})

----------------
-- DWINDLE
----------------

hl.config({
  dwindle = {
    preserve_split = true,
  },
})

----------------
-- INPUT
----------------

hl.config({
  input = {
    kb_layout = "us",

    follow_mouse = 1,

    sensitivity = 0,
  },
})

----------------
-- CLIPBOARD
----------------

local clipboardMenu =
  [[cliphist list | fuzzel --dmenu --prompt="Clipboard > " | cliphist decode | wl-copy]]

----------------
-- SCREENSHOTS
----------------

local screenshotRegion = [[
mkdir -p "$HOME/Pictures/Screenshots";
file="$HOME/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png";
geometry="$(slurp)" || exit 0;
grim -g "$geometry" "$file" &&
wl-copy < "$file" &&
notify-send "Screenshot saved" "$file"
]]

local screenshotFull = [[
mkdir -p "$HOME/Pictures/Screenshots";
file="$HOME/Pictures/Screenshots/$(date +%Y-%m-%d_%H-%M-%S).png";
grim "$file" &&
wl-copy < "$file" &&
notify-send "Screenshot saved" "$file"
]]

----------------
-- APPLICATION BINDS
----------------

hl.bind(
  mainMod .. " + Q",
  hl.dsp.exec_cmd(terminal)
)

hl.bind(
  mainMod .. " + SPACE",
  hl.dsp.exec_cmd(launcher)
)

hl.bind(
  mainMod .. " + E",
  hl.dsp.exec_cmd(fileManager)
)

----------------
-- WINDOW BINDS
----------------

hl.bind(
  mainMod .. " + C",
  hl.dsp.window.close()
)

hl.bind(
  mainMod .. " + F",
  hl.dsp.window.fullscreen({
    mode = "fullscreen",
    action = "toggle",
  })
)

hl.bind(
  mainMod .. " + SHIFT + F",
  hl.dsp.window.float({
    action = "toggle",
  })
)

----------------
-- FOCUS
----------------

hl.bind(
  mainMod .. " + left",
  hl.dsp.focus({
    direction = "left",
  })
)

hl.bind(
  mainMod .. " + right",
  hl.dsp.focus({
    direction = "right",
  })
)

hl.bind(
  mainMod .. " + up",
  hl.dsp.focus({
    direction = "up",
  })
)

hl.bind(
  mainMod .. " + down",
  hl.dsp.focus({
    direction = "down",
  })
)

----------------
-- MOVE / SWAP WINDOWS
----------------

hl.bind(
  mainMod .. " + SHIFT + left",
  hl.dsp.window.swap({
    direction = "left",
  })
)

hl.bind(
  mainMod .. " + SHIFT + right",
  hl.dsp.window.swap({
    direction = "right",
  })
)

hl.bind(
  mainMod .. " + SHIFT + up",
  hl.dsp.window.swap({
    direction = "up",
  })
)

hl.bind(
  mainMod .. " + SHIFT + down",
  hl.dsp.window.swap({
    direction = "down",
  })
)

----------------
-- WORKSPACES
----------------

for i = 1, 10 do
  local key = i % 10

  hl.bind(
    mainMod .. " + " .. key,
    hl.dsp.focus({
      workspace = i,
    })
  )

  hl.bind(
    mainMod .. " + SHIFT + " .. key,
    hl.dsp.window.move({
      workspace = i,
    })
  )
end

hl.bind(
  mainMod .. " + mouse_down",
  hl.dsp.focus({
    workspace = "e+1",
  })
)

hl.bind(
  mainMod .. " + mouse_up",
  hl.dsp.focus({
    workspace = "e-1",
  })
)

----------------
-- SCRATCH WORKSPACE
----------------

hl.bind(
  mainMod .. " + S",
  hl.dsp.workspace.toggle_special("scratch")
)

hl.bind(
  mainMod .. " + SHIFT + S",
  hl.dsp.window.move({
    workspace = "special:scratch",
  })
)

----------------
-- MOUSE MOVE / RESIZE
----------------

hl.bind(
  mainMod .. " + mouse:272",
  hl.dsp.window.drag(),
  {
    mouse = true,
  }
)

hl.bind(
  mainMod .. " + mouse:273",
  hl.dsp.window.resize(),
  {
    mouse = true,
  }
)

----------------
-- CLIPBOARD
----------------

hl.bind(
  mainMod .. " + V",
  hl.dsp.exec_cmd(clipboardMenu)
)

----------------
-- SCREENSHOTS
----------------

hl.bind(
  "Print",
  hl.dsp.exec_cmd(screenshotRegion)
)

hl.bind(
  "SHIFT + Print",
  hl.dsp.exec_cmd(screenshotFull)
)

----------------
-- SESSION
----------------

-- Open session/power menu.
hl.bind(
  mainMod .. " + ESCAPE",
  hl.dsp.exec_cmd("power-menu")
)

-- Lock directly without opening the menu.
hl.bind(
  mainMod .. " + L",
  hl.dsp.exec_cmd("loginctl lock-session")
)

----------------
-- AUDIO KEYS
----------------

hl.bind(
  "XF86AudioRaiseVolume",
  hl.dsp.exec_cmd(
    "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
  ),
  {
    locked = true,
    repeating = true,
  }
)

hl.bind(
  "XF86AudioLowerVolume",
  hl.dsp.exec_cmd(
    "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
  ),
  {
    locked = true,
    repeating = true,
  }
)

hl.bind(
  "XF86AudioMute",
  hl.dsp.exec_cmd(
    "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
  ),
  {
    locked = true,
  }
)

hl.bind(
  "XF86AudioMicMute",
  hl.dsp.exec_cmd(
    "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
  ),
  {
    locked = true,
  }
)

----------------
-- MEDIA KEYS
----------------

hl.bind(
  "XF86AudioPlay",
  hl.dsp.exec_cmd("playerctl play-pause"),
  {
    locked = true,
  }
)

hl.bind(
  "XF86AudioPrev",
  hl.dsp.exec_cmd("playerctl previous"),
  {
    locked = true,
  }
)

hl.bind(
  "XF86AudioNext",
  hl.dsp.exec_cmd("playerctl next"),
  {
    locked = true,
  }
)

hl.bind(
  "XF86AudioStop",
  hl.dsp.exec_cmd("playerctl stop"),
  {
    locked = true,
  }
)
