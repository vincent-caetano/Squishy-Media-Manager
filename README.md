# Squishy

Tiny native macOS wrapper around the `ffmpeg` installed on this machine.

The app supports MP4 H.264, MP4 HEVC, WebM VP9, GIF, and Audio M4A exports with customizable output name, destination, resolution, quality, and optional approximate target file size.

## Build

```sh
chmod +x build.sh
./build.sh
```

The app bundle is created at:

```txt
Squishy-MediaCompressor/build/Squishy.app
```

## Use

Open the app, choose or drop a video, pick a preset, then press Compress.
Outputs are saved beside the source file by default.
