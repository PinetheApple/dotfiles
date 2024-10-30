#!/bin/bash

load_wallpaper() {
	local wallpaper_dir="$HOME/Pictures/Wallpapers"
	
	find "$wallpaper_dir" -type f \( \
		-iname "*.jpg" -o \
		-iname "*.png" \
	\) | sed 's/^/preload = /' >> "$config_file"	
}

config_file="$HOME/.config/hypr/hyprpaper2.conf"
> "$config_file"
load_wallpaper
