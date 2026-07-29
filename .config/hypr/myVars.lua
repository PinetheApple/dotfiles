-- Apps and system commands. Ported from myVars.conf.

local rofiConfig = "~/.config/rofi/clipboard.rasi"

return {
    terminal    = "kitty",
    fileManager = "thunar",
    menu        = "rofi -show drun",
    browser     = "flatpak run io.github.zen_browser.zen",
    clipboard   = "cliphist list | rofi -dmenu -display-columns 2 -config "
        .. rofiConfig .. " | cliphist decode | wl-copy",
    wallpaper   = "~/.config/hypr/hyprpaper.py",

    suspend   = "playerctl pause; bluetoothctl disconnect; loginctl lock-session; systemctl suspend",
    shutdown  = "~/.config/hypr/power-confirm.sh poweroff",
    powerMenu = "wleave",

    main  = "SUPER",
    shift = "SHIFT",
}
