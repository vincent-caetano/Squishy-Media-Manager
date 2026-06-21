import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4H264
    case mp4HEVC
    case webmVP9
    case gif
    case audioM4A
    case imageJPEG
    case imagePNG
    case imageWebP

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp4H264: return "MP4 H.264"
        case .mp4HEVC: return "MP4 HEVC"
        case .webmVP9: return "WebM VP9"
        case .gif: return "GIF"
        case .audioM4A: return "Audio M4A"
        case .imageJPEG: return "JPEG Image"
        case .imagePNG: return "PNG Image"
        case .imageWebP: return "WebP Image"
        }
    }

    var detail: String {
        switch self {
        case .mp4H264: return "Most compatible video export"
        case .mp4HEVC: return "Smaller files for Apple devices"
        case .webmVP9: return "Web-friendly VP9 video"
        case .gif: return "Short silent animation"
        case .audioM4A: return "AAC audio-only export"
        case .imageJPEG: return "Compressed photo, smaller files"
        case .imagePNG: return "Lossless image, larger files"
        case .imageWebP: return "Modern format, great compression"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: return "mp4"
        case .webmVP9: return "webm"
        case .gif: return "gif"
        case .audioM4A: return "m4a"
        case .imageJPEG: return "jpg"
        case .imagePNG: return "png"
        case .imageWebP: return "webp"
        }
    }

    var isImage: Bool {
        switch self {
        case .imageJPEG, .imagePNG, .imageWebP: return true
        default: return false
        }
    }

    var isAudioOnly: Bool { self == .audioM4A }

    var supportsTargetSize: Bool {
        if self == .gif { return false }
        if isImage { return self != .imagePNG }
        return true
    }

    var supportsQuality: Bool { self != .imagePNG }
}

enum SourceKind {
    case video
    case image
}

enum YouTubeDownloadKind: String, CaseIterable, Identifiable {
    case video
    case audioOnly

    var id: String { rawValue }
    var title: String { self == .video ? "Video" : "Audio Only" }
}

enum ResolutionOption: String, CaseIterable, Identifiable {
    case original
    case p2160
    case p1440
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .p2160: return "2160p"
        case .p1440: return "1440p"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        }
    }

    var height: Int? {
        switch self {
        case .original: return nil
        case .p2160: return 2160
        case .p1440: return 1440
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        }
    }
}

enum SizeUnit: String, CaseIterable, Identifiable {
    case mb
    case kb

    var id: String { rawValue }
    var title: String { self == .mb ? "MB" : "KB" }
}

struct ExportSettings: Equatable {
    var outputFolder: URL?
    var outputName = ""
    var format: OutputFormat = .mp4H264
    var resolution: ResolutionOption = .original
    var targetSizeText = ""
    var targetSizeUnit: SizeUnit = .mb
    var quality = 62.0

    var targetSizeKB: Int? {
        let trimmed = targetSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else { return nil }
        return targetSizeUnit == .mb ? value * 1024 : value
    }
}

struct MediaMetadata: Equatable {
    var duration: Double?
    var videoCodec: String?
    var width: Int?
    var height: Int?
    var frameRate: String?
    var audioCodec: String?

    var durationText: String {
        guard let duration else { return "Unknown duration" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var videoText: String {
        guard let width, let height else { return "Video details unavailable" }
        let codec = videoCodec?.uppercased() ?? "Video"
        let fps = frameRate.map { " · \($0)" } ?? ""
        return "\(codec) · \(width)x\(height)\(fps)"
    }

    var audioText: String {
        guard let audioCodec else { return "No audio detected" }
        return "\(audioCodec.uppercased()) audio"
    }
}

enum JobState: Equatable {
    case idle
    case running
    case finished(URL)
    case failed(String)
}

@MainActor
final class CompressorModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var inputKind: SourceKind = .video
    @Published var settings = ExportSettings()
    @Published var metadata: MediaMetadata?
    @Published var jobState: JobState = .idle
    @Published var progress: Double = 0
    @Published var statusText = "Choose a source video to begin."
    @Published var ffmpegLog = "Ready"

    @Published var youtubeURLText = ""
    @Published var youtubeKind: YouTubeDownloadKind = .video
    @Published var isDownloadingYouTube = false
    @Published var youtubeDownloadProgress: Double = 0
    @Published var youtubeDownloadStatus = "Paste a YouTube link to download."
    @Published var youtubeDownloadLog = ""
    @Published var youtubeDownloadElapsed: TimeInterval = 0

    private var youtubeDownloadTimer: Timer?

    @Published var isYtDlpOutdated = false
    @Published var isUpdatingYtDlp = false
    @Published var ytDlpUpdateMessage: String?
    @Published var showYtDlpUpdateAlert = false
    @Published var ytDlpUpdateLog = ""
    @Published var ytDlpUpdateElapsed: TimeInterval = 0

    private var process: Process?
    private var youtubeProcess: Process?
    private var ytDlpUpdateProcess: Process?
    private var ytDlpUpdateTimer: Timer?
    private let ffmpegPath = ToolLocator.find("ffmpeg")
    private let ffprobePath = ToolLocator.find("ffprobe")
    private let ytDlpPath = ToolLocator.find("yt-dlp")
    private let brewPath = ToolLocator.find("brew")

    private static let ytDlpUpdateExpectedSeconds: TimeInterval = 20

    init() {
        checkYtDlpFreshness()
    }

    var ffmpegStatus: String {
        guard let ffmpegPath else { return "ffmpeg not found" }
        return ffmpegPath
    }

    var ytDlpStatus: String {
        guard let ytDlpPath else { return "yt-dlp not found" }
        return ytDlpPath
    }

    var canDownloadYouTube: Bool {
        ytDlpPath != nil && ffmpegPath != nil && !isDownloadingYouTube && isValidYouTubeURL(youtubeURLText)
    }

    private func checkYtDlpFreshness() {
        guard let ytDlpPath else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return
            }
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let versionString = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy.MM.dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            guard let releaseDate = formatter.date(from: String(versionString.prefix(10))) else { return }

            let daysOld = Calendar.current.dateComponents([.day], from: releaseDate, to: Date()).day ?? 0
            let outdated = daysOld > 90

            DispatchQueue.main.async {
                guard let self else { return }
                self.isYtDlpOutdated = outdated
                if outdated {
                    self.ytDlpUpdateMessage = "Your yt-dlp version (\(versionString)) is older than 90 days. Update to keep YouTube downloads working."
                    self.showYtDlpUpdateAlert = true
                }
            }
        }
    }

    var ytDlpUpdateProgressNote: String {
        let remaining = Self.ytDlpUpdateExpectedSeconds - ytDlpUpdateElapsed
        if remaining > 1 {
            return "Updating yt-dlp... \(Int(ytDlpUpdateElapsed))s elapsed, usually finishes in ~\(Int(Self.ytDlpUpdateExpectedSeconds))s."
        }
        return "Updating yt-dlp... \(Int(ytDlpUpdateElapsed))s elapsed, almost done."
    }

    func updateYtDlp() {
        guard let brewPath else {
            ytDlpUpdateMessage = "Homebrew not found. Install yt-dlp updates with: brew upgrade yt-dlp"
            return
        }
        guard !isUpdatingYtDlp else { return }

        isUpdatingYtDlp = true
        ytDlpUpdateLog = "$ brew upgrade yt-dlp\n"
        ytDlpUpdateElapsed = 0
        ytDlpUpdateMessage = ytDlpUpdateProgressNote

        ytDlpUpdateTimer?.invalidate()
        let startedAt = Date()
        ytDlpUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ytDlpUpdateElapsed = Date().timeIntervalSince(startedAt)
                self.ytDlpUpdateMessage = self.ytDlpUpdateProgressNote
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["upgrade", "--verbose", "yt-dlp"]

        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin"] + [existingPath]).joined(separator: ":")
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        ytDlpUpdateProcess = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.ytDlpUpdateLog += text
            }
        }

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.ytDlpUpdateTimer?.invalidate()
                self.ytDlpUpdateTimer = nil
                self.ytDlpUpdateProcess = nil
                self.isUpdatingYtDlp = false
                if process.terminationStatus == 0 {
                    self.isYtDlpOutdated = false
                    self.ytDlpUpdateMessage = "yt-dlp updated successfully in \(Int(self.ytDlpUpdateElapsed))s."
                    self.checkYtDlpFreshness()
                } else {
                    self.ytDlpUpdateMessage = "Update failed. Try running 'brew upgrade yt-dlp' manually."
                }
            }
        }

        do {
            try process.run()
        } catch {
            ytDlpUpdateTimer?.invalidate()
            ytDlpUpdateTimer = nil
            isUpdatingYtDlp = false
            ytDlpUpdateMessage = error.localizedDescription
        }
    }

    var outputURL: URL? {
        guard let folder = settings.outputFolder else { return nil }
        let base = sanitizedOutputName
        guard !base.isEmpty else { return nil }
        return folder.appendingPathComponent(base).appendingPathExtension(settings.format.fileExtension)
    }

    var validationMessage: String? {
        if ffmpegPath == nil { return "Install ffmpeg with Homebrew to enable exports." }
        if inputURL == nil { return "Choose or drop a media file first." }
        if sanitizedOutputName.isEmpty { return "Enter an output name." }
        if settings.targetSizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && settings.targetSizeKB == nil {
            return "Target size must be a whole number."
        }
        return nil
    }

    var canRun: Bool {
        validationMessage == nil && jobState != .running
    }

    var targetSizeNote: String {
        guard settings.targetSizeKB != nil else { return "Quality controls compression when no target size is set." }
        guard settings.format.supportsTargetSize else {
            return settings.format.isImage
                ? "PNG is lossless; target size is ignored."
                : "GIF ignores target size and uses animation defaults."
        }
        if settings.format.isImage {
            return "Approximate target: \(settings.targetSizeText.trimmingCharacters(in: .whitespacesAndNewlines)) \(settings.targetSizeUnit.title) (ffmpeg searches for a matching quality)."
        }
        guard metadata?.duration != nil else { return "Duration unavailable; export will use quality instead." }
        return "Approximate target: \(settings.targetSizeText.trimmingCharacters(in: .whitespacesAndNewlines)) \(settings.targetSizeUnit.title)."
    }

    private var sanitizedOutputName: String {
        settings.outputName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video, .audio, .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            setInput(url)
        }
    }

    func setInput(_ url: URL) {
        inputURL = url
        inputKind = sourceKind(for: url)
        settings.outputFolder = url.deletingLastPathComponent()
        settings.outputName = "\(url.deletingPathExtension().lastPathComponent)-compressed"
        normalizeFormatForInputKind()
        metadata = loadMetadata(for: url)
        progress = 0
        statusText = "Ready to export \(url.lastPathComponent)."
        ffmpegLog = "Loaded source metadata."
        jobState = .idle
    }

    private func sourceKind(for url: URL) -> SourceKind {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .image) == true ? .image : .video
    }

    private func normalizeFormatForInputKind() {
        if inputKind == .image, settings.format.isImage == false {
            settings.format = .imageJPEG
        } else if inputKind == .video, settings.format.isImage {
            settings.format = .mp4H264
        }
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? "compressed.\(settings.format.fileExtension)"
        panel.allowedContentTypes = allowedContentTypes(for: settings.format)

        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url.deletingLastPathComponent()
            settings.outputName = url.deletingPathExtension().lastPathComponent
        }
    }

    func normalizeSettingsAfterFormatChange() {
        if settings.format.isAudioOnly {
            settings.resolution = .original
        }
    }

    func compress() {
        guard let ffmpegPath, let inputURL, let outputURL else { return }

        if settings.format.isImage, settings.format.supportsTargetSize, let targetKB = settings.targetSizeKB {
            compressImageToTargetSize(targetBytes: targetKB * 1024)
            return
        }

        let plan = FFmpegPlan.make(settings: settings, metadata: metadata)
        var args = ["-hide_banner", "-y", "-i", inputURL.path]
        args.append(contentsOf: plan.arguments)
        args.append(contentsOf: ["-progress", "pipe:1", "-nostats", outputURL.path])

        progress = 0
        statusText = "Exporting \(settings.format.title)..."
        ffmpegLog = "Running ffmpeg."
        jobState = .running

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        self.process = process

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consumeProgress(text)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.process = nil
                if process.terminationStatus == 0 {
                    self.progress = 1
                    self.jobState = .finished(outputURL)
                    self.statusText = "Export complete."
                    self.ffmpegLog = "Created \(outputURL.lastPathComponent)."
                } else {
                    self.jobState = .failed("ffmpeg exited with code \(process.terminationStatus)")
                    self.statusText = "Export failed."
                }
            }
        }

        do {
            try process.run()
        } catch {
            jobState = .failed(error.localizedDescription)
            statusText = "Could not start export."
            ffmpegLog = error.localizedDescription
        }
    }

    private func compressImageToTargetSize(targetBytes: Int) {
        guard let ffmpegPath, let inputURL, let outputURL else { return }

        progress = 0
        statusText = "Searching for a quality near the target size..."
        ffmpegLog = "Running ffmpeg (size search)."
        jobState = .running

        let baseSettings = settings
        let baseMetadata = metadata
        let tempDir = FileManager.default.temporaryDirectory
        let trialURL = tempDir.appendingPathComponent("mediacompressor-trial-\(UUID().uuidString)").appendingPathExtension(baseSettings.format.fileExtension)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let maxIterations = 6
            var low = 1.0
            var high = 100.0
            var bestURL: URL?
            var bestDelta = Int.max

            for iteration in 0..<maxIterations {
                let trialQuality = ((low + high) / 2).rounded()
                var trialSettings = baseSettings
                trialSettings.quality = trialQuality
                trialSettings.targetSizeText = ""

                let plan = FFmpegPlan.make(settings: trialSettings, metadata: baseMetadata)
                try? FileManager.default.removeItem(at: trialURL)

                var args = ["-hide_banner", "-y", "-i", inputURL.path]
                args.append(contentsOf: plan.arguments)
                args.append(trialURL.path)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegPath)
                process.arguments = args
                process.standardOutput = Pipe()
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    DispatchQueue.main.async {
                        self.jobState = .failed(error.localizedDescription)
                        self.statusText = "Could not start export."
                    }
                    return
                }
                process.waitUntilExit()

                guard let attributes = try? FileManager.default.attributesOfItem(atPath: trialURL.path),
                      let fileSize = attributes[.size] as? Int else { continue }

                let delta = abs(fileSize - targetBytes)
                if delta < bestDelta {
                    bestDelta = delta
                    if let bestURL {
                        try? FileManager.default.removeItem(at: bestURL)
                    }
                    let candidateURL = tempDir.appendingPathComponent("mediacompressor-best-\(UUID().uuidString)").appendingPathExtension(baseSettings.format.fileExtension)
                    try? FileManager.default.copyItem(at: trialURL, to: candidateURL)
                    bestURL = candidateURL
                }

                let progressFraction = Double(iteration + 1) / Double(maxIterations)
                let sizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                DispatchQueue.main.async {
                    self.progress = min(progressFraction * 0.99, 0.99)
                    self.statusText = "Trying quality \(Int(trialQuality))... (\(sizeText))"
                }

                if fileSize > targetBytes {
                    high = trialQuality - 1
                } else {
                    low = trialQuality + 1
                }
                if low > high { break }
            }

            try? FileManager.default.removeItem(at: trialURL)

            DispatchQueue.main.async {
                guard let bestURL else {
                    self.jobState = .failed("Could not produce an output near the target size.")
                    self.statusText = "Export failed."
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    try FileManager.default.copyItem(at: bestURL, to: outputURL)
                    try? FileManager.default.removeItem(at: bestURL)
                    self.progress = 1
                    self.jobState = .finished(outputURL)
                    self.statusText = "Export complete."
                    self.ffmpegLog = "Created \(outputURL.lastPathComponent)."
                } catch {
                    self.jobState = .failed(error.localizedDescription)
                    self.statusText = "Could not save export."
                }
            }
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        progress = 0
        jobState = .idle
        statusText = "Export cancelled."
        ffmpegLog = "Cancelled"
    }

    static func normalizedYouTubeURLText(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let substitutions: [Character: Character] = [
            "\u{2010}": "-", "\u{2011}": "-", "\u{2012}": "-",
            "\u{2013}": "-", "\u{2014}": "-", "\u{2212}": "-",
            "\u{2018}": "'", "\u{2019}": "'", "\u{201C}": "\"", "\u{201D}": "\""
        ]
        for (smart, plain) in substitutions {
            result = result.replacingOccurrences(of: String(smart), with: String(plain))
        }
        return result
    }

    var youtubeURLValidationHint: String? {
        let trimmed = youtubeURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !isValidYouTubeURL(trimmed) else { return nil }
        if trimmed != Self.normalizedYouTubeURLText(trimmed) {
            return "This link contains a curly/smart dash or quote (likely inserted by macOS autocorrect while typing). Paste the link instead of typing it, or retype it with Edit > Substitutions > Smart Dashes turned off."
        }
        return "This doesn't look like a youtube.com or youtu.be link."
    }

    private func isValidYouTubeURL(_ text: String) -> Bool {
        let trimmed = Self.normalizedYouTubeURLText(text)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    func downloadYouTube() {
        guard let ytDlpPath, let ffmpegPath else { return }
        let trimmed = Self.normalizedYouTubeURLText(youtubeURLText)
        guard isValidYouTubeURL(trimmed) else { return }

        let folder = settings.outputFolder
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let ffmpegFolder = (ffmpegPath as NSString).deletingLastPathComponent
        let beforeNames = Set((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.map { $0.lastPathComponent } ?? [])

        var args = [
            "--newline", "--no-playlist",
            "--ffmpeg-location", ffmpegFolder,
            "-o", folder.appendingPathComponent("%(title).200B [%(id)s].%(ext)s").path
        ]

        switch youtubeKind {
        case .video:
            args.append(contentsOf: ["-f", "bv*+ba/b", "--merge-output-format", "mp4"])
        case .audioOnly:
            args.append(contentsOf: ["-x", "--audio-format", "m4a"])
        }
        args.append(trimmed)

        isDownloadingYouTube = true
        youtubeDownloadProgress = 0
        youtubeDownloadStatus = "Starting download..."
        youtubeDownloadLog = "$ yt-dlp \(args.joined(separator: " "))\n"
        youtubeDownloadElapsed = 0
        ffmpegLog = "Running yt-dlp."

        youtubeDownloadTimer?.invalidate()
        let startedAt = Date()
        youtubeDownloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.youtubeDownloadElapsed = Date().timeIntervalSince(startedAt)
                if self.youtubeDownloadProgress == 0 {
                    self.youtubeDownloadStatus = "Working... \(Int(self.youtubeDownloadElapsed))s elapsed (resolving video info)."
                }
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = environment

        youtubeProcess = process

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.youtubeDownloadLog += text
                self?.consumeYouTubeProgress(text)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.youtubeDownloadLog += text
                self?.appendLog(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.youtubeDownloadTimer?.invalidate()
                self.youtubeDownloadTimer = nil
                self.youtubeProcess = nil
                self.isDownloadingYouTube = false

                let afterFiles = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                let newFile = afterFiles.first {
                    !beforeNames.contains($0.lastPathComponent) && !$0.lastPathComponent.hasSuffix(".part")
                }

                if process.terminationStatus == 0, let newFile {
                    self.youtubeDownloadProgress = 1
                    self.youtubeDownloadStatus = "Download complete in \(Int(self.youtubeDownloadElapsed))s."
                    self.youtubeURLText = ""
                    self.setInput(newFile)
                } else {
                    let lastLine = self.youtubeDownloadLog
                        .split(separator: "\n")
                        .map(String.init)
                        .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    self.youtubeDownloadStatus = lastLine.map { "Download failed: \($0)" } ?? "Download failed."
                }
            }
        }

        do {
            try process.run()
        } catch {
            youtubeDownloadTimer?.invalidate()
            youtubeDownloadTimer = nil
            isDownloadingYouTube = false
            youtubeDownloadStatus = "Could not start download."
        }
    }

    func cancelYouTubeDownload() {
        youtubeDownloadTimer?.invalidate()
        youtubeDownloadTimer = nil
        youtubeProcess?.terminate()
        youtubeProcess = nil
        isDownloadingYouTube = false
        youtubeDownloadProgress = 0
        youtubeDownloadStatus = "Download cancelled."
    }

    private func consumeYouTubeProgress(_ text: String) {
        for line in text.split(separator: "\n") where line.contains("[download]") {
            for token in line.split(separator: " ") where token.hasSuffix("%") {
                if let value = Double(token.dropLast()) {
                    youtubeDownloadProgress = min(max(value / 100, 0), 0.99)
                    youtubeDownloadStatus = "Downloading... \(Int(value))%"
                }
            }
        }
    }

    func revealOutput() {
        guard case let .finished(url) = jobState else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func consumeProgress(_ text: String) {
        for line in text.split(separator: "\n") {
            if line.hasPrefix("out_time_ms="),
               let raw = Double(line.replacingOccurrences(of: "out_time_ms=", with: "")),
               let duration = metadata?.duration,
               duration > 0 {
                progress = min(max((raw / 1_000_000) / duration, 0), 0.99)
            }

            if line == "progress=end" {
                progress = 1
            }
        }
    }

    private func appendLog(_ text: String) {
        let cleaned = text
            .split(separator: "\n")
            .suffix(5)
            .joined(separator: "\n")

        if !cleaned.isEmpty {
            ffmpegLog = cleaned
        }
    }

    private func loadMetadata(for url: URL) -> MediaMetadata {
        if inputKind == .image {
            return loadImageMetadata(for: url)
        }

        return MediaMetadata(
            duration: probeDuration(for: url),
            videoCodec: probeValue(for: url, arguments: ["-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "default=noprint_wrappers=1:nokey=1"]),
            width: Int(probeValue(for: url, arguments: ["-select_streams", "v:0", "-show_entries", "stream=width", "-of", "default=noprint_wrappers=1:nokey=1"]) ?? ""),
            height: Int(probeValue(for: url, arguments: ["-select_streams", "v:0", "-show_entries", "stream=height", "-of", "default=noprint_wrappers=1:nokey=1"]) ?? ""),
            frameRate: normalizedFrameRate(probeValue(for: url, arguments: ["-select_streams", "v:0", "-show_entries", "stream=avg_frame_rate", "-of", "default=noprint_wrappers=1:nokey=1"])),
            audioCodec: probeValue(for: url, arguments: ["-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "default=noprint_wrappers=1:nokey=1"])
        )
    }

    private func loadImageMetadata(for url: URL) -> MediaMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return MediaMetadata()
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let formatName = (CGImageSourceGetType(source) as String?)
            .flatMap { UTType($0)?.preferredFilenameExtension }?
            .uppercased()

        return MediaMetadata(duration: nil, videoCodec: formatName, width: width, height: height, frameRate: nil, audioCodec: nil)
    }

    private func probeDuration(for url: URL) -> Double? {
        probeValue(for: url, arguments: [
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1"
        ]).flatMap(Double.init)
    }

    private func probeValue(for url: URL, arguments: [String]) -> String? {
        guard let ffprobePath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = ["-v", "error"] + arguments + [url.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let value = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        } catch {
            return nil
        }
    }

    private func normalizedFrameRate(_ value: String?) -> String? {
        guard let value, value != "0/0" else { return nil }
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return value }
        let fps = parts[0] / parts[1]
        return fps.rounded() == fps ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps)
    }

    private func allowedContentTypes(for format: OutputFormat) -> [UTType] {
        switch format {
        case .mp4H264, .mp4HEVC:
            return [.mpeg4Movie]
        case .webmVP9:
            return [UTType(filenameExtension: "webm") ?? .movie]
        case .gif:
            return [.gif]
        case .audioM4A:
            return [.mpeg4Audio]
        case .imageJPEG:
            return [.jpeg]
        case .imagePNG:
            return [.png]
        case .imageWebP:
            return [UTType(filenameExtension: "webp") ?? .image]
        }
    }
}

struct FFmpegPlan {
    let arguments: [String]

    static func make(settings: ExportSettings, metadata: MediaMetadata?) -> FFmpegPlan {
        var args: [String] = []

        if settings.format.isAudioOnly == false, let height = settings.resolution.height {
            args.append(contentsOf: ["-vf", "scale=-2:\(height)"])
        }

        if settings.format.isImage {
            args.append(contentsOf: ["-frames:v", "1"])
        }

        switch settings.format {
        case .mp4H264:
            args.append(contentsOf: videoRateArgs(settings: settings, metadata: metadata, audioKbps: 160, qualityCRF: crf(settings.quality, low: 18, high: 32)))
            args.append(contentsOf: ["-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"])
        case .mp4HEVC:
            args.append(contentsOf: videoRateArgs(settings: settings, metadata: metadata, audioKbps: 160, qualityCRF: crf(settings.quality, low: 20, high: 34)))
            args.append(contentsOf: ["-c:v", "libx265", "-preset", "fast", "-tag:v", "hvc1", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"])
        case .webmVP9:
            if settings.targetSizeKB != nil, metadata?.duration != nil {
                args.append(contentsOf: videoRateArgs(settings: settings, metadata: metadata, audioKbps: 128, qualityCRF: crf(settings.quality, low: 24, high: 42)))
            } else {
                args.append(contentsOf: ["-b:v", "0", "-crf", "\(crf(settings.quality, low: 24, high: 42))"])
            }
            args.append(contentsOf: ["-c:v", "libvpx-vp9", "-deadline", "good", "-cpu-used", "4", "-c:a", "libopus", "-b:a", "128k"])
        case .gif:
            if settings.resolution.height == nil {
                args.append(contentsOf: ["-vf", "fps=12,scale=-2:-2:flags=lanczos"])
            } else {
                args.append(contentsOf: ["-vf", "fps=12,scale=-2:\(settings.resolution.height ?? 720):flags=lanczos"])
            }
            args.append("-an")
        case .audioM4A:
            args.append("-vn")
            if let bitrate = audioTargetBitrate(settings: settings, metadata: metadata) {
                args.append(contentsOf: ["-c:a", "aac", "-b:a", "\(bitrate)k"])
            } else {
                args.append(contentsOf: ["-c:a", "aac", "-b:a", "192k"])
            }
        case .imageJPEG:
            args.append(contentsOf: ["-q:v", "\(crf(settings.quality, low: 2, high: 31))"])
        case .imagePNG:
            args.append(contentsOf: ["-c:v", "png"])
        case .imageWebP:
            args.append(contentsOf: ["-c:v", "libwebp", "-quality", "\(Int(min(max(settings.quality, 0), 100)))"])
        }

        return FFmpegPlan(arguments: args)
    }

    private static func videoRateArgs(settings: ExportSettings, metadata: MediaMetadata?, audioKbps: Int, qualityCRF: Int) -> [String] {
        guard let targetKB = settings.targetSizeKB, let duration = metadata?.duration, duration > 0 else {
            return ["-crf", "\(qualityCRF)"]
        }

        let totalKbps = Int((Double(targetKB) * 8.0 / duration).rounded())
        let videoKbps = max(totalKbps - audioKbps, 250)
        return [
            "-b:v", "\(videoKbps)k",
            "-maxrate", "\(Int(Double(videoKbps) * 1.35))k",
            "-bufsize", "\(videoKbps * 2)k"
        ]
    }

    private static func audioTargetBitrate(settings: ExportSettings, metadata: MediaMetadata?) -> Int? {
        guard let targetKB = settings.targetSizeKB, let duration = metadata?.duration, duration > 0 else { return nil }
        let kbps = Int((Double(targetKB) * 8.0 / duration).rounded())
        return min(max(kbps, 48), 320)
    }

    private static func crf(_ quality: Double, low: Int, high: Int) -> Int {
        let normalized = min(max(quality, 0), 100) / 100
        return Int((Double(high) - ((Double(high - low)) * normalized)).rounded())
    }
}

/// A TextField that disables macOS's automatic smart-dash/quote/text substitutions,
/// which otherwise silently mangle pasted-or-typed URLs (e.g. turning `-` into an en dash).
struct PlainTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticTextCompletionEnabled = false
        }
    }
}

enum ToolLocator {
    static func find(_ name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }
}

struct ContentView: View {
    @StateObject private var model = CompressorModel()
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            sourceSidebar
            Divider()
            settingsPane
        }
        .frame(minWidth: 860, idealWidth: 940, minHeight: 610)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Squishy", systemImage: "arrow.down.and.line.horizontal.and.arrow.up")
                    .font(.title2.weight(.semibold))
                Text("Compress and convert with local ffmpeg.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            dropZone

            youtubeSection

            metadataSection

            Spacer(minLength: 12)

            statusSection
        }
        .padding(22)
        .frame(width: 330)
        .background(SidebarBackground())
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Export Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.chooseOutput()
                } label: {
                    Label("Save As", systemImage: "square.and.pencil")
                }
                .disabled(model.inputURL == nil || model.jobState == .running)
            }

            settingsForm

            Spacer(minLength: 10)

            actionBar
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dropZone: some View {
        Button {
            model.chooseInput()
        } label: {
            VStack(spacing: 12) {
                Image(systemName: model.inputURL == nil ? "plus.rectangle.on.folder" : "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.inputURL == nil ? Color.accentColor : .green)

                Text(model.inputURL?.lastPathComponent ?? "Drop media here")
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(model.inputURL == nil ? "or click to choose a file" : "Click to choose another source")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 158)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    model.setInput(url)
                }
            }
            return true
        }
    }

    private var youtubeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("YouTube Link", symbol: "play.rectangle")

            PlainTextField("Paste a YouTube URL", text: $model.youtubeURLText)
                .disabled(model.isDownloadingYouTube)
                .frame(height: 22)

            if let hint = model.youtubeURLValidationHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Download as", selection: $model.youtubeKind) {
                ForEach(YouTubeDownloadKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(model.isDownloadingYouTube)

            HStack(spacing: 10) {
                Button {
                    model.downloadYouTube()
                } label: {
                    Label(model.isDownloadingYouTube ? "Downloading..." : "Download", systemImage: "arrow.down.circle")
                }
                .disabled(!model.canDownloadYouTube)

                if model.isDownloadingYouTube {
                    Button("Cancel", role: .destructive) {
                        model.cancelYouTubeDownload()
                    }
                }

                if model.isYtDlpOutdated {
                    Button {
                        model.updateYtDlp()
                    } label: {
                        Label(model.isUpdatingYtDlp ? "Updating..." : "Update yt-dlp", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isUpdatingYtDlp)
                }
            }

            if model.isDownloadingYouTube {
                if model.youtubeDownloadProgress > 0 {
                    ProgressView(value: model.youtubeDownloadProgress)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }

            Text(model.ytDlpStatus == "yt-dlp not found" ? "Install yt-dlp with Homebrew to enable downloads." : model.youtubeDownloadStatus)
                .font(.caption)
                .foregroundStyle(model.ytDlpStatus == "yt-dlp not found" ? .red : .secondary)
                .lineLimit(2)

            if model.isDownloadingYouTube || !model.youtubeDownloadLog.isEmpty {
                ScrollView {
                    Text(model.youtubeDownloadLog)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(height: 90)
                .background(Color.black.opacity(0.25))
                .cornerRadius(6)
            }

            if model.isUpdatingYtDlp {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if let ytDlpUpdateMessage = model.ytDlpUpdateMessage {
                Text(ytDlpUpdateMessage)
                    .font(.caption)
                    .foregroundStyle(model.isYtDlpOutdated ? .orange : .secondary)
                    .lineLimit(2)
            }

            if model.isUpdatingYtDlp || !model.ytDlpUpdateLog.isEmpty {
                ScrollView {
                    Text(model.ytDlpUpdateLog)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                }
                .frame(height: 90)
                .background(Color.black.opacity(0.25))
                .cornerRadius(6)
            }
        }
        .alert("yt-dlp Update Available", isPresented: $model.showYtDlpUpdateAlert) {
            Button("Update Now") {
                model.updateYtDlp()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(model.ytDlpUpdateMessage ?? "Your yt-dlp version is older than 90 days. Update it to keep YouTube downloads working.")
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Source", symbol: "info.circle")

            if let metadata = model.metadata {
                if model.inputKind == .image {
                    InfoRow(symbol: "photo", title: "Image", value: metadata.videoText)
                } else {
                    InfoRow(symbol: "clock", title: "Duration", value: metadata.durationText)
                    InfoRow(symbol: "film", title: "Video", value: metadata.videoText)
                    InfoRow(symbol: "waveform", title: "Audio", value: metadata.audioText)
                }
            } else {
                Text("No source selected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Status", symbol: "dot.radiowaves.left.and.right")

            Label(model.ffmpegStatus, systemImage: model.ffmpegStatus == "ffmpeg not found" ? "exclamationmark.triangle.fill" : "terminal")
                .font(.caption)
                .foregroundStyle(model.ffmpegStatus == "ffmpeg not found" ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: model.progress)
                .opacity(model.jobState == .idle ? 0.35 : 1)

            Text(model.ffmpegLog)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormRow("Format") {
                Picker("Format", selection: $model.settings.format) {
                    ForEach(OutputFormat.allCases.filter { $0.isImage == (model.inputKind == .image) }) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .onChange(of: model.settings.format) { _ in
                    model.normalizeSettingsAfterFormatChange()
                }

                Text(model.settings.format.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FormRow("Resolution") {
                Picker("Resolution", selection: $model.settings.resolution) {
                    ForEach(ResolutionOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.settings.format.isAudioOnly || model.jobState == .running)
            }

            FormRow("Output Name") {
                TextField("Output name", text: $model.settings.outputName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.jobState == .running)
            }

            FormRow("Destination") {
                Text(model.outputURL?.path ?? "Choose a source to set the destination.")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Change...") {
                    model.chooseOutput()
                }
                .disabled(model.inputURL == nil || model.jobState == .running)
            }

            Divider()

            FormRow("Target Size") {
                HStack(spacing: 8) {
                    TextField("Optional", text: $model.settings.targetSizeText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .disabled(model.jobState == .running || !model.settings.format.supportsTargetSize)

                    Picker("Unit", selection: $model.settings.targetSizeUnit) {
                        ForEach(SizeUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .disabled(model.jobState == .running || !model.settings.format.supportsTargetSize)
                }

                Text(model.targetSizeNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FormRow("Quality") {
                Slider(value: $model.settings.quality, in: 0...100, step: 1)
                    .disabled(model.jobState == .running || model.settings.targetSizeKB != nil || !model.settings.format.supportsQuality)

                HStack {
                    Text("Smaller")
                    Spacer()
                    Text("Higher Quality")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            statusLabel

            Spacer()

            if model.jobState == .running {
                Button("Cancel", role: .destructive) {
                    model.cancel()
                }
                .keyboardShortcut(.cancelAction)
            }

            if case .finished = model.jobState {
                Button {
                    model.revealOutput()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }

            Button {
                model.compress()
            } label: {
                Label(model.jobState == .running ? "Working..." : "Compress", systemImage: "arrow.down.forward.and.arrow.up.backward")
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(!model.canRun)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.jobState {
        case .finished:
            Label("Export complete", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(1)
        case .running:
            Label(model.statusText, systemImage: "gearshape.2")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .idle:
            if let validationMessage = model.validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Label(model.statusText, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SectionHeader: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct InfoRow: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FormRow<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)

                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

@main
struct SquishyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
