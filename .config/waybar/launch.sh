#!/bin/bash

# quit all running waybar instances
# to reload waybar properly
killall waybar

# load config and style file while launching waybar
waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css
