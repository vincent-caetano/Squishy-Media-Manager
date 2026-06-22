# Squishy

Native macOS wrapper around the `ffmpeg` installed on the machine. Supports MP4 H.264, MP4 HEVC, WebM VP9, GIF, and Audio M4A exports with customizable output name, destination, resolution, quality, and optional approximate target file size.

## Design

Follow the Apple Human Interface Guidelines for all UI/UX decisions, especially component usage and layout:

https://developer.apple.com/design/human-interface-guidelines/components

When building or modifying SwiftUI views, prefer native macOS components and standard interaction patterns described there over custom controls.

### Component sources

There is no fetchable "macOS UI component library" package — native controls ship with SwiftUI/AppKit in the SDK already (`Button`, `Picker`, `Toggle`, `Slider`, `Form`, `NavigationSplitView`, `Table`, etc.). Use these references when implementing or reviewing UI:

- Apple HIG components: https://developer.apple.com/design/human-interface-guidelines/components
- SwiftUIX (extra SwiftUI controls/utilities, use sparingly and only when no native equivalent exists): https://github.com/SwiftUIX/SwiftUIX
- ExploreSwiftUI (SwiftUI component examples/patterns): https://exploreswiftui.com/

Prefer plain native SwiftUI first; only reach for SwiftUIX when it fills a genuine gap, since third-party controls can drift from native HIG look-and-feel.

## Build

```sh
chmod +x build.sh
./build.sh
```

The app bundle is created at `build/Squishy.app`.
