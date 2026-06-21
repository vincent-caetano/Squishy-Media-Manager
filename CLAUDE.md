# Squishy

Native macOS wrapper around the `ffmpeg` installed on the machine. Supports MP4 H.264, MP4 HEVC, WebM VP9, GIF, and Audio M4A exports with customizable output name, destination, resolution, quality, and optional approximate target file size.

## Design

Follow the Apple Human Interface Guidelines for all UI/UX decisions, especially component usage and layout:

https://developer.apple.com/design/human-interface-guidelines/components

When building or modifying SwiftUI views, prefer native macOS components and standard interaction patterns described there over custom controls.

## Build

```sh
chmod +x build.sh
./build.sh
```

The app bundle is created at `build/Squishy.app`.
