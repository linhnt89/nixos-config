-- Hyprland configuration

--
-- Monitor
--

hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = "auto",
})

--
-- Applications
--

local terminal = "kitty"
local launcher = "fuzzel"
local fileManager = "thunar"

local mainMod = "SUPER"

--
-- Clipboard
--

local clipboardMenu =
  [[cliphist list | fuzzel --dmenu --prompt="Clipboard > " | cliphist decode | wl-copy]]

--
-- Screenshots
--

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

--
-- Session
--

local lockSession = "loginctl lock-session"

--
-- Application bindings
--

-- Terminal
hl.bind(
  mainMod .. " + Q",
  hl.dsp.exec_cmd(terminal)
)

-- Application launcher
hl.bind(
  mainMod .. " + SPACE",
  hl.dsp.exec_cmd(launcher)
)

-- File manager
hl.bind(
  mainMod .. " + E",
  hl.dsp.exec_cmd(fileManager)
)

--
-- Window bindings
--

-- Close focused window
hl.bind(
  mainMod .. " + C",
  hl.dsp.window.close()
)

--
-- Clipboard
--

hl.bind(
  mainMod .. " + V",
  hl.dsp.exec_cmd(clipboardMenu)
)

--
-- Screenshots
--

-- Select region
hl.bind(
  "Print",
  hl.dsp.exec_cmd(screenshotRegion)
)

-- Full desktop
hl.bind(
  "SHIFT + Print",
  hl.dsp.exec_cmd(screenshotFull)
)

--
-- Lock screen
--

hl.bind(
  mainMod .. " + L",
  hl.dsp.exec_cmd(lockSession)
)

--
-- Focus movement
--

hl.bind(
  mainMod .. " + left",
  hl.dsp.focus({ direction = "left" })
)

hl.bind(
  mainMod .. " + right",
  hl.dsp.focus({ direction = "right" })
)

hl.bind(
  mainMod .. " + up",
  hl.dsp.focus({ direction = "up" })
)

hl.bind(
  mainMod .. " + down",
  hl.dsp.focus({ direction = "down" })
)
