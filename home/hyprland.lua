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
