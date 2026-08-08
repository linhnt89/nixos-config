-- Initial Hyprland configuration.
-- We will build this gradually after the first successful boot.

hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = "auto",
})

local terminal = "kitty"
local mainMod = "SUPER"
local launcher = "fuzzel"
local clipboardMenu =
  [[cliphist list | fuzzel --dmenu --prompt="Clipboard > " | cliphist decode | wl-copy]]
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

-- Open terminal.
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))

-- Close focused window.
hl.bind(mainMod .. " + C", hl.dsp.window.close())

-- Basic focus movement.
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Open launcher
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(launcher))

-- Open clipboard menu
hl.bind(
  mainMod .. " + V",
  hl.dsp.exec_cmd(clipboardMenu)
)

-- Screnshot
hl.bind(
  "Print",
  hl.dsp.exec_cmd(screenshotRegion)
)

hl.bind(
  "SHIFT + Print",
  hl.dsp.exec_cmd(screenshotFull)
)
