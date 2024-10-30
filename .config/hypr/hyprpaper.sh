#!/bin/bash

load_wallpapers() {
	local wallpaper_dir="$HOME/Pictures/Wallpapers"
	local first_image_found=false
	local wallpaper=""

	while IFS= read -r image; do
        if [ "$first_image_found" = false ]; then
            wallpaper="$image"
            first_image_found=true
        fi
        echo "preload = $image" >> "$config_file"
    done < <(find "$wallpaper_dir" -type f \( -iname "*.jpg" -o -iname "*.png" \))
	
	echo -e "\nwallpaper = ,$wallpaper" >> "$config_file"  # set current wallpaper
}

config_file="$HOME/.config/hypr/hyprpaper2.conf"
> "$config_file"  # clear config file

load_wallpapers

echo -e "\nsplash = false" >> "$config_file"
