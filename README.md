# Squishy

Tiny native macOS wrapper around the `ffmpeg` installed on this machine.

The app supports MP4 H.264, MP4 HEVC, WebM VP9, GIF, and Audio M4A exports with customizable output name, destination, resolution, quality, and optional approximate target file size.

## First launch

Squishy verifies its prerequisites before enabling the main interface:

- [Homebrew](https://brew.sh/) can install and manage the required command-line tools.
- `ffmpeg` and `ffprobe` handle media inspection and conversion.
- `yt-dlp` handles YouTube downloads.

When Homebrew is available, the onboarding assistant can install the media tools and displays the installation log. If Homebrew is missing, it walks the user through the official Homebrew installation command. Setup only completes after Squishy launches each required tool and verifies that it responds successfully.

## Build

```sh
chmod +x build.sh
./build.sh
```

The app bundle is created at:

```txt
Squishy-MediaCompressor/build/Squishy.app
```

Tagged releases are built on GitHub's ARM64 macOS runner. A matching `vX.Y.Z` tag creates an ad-hoc signed DMG, ZIP archive, and SHA-256 checksum file on the GitHub Releases page.

## Use

Open the app, choose or drop a video, pick a preset, then press Compress.
Outputs are saved beside the source file by default.
