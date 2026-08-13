# Squishy

Tiny native macOS wrapper around the `ffmpeg` installed on this machine.

The app supports MP4 H.264, MP4 HEVC, WebM VP9, GIF, Audio M4A, and JPEG/PNG/WebP image exports with customizable output name, destination, resolution, quality, and optional approximate target file size.

Files are processed as a queue: drop as many as you like and Squishy converts five at a time, showing per-file progress and errors.

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

Open the app, choose or drop one or more files, pick a preset, then press Compress.
Outputs are saved beside each source file by default, or in a single folder chosen with the Destination control.

Click the status strip at the bottom of the window to open the console, which logs every job, its size change, and the ffmpeg output for anything that failed.

## Updating

Squishy checks the GitHub Releases API for a newer version when it launches, at most once per day, and offers to open the download page. You can also check on demand from **Squishy ▸ Check for Updates…**.

Updating is a manual replace: download the new `.dmg` and drag Squishy into Applications over the old copy. Settings and the queue are not affected.
