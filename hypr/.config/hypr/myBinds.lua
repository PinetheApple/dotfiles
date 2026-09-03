-- Keybinds.

local v = require("myVars")

local main  = v.main
local shift = v.shift
local mainShift = main .. " + " .. shift

local function exec(cmd)
    return hl.dsp.exec_cmd(cmd)
end

local screenshotMonitor =
    "grim -o \"$(hyprctl monitors -j | jq -r '.[]|select(.focused)|.name')\" "
    .. "~/Pictures/Screenshots/screenshot_$(date +%Y%m%d-%H%M%S)_monitor.png"
local screenshotRegion = "grim -g \"$(slurp)\" - | swappy -f -"

hl.bind(main .. " + T", exec(v.terminal))
hl.bind(mainShift .. " + Q", hl.dsp.window.close())
hl.bind(main .. " + F", exec(v.fileManager))
hl.bind(main .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(main .. " + R", exec(v.menu))
hl.bind("XF86Search", exec(v.menu), { ignore_mods = true })
hl.bind(main .. " + P", hl.dsp.window.pseudo()) -- dwindle
hl.bind(main .. " + C", exec(v.clipboard))
hl.bind(mainShift .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(main .. " + O", exec(v.wallpaper))

-- power related
hl.bind(mainShift .. " + Delete", exec(v.shutdown))
hl.bind("F9", exec(v.suspend))
hl.bind(mainShift .. " + S", exec(v.suspend))
hl.bind(main .. " + L", exec("loginctl lock-session"))
hl.bind(mainShift .. " + M", exec(v.powerMenu))
hl.bind(mainShift .. " + I", exec("caffeine-toggle")) -- toggle sleep inhibitor

-- session save/restore (snapshot windows -> restored on next login)
hl.bind(main .. " + CONTROL + S", exec("~/.config/hypr/session-save.sh"))
hl.bind(main .. " + CONTROL + R", exec("~/.config/hypr/session-restore.sh"))

-- app specific binds
hl.bind(main .. " + B", exec(v.browser)) -- Zen Browser

-- volume control
hl.bind("XF86AudioRaiseVolume",
    exec("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("XF86AudioLowerVolume",
    exec("wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute",
    exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

-- brightness control
hl.bind("XF86MonBrightnessDown", exec("brightnessctl s 5%-"))
hl.bind("XF86MonBrightnessUp", exec("brightnessctl s +5%"))

-- playback control
hl.bind("Home", exec("playerctl play-pause"))
hl.bind("Prior", exec("playerctl previous"))
hl.bind("Next", exec("playerctl next"))
hl.bind("XF86AudioPlay", exec("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", exec("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioStop", exec("playerctl stop"), { locked = true })
hl.bind("XF86AudioNext", exec("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", exec("playerctl previous"), { locked = true })

-- Screenshot focused monitor (direct save) / region (select + annotate in swappy)
hl.bind("PRINT", exec(screenshotMonitor))
hl.bind(shift .. " + PRINT", exec(screenshotRegion))
hl.bind("F7", exec(screenshotMonitor))
hl.bind(shift .. " + F7", exec(screenshotRegion))

-- Move focus with mainMod + arrow keys
for _, direction in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(main .. " + " .. direction, hl.dsp.focus({ direction = direction }))
end

-- Workspaces: key N maps to workspace N+1 (0 -> 1, 5 -> 6)
for key = 0, 5 do
    local workspace = key + 1
    hl.bind(main .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind(mainShift .. " + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(main .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(main .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(main .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(main .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- dictation: meeting-mode transcription of system audio (toggle)
hl.bind("ALT + SHIFT + T", exec("voxtype-meeting-toggle"))
