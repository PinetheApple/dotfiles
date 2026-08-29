-- Reads the wallust-generated palette. wallust still emits hyprlang
-- (`$color0 = rgb(...)`), so parse it rather than adding a second template.

local PALETTE_PATH = os.getenv("HOME") .. "/.cache/wallust/colors-hyprland.conf"

local FALLBACK = {
    background = "rgb(000206)",
    foreground = "rgb(D0E9E6)",
    color0 = "rgb(000206)",
    color1 = "rgb(315E5A)",
    color2 = "rgb(315E5A)",
}

local function read_palette(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local colors = {}
    for line in file:lines() do
        local name, value = line:match("^%s*%$([%w_]+)%s*=%s*(rgba?%b())")
        if name then
            colors[name] = value
        end
    end
    file:close()

    return next(colors) and colors or nil
end

local colors = read_palette(PALETTE_PATH) or FALLBACK

return setmetatable(colors, {
    __index = function(_, key)
        return FALLBACK[key] or "rgb(000000)"
    end,
})
