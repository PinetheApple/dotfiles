-- For full list, see wiki - https://wiki.hypr.land/

local colors = require("myColors")

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({ output = "eDP-2", mode = "preferred", position = "0x0", scale = 1 })
hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "1920x0", scale = 1 })

-- workspace configuration
local workspaces = {
    { id = "1", monitor = "eDP-2",    default = false },
    { id = "2", monitor = "eDP-2",    default = true },
    { id = "3", monitor = "eDP-2",    default = true },
    { id = "4", monitor = "HDMI-A-1", default = true },
    { id = "5", monitor = "HDMI-A-1", default = true },
    { id = "6", monitor = "HDMI-A-1", default = true },
}

for _, ws in ipairs(workspaces) do
    hl.workspace_rule({ workspace = ws.id, monitor = ws.monitor, default = ws.default })
end

-- Execute favorite apps launch
hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/hyprpaper.sh")
    hl.exec_cmd("wayle panel start")
    hl.exec_cmd("~/scripts/notify-follow-monitor.sh") -- notifications follow focused monitor
    hl.exec_cmd("~/.config/hypr/hyprpaper.py")
    hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("hypridle")

    hl.exec_cmd("~/scripts/makima-start.sh")
    hl.exec_cmd("systemctl --user start voxtype.service")

    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

    hl.exec_cmd("~/.config/hypr/session-restore.sh")
end)

-- hyprlang `exec` ran on start and on every reload; mirror both events.
local function applyGtkTheme()
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'GnomeBlueDark'")   -- GTK3 apps
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")  -- GTK4 apps
end

hl.on("hyprland.start", applyGtkTheme)
hl.on("config.reloaded", applyGtkTheme)

-- Some default env vars.
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct") -- change to qt5ct if you have that for Qt apps
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("XDG_CONFIG_DIRS", "/etc/xdg")

-- For all categories, see https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 to 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },

    general = {
        gaps_in     = 3,
        gaps_out    = 5,
        border_size = 2,

        col = {
            active_border   = { colors = { colors.color1, colors.color2 }, angle = 45 },
            inactive_border = colors.color0,
        },

        layout = "dwindle",

        -- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before turning on
        allow_tearing = false,
    },

    decoration = {
        rounding = 10,

        blur = {
            enabled = true,
            size    = 3,
            passes  = 2,
        },

        active_opacity     = 0.97,
        inactive_opacity   = 0.9,
        fullscreen_opacity = 1.0,

        dim_inactive = true,
        dim_strength = 0.4,
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true, -- you probably want this
    },

    misc = {
        disable_hyprland_logo   = true,
        force_default_wallpaper = 0, -- Set to 0 or 1 to disable the anime mascot wallpapers
    },
})

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

hl.animation({ leaf = "windows",     enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",      enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8,  bezier = "default" })
hl.animation({ leaf = "fade",        enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 6,  bezier = "default" })

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
hl.window_rule({
    -- Ignore maximize requests from all apps.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- disables border for windows in fullscreen
    name  = "no-border-fullscreen",
    match = { fullscreen = true },

    border_size = 0,
})

hl.window_rule({
    -- voxtype's Quickshell panels (live transcript, transcript review)
    -- are real toplevels so they can be moved; keep them out of the tile.
    name  = "float-voxtype-panels",
    match = { class = "org.quickshell" },

    float = true,
    border_size = 0,
})

require("myBinds")
