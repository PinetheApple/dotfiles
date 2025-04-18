#!/usr/bin/python3
### script to update hyprpaper with a random wallpaper or a wallpaper of choice

import os
import random
import subprocess
import sys

HOME = os.environ.get("HOME")
if HOME == None:
    print("Failed to get $HOME variable")
    sys.exit(1)

HYPRPAPER_CONF = HOME + "/.config/hypr/hyprpaper.conf"
CACHED_WALLPAPER = HOME + "/.cache/.current_wallpaper"
PYWAL_CACHE = HOME + "/.cache/wal/"


def get_displays():
    result = subprocess.run(
        ["hyprctl", "monitors"], capture_output=True, text=True
    )
    if result.returncode != 0:
        print(
            f"There was an error when trying to get the display. {result.stderr=}"
        )
        sys.exit(1)

    displays = [
        display_info.split(" ")[1]
        for display_info in result.stdout.split("\n\n")
        if len(display_info.split(" ")) > 1
    ]
    return displays


def get_preloaded_wallpapers():
    current_wallpaper = ""
    wallpapers = []

    with open(HYPRPAPER_CONF, "r") as conf_file:
        for line in conf_file:
            parts = [part.strip() for part in line.split("=")]
            if parts[0] == "preload":
                wallpapers.append(parts[1])
            elif parts[0] == "wallpaper":
                current_wallpaper = parts[1].split(",")[-1]

        wallpapers = [
            wallpaper
            for wallpaper in wallpapers
            if wallpaper != current_wallpaper
        ]

    return wallpapers


def convert_to_png(wallpaper: str):
    img_name = wallpaper.split("/")[-1]
    if img_name.endswith(".jpg"):
        img_name = img_name[:-4]
    else:
        img_name = img_name[:-5]

    png_wallpaper = "/tmp/" + img_name + ".png"
    if os.path.exists(png_wallpaper):
        print(f"Found {png_wallpaper}.")
        return png_wallpaper

    print("No PNG version found in '/tmp'. Creating PNG version...")
    result = subprocess.run(
        ["magick", wallpaper, png_wallpaper], capture_output=True, text=True
    )
    if not result.returncode == 0:
        print(f"Failed to create PNG version. {result.stderr=}")
        return wallpaper

    return png_wallpaper


def update_pywal():
    # clear cache as it prevents pywal from properly updating the colours
    result = subprocess.run(["rm", "-r", PYWAL_CACHE])
    if not result.returncode == 0:
        print(f"Failed to clear pywal cache. {result.stderr=}")

    result = subprocess.run(
        ["wal", "-i", CACHED_WALLPAPER],
    )
    if not result.returncode == 0:
        print(f"Failed to update pywal. {result.stderr=}")
        return

    print("Successfully updated pywal theme!")


def update_wallpaper(wallpaper: str, displays: list):
    # check if wallpaper file exists and is an image
    if not (os.path.exists(wallpaper) and os.path.isfile(wallpaper)):
        print(
            f"{wallpaper} is does not exist or is not a regular file. Exiting..."
        )
        sys.exit(1)

    if not wallpaper.endswith((".jpg", ".jpeg", ".png")):
        print(f"{wallpaper} is not a valid JPG or PNG file. Exiting...")
        sys.exit(1)

    for display in displays:
        wallpaper_arg = display + "," + wallpaper
        result = subprocess.run(
            ["hyprctl", "hyprpaper", "wallpaper", wallpaper_arg],
            capture_output=True,
            text=True,
        )
        if not result.returncode == 0:
            print(f"Failed to update wallpaper using hyprctl. {result.stderr=}")
            return

    print("Updated wallpaper successfully!\n")
    if wallpaper.endswith((".jpg", ".jpeg")):
        print(
            "Image is JPG. Checking for PNG version in '/tmp' for hyprlock..."
        )
        wallpaper = convert_to_png(wallpaper)

    print("Copying wallpaper to .cache directory...")
    result = subprocess.run(
        ["cp", wallpaper, CACHED_WALLPAPER],
        capture_output=True,
        text=True,
    )
    if not result.returncode == 0:
        print(f"Failed to copy wallpaper to .cache directory. {result.stderr=}")
        return

    print(f"Successfully saved wallpaper as {CACHED_WALLPAPER}!")


def select_random_wallpaper():
    wallpapers = []

    if not os.path.exists(HYPRPAPER_CONF):
        print(f"{HYPRPAPER_CONF} file does not exist. Exiting...")
        sys.exit(1)

    wallpapers = get_preloaded_wallpapers()
    wallpaper = random.choice(wallpapers)
    print("Random wallpaper selected: ", wallpaper)
    return wallpaper


def main():
    if len(sys.argv) > 1:
        wallpaper = sys.argv[1]
        if not wallpaper.startswith(("~", "/")):
            wallpaper = HOME + "/Pictures/Wallpapers/" + wallpaper
    else:
        print("No wallpaper specified. Selecting a random wallpaper...")
        wallpaper = select_random_wallpaper()

    displays = get_displays()
    update_wallpaper(wallpaper, displays)
    update_pywal()


if __name__ == "__main__":
    main()
