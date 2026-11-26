#!/usr/bin/env bash
# Generate the default launcher, adaptive foreground and notification icons.
set -eu

res="android/app/src/main/res"
mark="macos/plezy.icon/Assets/offstage.png"
tile="assets/plezy.png"

# At xxxhdpi, 432 px is the adaptive icon's 108 dp canvas. Android also
# uses this layer's alpha channel for themed monochrome icons.
magick "$mark" -resize 238x238 -background none -gravity center -extent 432x432 \
  "$res/drawable-xxxhdpi/gucciplexa_foreground.png"

while read -r density launcher notification; do
  magick "$tile" -resize "${launcher}x${launcher}" "$res/mipmap-$density/ic_launcher.png"
  magick "$mark" -resize "${notification}x${notification}" -background none -gravity center \
    -extent "${notification}x${notification}" -channel RGB -evaluate set 100% +channel \
    "$res/drawable-$density/ic_stat_notification.png"
done <<'SIZES'
mdpi 48 24
hdpi 72 36
xhdpi 96 48
xxhdpi 144 72
xxxhdpi 192 96
SIZES
