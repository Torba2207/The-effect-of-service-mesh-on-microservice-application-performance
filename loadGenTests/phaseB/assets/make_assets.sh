#!/usr/bin/env bash
# Regenerates the fixed Phase B work-unit assets. The committed files are the
# canonical bytes used for every run; only re-run this if you intend to change them
# (and then re-commit). Requires ImageMagick + ffmpeg.
#
# Phase B uses deliberately LIGHT assets so each request is a few ms / sub-second and
# services stay below saturation under aggregate load (see ../README.md). Phase A's
# heavier work units (512x512 PNG, 10s 720p video) are generated elsewhere.
set -euo pipefail
cd "$(dirname "$0")"

# 128x128 detailed image -> ~15-20 ms blur (sustains 100 req/s within 500m x3).
magick -size 512x512 -seed 42 plasma:fractal -resize 128x128 -depth 8 filter_input_128.png

# 1 s, 360p H.264 -> ~0.5 s compress (sustains the low video rate within 1 CPU x3).
ffmpeg -y -loglevel error -f lavfi -i mandelbrot=size=640x360:rate=24 -t 1 \
  -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p sample_360p_1s.mp4

ls -la filter_input_128.png sample_360p_1s.mp4
