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

    /// PNG re-encodes without discarding data, so exporting to it converts rather than compresses.
    var isLossless: Bool { self == .imagePNG }

    var actionVerb: String { isLossless ? "Convert" : "Compress" }

    var progressVerb: String { isLossless ? "Converting" : "Compressing" }

    var actionSymbol: String {
        isLossless ? "arrow.triangle.2.circlepath" : "arrow.up.right.and.arrow.down.left"
    }
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

    var resolutionText: String? {
        guard let width, let height else { return nil }
        let fps = frameRate.map { " · \($0)" } ?? ""
        return "\(width)\u{00d7}\(height)\(fps)"
    }

    var audioText: String {
        guard let audioCodec else { return "No audio detected" }
        return "\(audioCodec.uppercased()) audio"
    }
}

enum ItemState: Equatable {
    case queued
    case running
    case finished(URL)
    case failed(String)
    case cancelled

    var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct MediaItem: Identifiable {
    let id = UUID()
    let url: URL
    let kind: SourceKind
    var outputName: String
    var metadata: MediaMetadata?
    var thumbnail: NSImage?
    var isLoadingDetails = true
    var fileSizeBytes: Int64?
    var creationDate: Date?
    var state: ItemState = .queued
    var progress: Double = 0
    var statusDetail = ""

    init(url: URL, kind: SourceKind) {
        self.url = url
        self.kind = kind
        self.outputName = "\(url.deletingPathExtension().lastPathComponent)-compressed"
    }

    var fileSizeText: String {
        guard let fileSizeBytes else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var creationDateText: String {
        guard let creationDate else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }

    /// The file this item produced, once it finished exporting.
    var producedURL: URL? {
        if case let .finished(url) = state { return url }
        return nil
    }
}

struct ConsoleEntry: Identifiable {
    enum Level {
        case info
        case success
        case error
    }

    let id = UUID()
    let date = Date()
    let level: Level
    let text: String

    var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// Collects a subprocess's stderr off the main thread so the tail can be shown if it fails.
final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        if text.count > 20_000 {
            text = String(text.suffix(10_000))
        }
        lock.unlock()
    }

    func tail(_ lines: Int = 6) -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(lines)
            .joined(separator: "\n")
    }
}

/// Thread-safe flag so a queued export running on a background queue can notice a cancel
/// request issued from the main actor.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

enum PrerequisiteInstallState: Equatable {
    case idle
    case installing
    case succeeded
    case failed(String)
}

@MainActor
final class CompressorModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var selectedItemID: UUID?
    @Published var settings = ExportSettings()
    @Published var isQueueRunning = false
    @Published var statusText = "Choose a source video to begin."
    @Published private(set) var consoleEntries: [ConsoleEntry] = []

    /// How many ffmpeg exports may run at the same time.
    let maxConcurrentJobs = 5

    @Published var youtubeURLText = ""
    @Published var youtubeKind: YouTubeDownloadKind = .video
    @Published var isDownloadingYouTube = false
    @Published var youtubeDownloadProgress: Double = 0
    @Published var youtubeDownloadStatus = "Paste a YouTube link to download."
    @Published var youtubeDownloadLog = ""
    @Published var youtubeDownloadElapsed: TimeInterval = 0

    @Published var isFetchingYoutubePreview = false
    @Published var youtubePreviewTitle: String?
    @Published var youtubePreviewDuration: Double?
    @Published var youtubePreviewThumbnail: NSImage?

    private var youtubeDownloadTimer: Timer?
    private var youtubePreviewDebounceTimer: Timer?
    private var youtubePreviewProcess: Process?
    private var youtubePreviewThumbnailTask: URLSessionDataTask?

    @Published var showUpdateAlert = false
    @Published var updateAlertTitle = "Update Available"
    @Published var updateAlertMessage = ""
    @Published var updateDownloadURL: URL?
    @Published var isCheckingForUpdates = false

    @Published var isYtDlpOutdated = false
    @Published var isUpdatingYtDlp = false
    @Published var ytDlpUpdateMessage: String?
    @Published var showYtDlpUpdateAlert = false
    @Published var ytDlpUpdateLog = ""
    @Published var ytDlpUpdateElapsed: TimeInterval = 0

    private var processes: [UUID: Process] = [:]
    private var cancellationFlags: [UUID: CancellationFlag] = [:]
    /// Destinations locked in when the queue starts, so renames can't shift them mid-run.
    private var plannedOutputs: [UUID: URL] = [:]
    private var youtubeProcess: Process?
    private var ytDlpUpdateProcess: Process?
    private var ytDlpUpdateTimer: Timer?
    private var prerequisiteInstallProcess: Process?

    @Published private(set) var ffmpegPath: String?
    @Published private(set) var ffprobePath: String?
    @Published private(set) var ytDlpPath: String?
    @Published private(set) var brewPath: String?
    @Published private(set) var ffmpegVersion: String?
    @Published private(set) var ytDlpVersion: String?
    @Published private(set) var brewVersion: String?
    @Published var prerequisiteInstallState: PrerequisiteInstallState = .idle
    @Published var prerequisiteInstallLog = ""

    private static let ytDlpUpdateExpectedSeconds: TimeInterval = 20

    init() {
        refreshPrerequisites()
        checkYtDlpFreshness()
    }

    var prerequisitesReady: Bool {
        ffmpegPath != nil && ffprobePath != nil && ytDlpPath != nil
    }

    var isInstallingPrerequisites: Bool {
        prerequisiteInstallState == .installing
    }

    func refreshPrerequisites() {
        let locatedBrewPath = ToolLocator.find("brew")
        let locatedFFmpegPath = ToolLocator.find("ffmpeg")
        let locatedFFprobePath = ToolLocator.find("ffprobe")
        let locatedYtDlpPath = ToolLocator.find("yt-dlp")

        let detectedBrewVersion = locatedBrewPath.flatMap {
            ToolLocator.version(at: $0, arguments: ["--version"])
        }
        let detectedFFmpegVersion = locatedFFmpegPath.flatMap {
            ToolLocator.version(at: $0, arguments: ["-version"])
        }
        let detectedFFprobeVersion = locatedFFprobePath.flatMap {
            ToolLocator.version(at: $0, arguments: ["-version"])
        }
        let detectedYtDlpVersion = locatedYtDlpPath.flatMap {
            ToolLocator.version(at: $0, arguments: ["--version"])
        }

        brewPath = detectedBrewVersion == nil ? nil : locatedBrewPath
        ffmpegPath = detectedFFmpegVersion == nil ? nil : locatedFFmpegPath
        ffprobePath = detectedFFprobeVersion == nil ? nil : locatedFFprobePath
        ytDlpPath = detectedYtDlpVersion == nil ? nil : locatedYtDlpPath
        brewVersion = detectedBrewVersion
        ffmpegVersion = detectedFFmpegVersion
        ytDlpVersion = detectedYtDlpVersion

        if ytDlpPath == nil {
            isYtDlpOutdated = false
        }
        if prerequisitesReady && !isInstallingPrerequisites,
           case .failed = prerequisiteInstallState {
            prerequisiteInstallState = .succeeded
        }
    }

    func installPrerequisites() {
        guard let brewPath else {
            prerequisiteInstallState = .failed("Homebrew must be installed before Squishy can install its media tools.")
            return
        }
        guard !isInstallingPrerequisites else { return }

        prerequisiteInstallState = .installing
        prerequisiteInstallLog = "$ brew install ffmpeg yt-dlp\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", "ffmpeg", "yt-dlp"]

        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = ([
            (brewPath as NSString).deletingLastPathComponent,
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ] + [existingPath]).joined(separator: ":")
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        prerequisiteInstallProcess = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.prerequisiteInstallLog += text
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            outputPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.prerequisiteInstallProcess = nil
                self.refreshPrerequisites()

                if terminatedProcess.terminationStatus == 0 && self.prerequisitesReady {
                    self.prerequisiteInstallState = .succeeded
                    self.prerequisiteInstallLog += "\nVerification passed. Squishy is ready.\n"
                    self.checkYtDlpFreshness()
                } else if terminatedProcess.terminationStatus == 0 {
                    self.prerequisiteInstallState = .failed("Homebrew finished, but one or more tools could not be verified. Check the log and try again.")
                } else {
                    self.prerequisiteInstallState = .failed("Homebrew exited with code \(terminatedProcess.terminationStatus). Check the log, then retry.")
                }
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            prerequisiteInstallProcess = nil
            prerequisiteInstallState = .failed(error.localizedDescription)
            prerequisiteInstallLog += "\n\(error.localizedDescription)\n"
        }
    }

    // MARK: - App updates

    var appVersion: String { UpdateChecker.currentVersion }

    /// Automatic checks run at most once a day; the menu item forces one and always reports back.
    func checkForAppUpdates(userInitiated: Bool) {
        if !userInitiated {
            let last = UserDefaults.standard.object(forKey: UpdateChecker.lastCheckDefaultsKey) as? Date
            if let last, Date().timeIntervalSince(last) < 86_400 { return }
        }
        guard !isCheckingForUpdates else { return }

        isCheckingForUpdates = true
        UserDefaults.standard.set(Date(), forKey: UpdateChecker.lastCheckDefaultsKey)

        UpdateChecker.fetchLatest { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCheckingForUpdates = false

                switch result {
                case let .success(release):
                    if UpdateChecker.isVersion(release.version, newerThan: self.appVersion) {
                        self.updateAlertTitle = "Update Available"
                        self.updateAlertMessage = "Squishy \(release.version) is available. You're running \(self.appVersion). Download the new version and drag it into Applications, replacing the old copy."
                        self.updateDownloadURL = release.pageURL
                        self.showUpdateAlert = true
                        self.log("Update available: \(release.version) (running \(self.appVersion)).")
                    } else if userInitiated {
                        self.updateAlertTitle = "You're Up to Date"
                        self.updateAlertMessage = "Squishy \(self.appVersion) is the latest version."
                        self.updateDownloadURL = nil
                        self.showUpdateAlert = true
                    }
                case let .failure(error):
                    self.log("Update check failed: \(error.localizedDescription)", level: .error)
                    if userInitiated {
                        self.updateAlertTitle = "Could Not Check for Updates"
                        self.updateAlertMessage = error.localizedDescription
                        self.updateDownloadURL = UpdateChecker.releasesPage
                        self.showUpdateAlert = true
                    }
                }
            }
        }
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
                    self.refreshPrerequisites()
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

    // MARK: - Queue contents

    var selectedItem: MediaItem? {
        guard let selectedItemID else { return items.first }
        return items.first { $0.id == selectedItemID } ?? items.first
    }

    /// The kind the queue as a whole is treated as: images only when every item is an image.
    var queueKind: SourceKind {
        items.allSatisfy { $0.kind == .image } && !items.isEmpty ? .image : .video
    }

    var runningCount: Int { items.filter { $0.state == .running }.count }
    var queuedCount: Int { items.filter { $0.state == .queued }.count }
    var finishedCount: Int { items.filter { $0.state.isFinished }.count }
    var failedCount: Int { items.filter { $0.state.isFailed }.count }

    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        let total = items.reduce(0.0) { $0 + ($1.state.isFinished ? 1 : $1.progress) }
        return total / Double(items.count)
    }

    var finishedOutputs: [URL] {
        items.compactMap { $0.producedURL }
    }

    /// Destination for every item, walked in queue order so that sources sharing a base
    /// name (`clip.png` and `clip.psd` both exporting to PNG, say) get numbered suffixes
    /// instead of overwriting each other.
    func resolvedOutputURLs() -> [UUID: URL] {
        let ext = settings.format.fileExtension
        var used = Set<String>()
        var result: [UUID: URL] = [:]

        for item in items {
            let base = Self.sanitized(item.outputName)
            guard !base.isEmpty else { continue }

            let folder = settings.outputFolder ?? item.url.deletingLastPathComponent()
            var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
            if candidate.standardizedFileURL == item.url.standardizedFileURL {
                candidate = folder.appendingPathComponent("\(base)-compressed").appendingPathExtension(ext)
            }

            // Compared case-insensitively because the default macOS volume is.
            var suffix = 2
            while !used.insert(candidate.standardizedFileURL.path.lowercased()).inserted {
                candidate = folder.appendingPathComponent("\(base) \(suffix)").appendingPathExtension(ext)
                suffix += 1
            }

            result[item.id] = candidate
        }

        return result
    }

    func outputURL(for item: MediaItem) -> URL? {
        resolvedOutputURLs()[item.id]
    }

    var validationMessage: String? {
        if ffmpegPath == nil { return "Install ffmpeg with Homebrew to enable exports." }
        if items.isEmpty { return "Choose or drop media files first." }
        if items.contains(where: { Self.sanitized($0.outputName).isEmpty }) { return "Every file needs an output name." }
        if settings.targetSizeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && settings.targetSizeKB == nil {
            return "Target size must be a whole number."
        }
        return nil
    }

    var canRun: Bool {
        validationMessage == nil && !isQueueRunning
    }

    var targetSizeNote: String {
        guard settings.targetSizeKB != nil else { return "Quality controls compression when no target size is set." }
        guard settings.format.supportsTargetSize else {
            return settings.format.isImage
                ? "PNG is lossless; target size is ignored."
                : "GIF ignores target size and uses animation defaults."
        }
        let value = settings.targetSizeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Approximate target per file: \(value) \(settings.targetSizeUnit.title)."
    }

    private static func sanitized(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .video, .audio, .image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            addInputs(panel.urls)
        }
    }

    func addInputs(_ urls: [URL]) {
        var addedIDs: [UUID] = []

        for url in urls {
            guard !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { continue }
            var item = MediaItem(url: url, kind: Self.sourceKind(for: url))
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            item.fileSizeBytes = attributes?[.size] as? Int64
            item.creationDate = attributes?[.creationDate] as? Date
            items.append(item)
            addedIDs.append(item.id)
        }

        guard !addedIDs.isEmpty else { return }

        if selectedItemID == nil || !items.contains(where: { $0.id == selectedItemID }) {
            selectedItemID = addedIDs.first
        }
        normalizeFormatForQueueKind()

        statusText = items.count == 1
            ? "Ready to export \(items[0].url.lastPathComponent)."
            : "\(items.count) files queued."
        log("Added \(addedIDs.count) file\(addedIDs.count == 1 ? "" : "s") to the queue.")

        for id in addedIDs {
            loadDetails(for: id)
        }
    }

    func removeItem(_ id: UUID) {
        cancelItem(id)
        items.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = items.first?.id
        }
        if items.isEmpty {
            statusText = ""
        }
        normalizeFormatForQueueKind()
    }

    func clearInput() {
        cancelAll()
        items.removeAll()
        selectedItemID = nil
        statusText = ""
        log("Cleared the queue.")
    }

    private func update(_ id: UUID, _ body: (inout MediaItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        body(&items[index])
    }

    private func loadDetails(for id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let url = item.url
        let kind = item.kind
        let ffprobePath = self.ffprobePath
        let ffmpegPath = self.ffmpegPath

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let metadata = MediaProbe.metadata(for: url, kind: kind, ffprobePath: ffprobePath)
            DispatchQueue.main.async {
                self?.update(id) { $0.metadata = metadata }
            }

            let thumbnail = MediaProbe.thumbnail(
                for: url,
                kind: kind,
                duration: metadata.duration,
                ffmpegPath: ffmpegPath
            )
            DispatchQueue.main.async {
                self?.update(id) {
                    $0.thumbnail = thumbnail
                    $0.isLoadingDetails = false
                }
            }
        }
    }

    private static func sourceKind(for url: URL) -> SourceKind {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .image) == true ? .image : .video
    }

    private func normalizeFormatForQueueKind() {
        guard !items.isEmpty else { return }
        if queueKind == .image, settings.format.isImage == false {
            settings.format = .imageJPEG
        } else if queueKind == .video, settings.format.isImage {
            settings.format = .mp4H264
        }
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where compressed files are saved."

        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url
        }
    }

    func useSourceFolders() {
        settings.outputFolder = nil
    }

    var destinationText: String {
        settings.outputFolder?.lastPathComponent ?? "Alongside originals"
    }

    func normalizeSettingsAfterFormatChange() {
        if settings.format.isAudioOnly {
            settings.resolution = .original
        }
    }

    // MARK: - Queue engine

    /// Queues every item and starts working through them, `maxConcurrentJobs` at a time.
    func compressAll() {
        guard ffmpegPath != nil, !items.isEmpty, !isQueueRunning else { return }

        for index in items.indices {
            items[index].state = .queued
            items[index].progress = 0
            items[index].statusDetail = ""
        }

        plannedOutputs = resolvedOutputURLs()
        isQueueRunning = true
        statusText = items.count == 1
            ? "\(settings.format.progressVerb) to \(settings.format.title)..."
            : "\(settings.format.progressVerb) \(items.count) files (\(maxConcurrentJobs) at a time)..."
        log("Starting \(items.count) job\(items.count == 1 ? "" : "s") · \(settings.format.title) · \(settings.resolution.title) · up to \(maxConcurrentJobs) at a time.")
        pumpQueue()
    }

    /// Starts as many queued items as the concurrency limit allows, and wraps the queue up
    /// once nothing is left to run.
    private func pumpQueue() {
        while runningCount < maxConcurrentJobs, let next = items.first(where: { $0.state == .queued }) {
            start(next.id)
        }

        if runningCount == 0 && queuedCount == 0 {
            let wasRunning = isQueueRunning
            isQueueRunning = false
            if items.contains(where: { $0.state == .cancelled }) {
                statusText = "Export cancelled."
            } else if failedCount > 0 {
                statusText = finishedCount > 0
                    ? "Finished \(finishedCount) of \(items.count); \(failedCount) failed."
                    : "Export failed."
            } else if finishedCount > 0 {
                statusText = finishedCount == 1 ? "Export complete." : "Exported \(finishedCount) files."
            }
            if wasRunning {
                log(
                    "Queue finished — \(finishedCount) succeeded, \(failedCount) failed.",
                    level: failedCount > 0 ? .error : .success
                )
            }
        }
    }

    private func start(_ id: UUID) {
        guard let ffmpegPath, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[index]

        guard item.kind == .image || settings.format.isImage == false else {
            items[index].state = .failed("Video sources can't use image formats.")
            log("\(item.url.lastPathComponent): video source can't use an image format.", level: .error)
            return
        }
        guard item.kind == .video || settings.format.isImage else {
            items[index].state = .failed("Image sources can't use video formats.")
            log("\(item.url.lastPathComponent): image source can't use a video format.", level: .error)
            return
        }
        guard let outputURL = plannedOutputs[id] ?? outputURL(for: item) else {
            items[index].state = .failed("Invalid output name.")
            log("\(item.url.lastPathComponent): invalid output name.", level: .error)
            return
        }

        items[index].state = .running
        items[index].progress = 0
        items[index].statusDetail = "Starting…"
        log("▶ \(item.url.lastPathComponent) → \(outputURL.lastPathComponent)")

        if settings.format.isImage, settings.format.supportsTargetSize, let targetKB = settings.targetSizeKB {
            startImageSizeSearch(id: id, item: item, outputURL: outputURL, targetBytes: targetKB * 1024, ffmpegPath: ffmpegPath)
        } else {
            startDirectExport(id: id, item: item, outputURL: outputURL, ffmpegPath: ffmpegPath)
        }
    }

    private func startDirectExport(id: UUID, item: MediaItem, outputURL: URL, ffmpegPath: String) {
        let plan = FFmpegPlan.make(settings: settings, metadata: item.metadata)
        var args = ["-hide_banner", "-y", "-i", item.url.path]
        args.append(contentsOf: plan.arguments)
        args.append(contentsOf: ["-progress", "pipe:1", "-nostats", outputURL.path])

        let duration = item.metadata?.duration

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args
        processes[id] = process

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consumeProgress(text, for: id, duration: duration)
            }
        }

        let errorLog = LogBuffer()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            errorLog.append(text)
        }

        let sourceName = item.url.lastPathComponent

        process.terminationHandler = { [weak self] process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.processes[id] = nil

                if self.cancellationFlags[id]?.isCancelled == true {
                    self.cancellationFlags[id] = nil
                    self.update(id) { $0.state = .cancelled; $0.progress = 0; $0.statusDetail = "" }
                    self.log("⏹ \(sourceName) cancelled.")
                } else if process.terminationStatus == 0 {
                    self.update(id) {
                        $0.progress = 1
                        $0.state = .finished(outputURL)
                        $0.statusDetail = ""
                    }
                    self.log("✔ \(outputURL.lastPathComponent) \(Self.savingsText(from: item.fileSizeBytes, to: outputURL))", level: .success)
                } else {
                    self.update(id) {
                        $0.state = .failed("ffmpeg exited with code \(process.terminationStatus)")
                        $0.statusDetail = ""
                    }
                    self.log("✖ \(sourceName): ffmpeg exited with code \(process.terminationStatus)", level: .error)
                    self.log(errorLog.tail(), level: .error)
                }

                self.pumpQueue()
            }
        }

        do {
            try process.run()
        } catch {
            processes[id] = nil
            update(id) { $0.state = .failed(error.localizedDescription) }
            log("✖ \(sourceName): \(error.localizedDescription)", level: .error)
            pumpQueue()
        }
    }

    /// "1,8 MB → 640 KB (−65%)" for the console, or just the output size if the input size is unknown.
    private static func savingsText(from inputBytes: Int64?, to outputURL: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        guard let outputBytes = attributes?[.size] as? Int64 else { return "" }
        let outputText = ByteCountFormatter.string(fromByteCount: outputBytes, countStyle: .file)

        guard let inputBytes, inputBytes > 0 else { return "· \(outputText)" }
        let inputText = ByteCountFormatter.string(fromByteCount: inputBytes, countStyle: .file)
        let change = Int(((Double(outputBytes) - Double(inputBytes)) / Double(inputBytes) * 100).rounded())
        let sign = change > 0 ? "+" : "−"
        return "· \(inputText) → \(outputText) (\(sign)\(abs(change))%)"
    }

    /// Binary-searches the quality scale for an image encode close to the requested size.
    private func startImageSizeSearch(id: UUID, item: MediaItem, outputURL: URL, targetBytes: Int, ffmpegPath: String) {
        let flag = CancellationFlag()
        cancellationFlags[id] = flag

        let baseSettings = settings
        let baseMetadata = item.metadata
        let inputURL = item.url
        let tempDir = FileManager.default.temporaryDirectory
        let trialURL = tempDir
            .appendingPathComponent("squishy-trial-\(id.uuidString)")
            .appendingPathExtension(baseSettings.format.fileExtension)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let maxIterations = 6
            var low = 1.0
            var high = 100.0
            var bestURL: URL?
            var bestDelta = Int.max

            for iteration in 0..<maxIterations {
                if flag.isCancelled { break }

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
                        guard let self else { return }
                        self.cancellationFlags[id] = nil
                        self.update(id) { $0.state = .failed(error.localizedDescription) }
                        self.pumpQueue()
                    }
                    return
                }
                DispatchQueue.main.async { self?.processes[id] = process }
                process.waitUntilExit()
                DispatchQueue.main.async { self?.processes[id] = nil }

                if flag.isCancelled { break }

                guard let attributes = try? FileManager.default.attributesOfItem(atPath: trialURL.path),
                      let fileSize = attributes[.size] as? Int else { continue }

                let delta = abs(fileSize - targetBytes)
                if delta < bestDelta {
                    bestDelta = delta
                    if let bestURL {
                        try? FileManager.default.removeItem(at: bestURL)
                    }
                    let candidateURL = tempDir
                        .appendingPathComponent("squishy-best-\(UUID().uuidString)")
                        .appendingPathExtension(baseSettings.format.fileExtension)
                    try? FileManager.default.copyItem(at: trialURL, to: candidateURL)
                    bestURL = candidateURL
                }

                let progressFraction = Double(iteration + 1) / Double(maxIterations)
                let sizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                DispatchQueue.main.async {
                    self?.update(id) {
                        $0.progress = min(progressFraction * 0.99, 0.99)
                        $0.statusDetail = "Quality \(Int(trialQuality)) · \(sizeText)"
                    }
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
                guard let self else { return }
                self.cancellationFlags[id] = nil
                self.processes[id] = nil

                if flag.isCancelled {
                    bestURL.map { try? FileManager.default.removeItem(at: $0) }
                    self.update(id) { $0.state = .cancelled; $0.progress = 0; $0.statusDetail = "" }
                    self.pumpQueue()
                    return
                }

                guard let bestURL else {
                    self.update(id) { $0.state = .failed("Could not produce an output near the target size.") }
                    self.pumpQueue()
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        try FileManager.default.removeItem(at: outputURL)
                    }
                    try FileManager.default.copyItem(at: bestURL, to: outputURL)
                    try? FileManager.default.removeItem(at: bestURL)
                    self.update(id) {
                        $0.progress = 1
                        $0.state = .finished(outputURL)
                        $0.statusDetail = ""
                    }
                    self.log("✔ \(outputURL.lastPathComponent) \(Self.savingsText(from: item.fileSizeBytes, to: outputURL))", level: .success)
                } catch {
                    self.update(id) { $0.state = .failed(error.localizedDescription) }
                    self.log("✖ \(item.url.lastPathComponent): \(error.localizedDescription)", level: .error)
                }

                self.pumpQueue()
            }
        }
    }

    func cancelItem(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item.state {
        case .queued:
            update(id) { $0.state = .cancelled; $0.progress = 0 }
        case .running:
            let flag = cancellationFlags[id] ?? CancellationFlag()
            cancellationFlags[id] = flag
            flag.cancel()
            processes[id]?.terminate()
        default:
            break
        }
    }

    func cancelAll() {
        for item in items where item.state == .queued {
            update(item.id) { $0.state = .cancelled; $0.progress = 0 }
        }
        for item in items where item.state == .running {
            cancelItem(item.id)
        }
        statusText = "Export cancelled."
        log("Cancelled the queue.")
        pumpQueue()
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

    /// A file drop that lands inside the URL field arrives as plain text. Recognise those
    /// paths and route them into the queue instead of treating them as a link.
    @discardableResult
    func consumeDroppedFilePaths() -> Bool {
        let text = youtubeURLText
        guard text.contains("/") else { return false }

        var candidates = text.split(whereSeparator: \.isNewline).map(String.init)
        if candidates.isEmpty { candidates = [text] }

        let urls: [URL] = candidates.compactMap { candidate in
            var path = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("file://") {
                guard let url = URL(string: path) else { return nil }
                path = url.path
            }
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
            return URL(fileURLWithPath: path)
        }

        guard !urls.isEmpty else { return false }

        youtubeURLText = ""
        addInputs(urls)
        return true
    }

    func scheduleYoutubePreviewFetch() {
        youtubePreviewDebounceTimer?.invalidate()
        youtubePreviewProcess?.terminate()
        youtubePreviewProcess = nil
        youtubePreviewThumbnailTask?.cancel()
        youtubePreviewThumbnailTask = nil
        isFetchingYoutubePreview = false

        let trimmed = Self.normalizedYouTubeURLText(youtubeURLText)
        guard isValidYouTubeURL(trimmed) else {
            youtubePreviewTitle = nil
            youtubePreviewDuration = nil
            youtubePreviewThumbnail = nil
            return
        }

        youtubePreviewDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.fetchYoutubePreview(for: trimmed)
            }
        }
    }

    private func fetchYoutubePreview(for urlString: String) {
        guard let ytDlpPath else { return }

        isFetchingYoutubePreview = true
        youtubePreviewTitle = nil
        youtubePreviewDuration = nil
        youtubePreviewThumbnail = nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlpPath)
        process.arguments = [
            "--no-playlist", "--skip-download",
            "--print", "%(title)s",
            "--print", "%(duration)s",
            "--print", "%(thumbnail)s",
            urlString
        ]

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        youtubePreviewProcess = process

        process.terminationHandler = { [weak self] terminatedProcess in
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let lines = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .map(String.init) ?? []

            DispatchQueue.main.async {
                guard let self else { return }
                self.youtubePreviewProcess = nil
                self.isFetchingYoutubePreview = false

                guard terminatedProcess.terminationStatus == 0, lines.count >= 3 else { return }

                self.youtubePreviewTitle = lines[0]
                self.youtubePreviewDuration = Double(lines[1])

                if let thumbnailURL = URL(string: lines[2]) {
                    self.loadYoutubePreviewThumbnail(from: thumbnailURL)
                }
            }
        }

        do {
            try process.run()
        } catch {
            isFetchingYoutubePreview = false
        }
    }

    private func loadYoutubePreviewThumbnail(from url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.youtubePreviewThumbnail = image
            }
        }
        youtubePreviewThumbnailTask = task
        task.resume()
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
        log("Downloading \(youtubeKind == .video ? "video" : "audio") with yt-dlp…")

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
                    self.scheduleYoutubePreviewFetch()
                    self.log("✔ Downloaded \(newFile.lastPathComponent).", level: .success)
                    self.addInputs([newFile])
                } else {
                    let lastLine = self.youtubeDownloadLog
                        .split(separator: "\n")
                        .map(String.init)
                        .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    self.youtubeDownloadStatus = lastLine.map { "Download failed: \($0)" } ?? "Download failed."
                    self.log("✖ Download failed. \(lastLine ?? "")", level: .error)
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
        let outputs = finishedOutputs
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }

    private func consumeProgress(_ text: String, for id: UUID, duration: Double?) {
        for line in text.split(separator: "\n") {
            if line.hasPrefix("out_time_ms="),
               let raw = Double(line.replacingOccurrences(of: "out_time_ms=", with: "")),
               let duration,
               duration > 0 {
                let fraction = min(max((raw / 1_000_000) / duration, 0), 0.99)
                update(id) {
                    $0.progress = fraction
                    $0.statusDetail = "\(Int(fraction * 100))%"
                }
            }

            if line == "progress=end" {
                update(id) { $0.progress = 1 }
            }
        }
    }

    // MARK: - Console

    func log(_ text: String, level: ConsoleEntry.Level = .info) {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            consoleEntries.append(ConsoleEntry(level: level, text: trimmed))
        }
        if consoleEntries.count > 500 {
            consoleEntries.removeFirst(consoleEntries.count - 500)
        }
    }

    func clearConsole() {
        consoleEntries.removeAll()
    }

    var consoleText: String {
        consoleEntries.map { "[\($0.timeText)] \($0.text)" }.joined(separator: "\n")
    }

    var consoleErrorCount: Int {
        consoleEntries.filter { $0.level == .error }.count
    }

}

/// Metadata and thumbnail extraction. Runs off the main thread so queueing many files at
/// once doesn't stall the UI while ffprobe walks each one.
enum MediaProbe {
    static func metadata(for url: URL, kind: SourceKind, ffprobePath: String?) -> MediaMetadata {
        if kind == .image {
            return imageMetadata(for: url)
        }

        func stream(_ entry: String, selector: String = "v:0") -> String? {
            probeValue(for: url, ffprobePath: ffprobePath, arguments: [
                "-select_streams", selector,
                "-show_entries", "stream=\(entry)",
                "-of", "default=noprint_wrappers=1:nokey=1"
            ])
        }

        return MediaMetadata(
            duration: probeValue(for: url, ffprobePath: ffprobePath, arguments: [
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1"
            ]).flatMap(Double.init),
            videoCodec: stream("codec_name"),
            width: Int(stream("width") ?? ""),
            height: Int(stream("height") ?? ""),
            frameRate: normalizedFrameRate(stream("avg_frame_rate")),
            audioCodec: stream("codec_name", selector: "a:0")
        )
    }

    static func thumbnail(for url: URL, kind: SourceKind, duration: Double?, ffmpegPath: String?) -> NSImage? {
        if kind == .image {
            return NSImage(contentsOf: url)
        }
        guard let ffmpegPath else { return nil }

        let seconds = (duration ?? 0) > 1 ? min((duration ?? 0) * 0.1, 5) : 0
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("squishy-thumb-\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-hide_banner", "-y",
            "-ss", "\(seconds)",
            "-i", url.path,
            "-frames:v", "1",
            "-q:v", "3",
            tempURL.path
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        let image = NSImage(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return image
    }

    private static func imageMetadata(for url: URL) -> MediaMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return MediaMetadata()
        }

        let formatName = (CGImageSourceGetType(source) as String?)
            .flatMap { UTType($0)?.preferredFilenameExtension }?
            .uppercased()

        return MediaMetadata(
            duration: nil,
            videoCodec: formatName,
            width: properties[kCGImagePropertyPixelWidth] as? Int,
            height: properties[kCGImagePropertyPixelHeight] as? Int,
            frameRate: nil,
            audioCodec: nil
        )
    }

    private static func probeValue(for url: URL, ffprobePath: String?, arguments: [String]) -> String? {
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

    private static func normalizedFrameRate(_ value: String?) -> String? {
        guard let value, value != "0/0" else { return nil }
        let parts = value.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return value }
        let fps = parts[0] / parts[1]
        return fps.rounded() == fps ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps)
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
            args.append(contentsOf: ["-frames:v", "1", "-update", "1"])
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
    var fontSize: CGFloat = 13

    init(_ placeholder: String, text: Binding<String>, fontSize: CGFloat = 13) {
        self.placeholder = placeholder
        self._text = text
        self.fontSize = fontSize
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: fontSize)
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingHead
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        // Without this the field swallows dropped files as text instead of letting the
        // drop fall through to the window's file queue.
        field.unregisterDraggedTypes()
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
            // The shared field editor re-registers drag types whenever it takes over a
            // field, so files dropped while editing would land here as text.
            editor.unregisterDraggedTypes()
        }
    }
}

extension Notification.Name {
    static let squishyCheckForUpdates = Notification.Name("squishyCheckForUpdates")
}

/// Compares the running bundle against the newest GitHub release. Deliberately dependency
/// free: it only reads the releases API and hands the user off to the download page, so
/// there is no framework to embed and no update signing key to manage.
enum UpdateChecker {
    static let repository = "vincent-caetano/Squishy-Media-Manager"
    static let lastCheckDefaultsKey = "lastUpdateCheckDate"

    static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    static var releasesPage: URL {
        URL(string: "https://github.com/\(repository)/releases/latest")!
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Release {
        let version: String
        let pageURL: URL
    }

    static func fetchLatest(completion: @escaping (Result<Release, Error>) -> Void) {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                completion(.failure(URLError(.cannotParseResponse)))
                return
            }

            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            completion(.success(Release(version: version, pageURL: page)))
        }.resume()
    }

    /// Numeric, component-wise comparison so 0.10.0 correctly beats 0.9.0.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}

enum ToolLocator {
    static func find(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/\(name)" }
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
            "\(home)/.nix-profile/bin/\(name)",
            "/run/current-system/sw/bin/\(name)",
            "/opt/homebrew/opt/\(name)/bin/\(name)",
            "/usr/local/opt/\(name)/bin/\(name)"
        ] + pathCandidates

        var visited = Set<String>()
        for path in candidates {
            guard visited.insert(path).inserted else { continue }
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    static func version(at path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n", maxSplits: 1)
            .first
            .map(String.init)
    }
}

struct PrerequisiteOnboardingView: View {
    @ObservedObject var model: CompressorModel
    let isRecovery: Bool
    let onComplete: () -> Void

    private let homebrewInstallCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    prerequisiteStep(
                        number: 1,
                        title: "Homebrew",
                        detail: "Homebrew securely manages the command-line tools Squishy depends on."
                    ) {
                        homebrewContent
                    }
                    prerequisiteStep(
                        number: 2,
                        title: "Media tools",
                        detail: "FFmpeg handles media conversion, while yt-dlp enables YouTube downloads."
                    ) {
                        mediaToolsContent
                    }
                    prerequisiteStep(
                        number: 3,
                        title: "Verification",
                        detail: "Squishy launches each tool and checks that it responds before setup can finish."
                    ) {
                        verificationContent
                    }
                }
                .padding(28)
            }

            Divider()

            HStack {
                if model.brewPath != nil && !model.prerequisitesReady {
                    Button("Verify Again") {
                        model.refreshPrerequisites()
                    }
                    .disabled(model.isInstallingPrerequisites)
                }

                Spacer()

                Button("Check for Updates…") {
                    model.checkForAppUpdates(userInitiated: true)
                }
                .disabled(model.isCheckingForUpdates)

                Button("Start Using Squishy") {
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!model.prerequisitesReady || model.isInstallingPrerequisites)
            }
            .padding(20)
        }
        .frame(width: 650, height: 640)
        .interactiveDismissDisabled(!model.prerequisitesReady)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: model.prerequisitesReady ? "checkmark.seal.fill" : "wand.and.stars")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(model.prerequisitesReady ? .green : Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.prerequisitesReady ? "Squishy is ready" : (isRecovery ? "Squishy needs a quick check" : "Welcome to Squishy"))
                    .font(.largeTitle.bold())

                Text(model.prerequisitesReady
                     ? "All required tools are installed and responding correctly."
                     : "Complete these three steps once, then Squishy will be ready to compress and download media.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func prerequisiteStep<Content: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var homebrewContent: some View {
        if let brewPath = model.brewPath {
            requirementRow(
                title: "Homebrew",
                detail: model.brewVersion ?? brewPath,
                isReady: true
            )
        } else if model.prerequisitesReady {
            requirementRow(
                title: "Homebrew not required",
                detail: "The required tools were found through another package manager.",
                isReady: true
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Homebrew was not found", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text("Open Terminal, paste this official installation command, and follow its prompts:")
                    .font(.callout)

                Text(homebrewInstallCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))

                HStack {
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(homebrewInstallCommand, forType: .string)
                    }
                    Button("Open Terminal") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    }
                    Button("Check Again") {
                        model.refreshPrerequisites()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaToolsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            requirementRow(
                title: "FFmpeg and ffprobe",
                detail: model.ffmpegVersion ?? "Not installed or not responding",
                isReady: model.ffmpegPath != nil && model.ffprobePath != nil
            )
            requirementRow(
                title: "yt-dlp",
                detail: model.ytDlpVersion ?? "Not installed or not responding",
                isReady: model.ytDlpPath != nil
            )

            if model.brewPath != nil && !model.prerequisitesReady {
                Button {
                    model.installPrerequisites()
                } label: {
                    Label(model.isInstallingPrerequisites ? "Installing…" : "Install Required Tools", systemImage: "arrow.down.circle")
                }
                .controlSize(.large)
                .disabled(model.isInstallingPrerequisites)
            }

            if model.isInstallingPrerequisites {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if !model.prerequisiteInstallLog.isEmpty {
                ScrollView {
                    Text(model.prerequisiteInstallLog)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(8)
                }
                .frame(height: 90)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            }

            if case let .failed(message) = model.prerequisiteInstallState {
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var verificationContent: some View {
        requirementRow(
            title: model.prerequisitesReady ? "All checks passed" : "Waiting for required tools",
            detail: model.prerequisitesReady
                ? "Compression and YouTube downloads are enabled."
                : "Install the missing items above, then run verification again.",
            isReady: model.prerequisitesReady
        )
    }

    private func requirementRow(title: String, detail: String, isReady: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isReady ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Gathers URLs from concurrent drop callbacks while preserving the drop order.
private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL?]

    init(count: Int) {
        storage = [URL?](repeating: nil, count: count)
    }

    func store(_ url: URL, at index: Int) {
        lock.lock()
        storage[index] = url
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { $0 }
    }
}

/// Scrollback of everything the queue has done, reachable by clicking the status strip.
struct ConsoleView: View {
    @ObservedObject var model: CompressorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Text(model.consoleErrorCount > 0
                     ? "\(model.consoleEntries.count) entries · \(model.consoleErrorCount) errors"
                     : "\(model.consoleEntries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if model.consoleEntries.isEmpty {
                            Text("Nothing logged yet.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }

                        ForEach(model.consoleEntries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.timeText)
                                    .foregroundStyle(.tertiary)
                                Text(entry.text)
                                    .foregroundStyle(color(for: entry.level))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.consoleEntries.count) {
                    if let last = model.consoleEntries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = model.consoleEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            HStack {
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.consoleText, forType: .string)
                }
                .disabled(model.consoleEntries.isEmpty)

                Button("Clear") {
                    model.clearConsole()
                }
                .disabled(model.consoleEntries.isEmpty)

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 460)
    }

    private func color(for level: ConsoleEntry.Level) -> Color {
        switch level {
        case .info: return .primary
        case .success: return .green
        case .error: return .red
        }
    }
}

private enum CompressionControl: String, CaseIterable, Identifiable {
    case quality = "Quality"
    case targetSize = "Target Size"

    var id: String { rawValue }
}

private extension Color {
    static let squishyBlue = Color(red: 0.20, green: 0.47, blue: 1.0)
    static let squishyField = Color.black.opacity(0.04)
    static let squishyBorder = Color.black.opacity(0.08)
}

struct ContentView: View {
    @StateObject private var model = CompressorModel()
    @AppStorage("hasCompletedPrerequisiteOnboarding") private var hasCompletedPrerequisiteOnboarding = false
    @State private var isDropTargeted = false
    @State private var showPrerequisiteOnboarding = false
    @State private var showConsole = false
    @State private var compressionControl: CompressionControl = .quality

    private let panelWidth: CGFloat = 422
    private let panelHeight: CGFloat = 724

    var body: some View {
        HStack(spacing: 0) {
            sourcePanel
                .frame(width: panelWidth, height: panelHeight)

            if !model.items.isEmpty {
                exportPanel
                    .frame(width: panelWidth, height: panelHeight)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: model.items.isEmpty ? panelWidth : panelWidth * 2, height: panelHeight)
        .background(Color.white)
        .preferredColorScheme(.light)
        .tint(.squishyBlue)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.squishyBlue, lineWidth: 2)
                .padding(4)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onAppear {
            model.refreshPrerequisites()
            showPrerequisiteOnboarding = !hasCompletedPrerequisiteOnboarding || !model.prerequisitesReady
            model.checkForAppUpdates(userInitiated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .squishyCheckForUpdates)) { _ in
            model.checkForAppUpdates(userInitiated: true)
        }
        .alert(model.updateAlertTitle, isPresented: $model.showUpdateAlert) {
            if let url = model.updateDownloadURL {
                Button("Download") { NSWorkspace.shared.open(url) }
                Button("Later", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(model.updateAlertMessage)
        }
        .sheet(isPresented: $showPrerequisiteOnboarding) {
            PrerequisiteOnboardingView(
                model: model,
                isRecovery: hasCompletedPrerequisiteOnboarding,
                onComplete: {
                    hasCompletedPrerequisiteOnboarding = true
                    showPrerequisiteOnboarding = false
                }
            )
        }
        .sheet(isPresented: $showConsole) {
            ConsoleView(model: model)
        }
        .alert("yt-dlp Update Available", isPresented: $model.showYtDlpUpdateAlert) {
            Button("Update Now") { model.updateYtDlp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text(model.ytDlpUpdateMessage ?? "Your yt-dlp version is older than 90 days. Update it to keep YouTube downloads working.")
        }
    }

    // MARK: - Source panel

    private var sourcePanel: some View {
        VStack(spacing: 0) {
            sourceHeader

            VStack(spacing: 0) {
                Group {
                    if !model.items.isEmpty {
                        selectedFileContent
                    } else if model.youtubePreviewTitle != nil || model.isFetchingYoutubePreview || !model.youtubeURLText.isEmpty {
                        youtubeContent
                    } else {
                        emptySourceContent
                    }
                }

                Spacer(minLength: 16)
                statusStrip
            }
            .padding(16)
        }
        .background(Color.white)
    }

    private var sourceHeader: some View {
        HStack(spacing: 16) {
            if model.items.count > 1 {
                Text("\(model.items.count) files")
                    .font(.system(.body, design: .rounded, weight: .bold))
            }

            Spacer()

            if !model.items.isEmpty {
                compactIconButton("trash", help: "Remove all files") {
                    model.clearInput()
                }
            }

            compactIconButton("plus", help: "Add media") {
                model.chooseInput()
            }

            if !model.items.isEmpty {
                compactIconButton("gear", help: "Check requirements") {
                    model.refreshPrerequisites()
                    showPrerequisiteOnboarding = true
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func compactIconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.squishyBlue)
        .help(help)
    }

    private var emptySourceContent: some View {
        VStack(spacing: 32) {
            Button {
                model.chooseInput()
            } label: {
                VStack(spacing: 16) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 72, weight: .regular))
                        .foregroundStyle(Color.squishyBlue)

                    VStack(spacing: 4) {
                        Text("Drop media here")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("or click to choose a file")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 284)
            .background(Color.squishyField)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            youtubeURLField
        }
    }

    private var youtubeContent: some View {
        VStack(spacing: 16) {
            youtubeURLField

            if model.isFetchingYoutubePreview {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Fetching video info…")
                        .font(.system(.callout, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else if model.youtubePreviewTitle != nil {
                youtubePreview
            } else if let hint = model.youtubeURLValidationHint {
                Label(hint, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.isDownloadingYouTube {
                ProgressView(value: model.youtubeDownloadProgress > 0 ? model.youtubeDownloadProgress : nil)
                    .progressViewStyle(.linear)

                Button("Cancel Download", role: .destructive) {
                    model.cancelYouTubeDownload()
                }
                .controlSize(.small)
            }
        }
    }

    private var youtubeURLField: some View {
        PlainTextField("Paste a URL", text: $model.youtubeURLText, fontSize: 16)
            .frame(height: 22)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.squishyField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.squishyBorder, lineWidth: 1)
            }
            .disabled(model.isDownloadingYouTube)
            .onChange(of: model.youtubeURLText) {
                guard !model.consumeDroppedFilePaths() else { return }
                model.scheduleYoutubePreviewFetch()
            }
    }

    private var youtubePreview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.88))

                if let thumbnail = model.youtubePreviewThumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(spacing: 8) {
                Text(model.youtubePreviewTitle ?? "")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let duration = model.youtubePreviewDuration {
                    Text(durationText(duration))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                downloadButton(title: "Download Video", symbol: "video", kind: .video, prominent: true)
                downloadButton(title: "Download Audio", symbol: "waveform.mid", kind: .audioOnly, prominent: false)
            }
        }
    }

    private func downloadButton(
        title: String,
        symbol: String,
        kind: YouTubeDownloadKind,
        prominent: Bool
    ) -> some View {
        Button {
            model.youtubeKind = kind
            model.downloadYouTube()
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(.body, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(prominent ? Color.squishyBlue : Color.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.canDownloadYouTube)
        .opacity(model.canDownloadYouTube ? 1 : 0.55)
    }

    @ViewBuilder
    private var selectedFileContent: some View {
        VStack(spacing: 16) {
            youtubeURLField

            if model.items.count == 1, let item = model.items.first {
                filePreview(item)
            } else {
                queueList
            }
        }
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(model.items) { item in
                    queueRow(item)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func queueRow(_ item: MediaItem) -> some View {
        let isSelected = model.selectedItem?.id == item.id

        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.88))

                    if let thumbnail = item.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if item.isLoadingDetails {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: item.kind == .image ? "photo" : "film")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 62, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent)
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(rowSubtitle(item))
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(rowSubtitleColor(item))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                stateBadge(item)

                Button {
                    model.removeItem(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            }

            if item.state == .running {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.squishyBlue.opacity(0.1) : Color.squishyField)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.squishyBlue.opacity(0.5) : Color.squishyBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { model.selectedItemID = item.id }
        .contextMenu {
            if case let .finished(url) = item.state {
                Button("Reveal Output") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            if item.state == .running || item.state == .queued {
                Button("Cancel", role: .destructive) { model.cancelItem(item.id) }
            }
            Button("Remove", role: .destructive) { model.removeItem(item.id) }
        }
    }

    private func rowSubtitle(_ item: MediaItem) -> String {
        switch item.state {
        case .running:
            let verb = model.settings.format.progressVerb
            return item.statusDetail.isEmpty ? "\(verb)…" : "\(verb) · \(item.statusDetail)"
        case .queued:
            return model.isQueueRunning ? "Waiting…" : baseSubtitle(item)
        case let .finished(url):
            return "Saved as \(url.lastPathComponent)"
        case let .failed(message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }

    private func baseSubtitle(_ item: MediaItem) -> String {
        var parts = [item.fileSizeText]
        if let duration = item.metadata?.duration, duration > 0 {
            parts.append(item.metadata?.durationText ?? "")
        }
        if let resolution = item.metadata?.resolutionText {
            parts.append(resolution)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func rowSubtitleColor(_ item: MediaItem) -> Color {
        switch item.state {
        case .failed: return .red
        case .finished: return .green
        default: return .secondary
        }
    }

    @ViewBuilder
    private func stateBadge(_ item: MediaItem) -> some View {
        switch item.state {
        case .queued:
            Image(systemName: model.isQueueRunning ? "clock" : "circle.dashed")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func filePreview(_ item: MediaItem) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.88))

                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if item.isLoadingDetails {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: item.kind == .image ? "photo" : "film")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(item.url.lastPathComponent)
                .font(.system(.body, design: .rounded, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                if let duration = item.metadata?.duration, duration > 0 {
                    Text(item.metadata?.durationText ?? "—")
                    Text("|").foregroundStyle(Color.black.opacity(0.24))
                }
                Text(item.fileSizeText)
            }
            .font(.system(.body, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                metadataRow("Resolution", item.metadata?.resolutionText ?? "—")
                metadataRow("Date Created", item.creationDateText)
                metadataRow("Format", item.metadata?.videoCodec?.uppercased() ?? model.settings.format.title)
                metadataRow("Audio", item.kind == .image ? "No audio" : (item.metadata?.audioText ?? "—"))
            }
            .padding(12)
            .background(Color.squishyField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Text(">  \(statusText)")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { showConsole = true }
        .help("Show console")
        .contextMenu {
            Button("Show Console") { showConsole = true }
            Button("Check for Updates…") { model.checkForAppUpdates(userInitiated: true) }
            Button("Check Requirements…") {
                model.refreshPrerequisites()
                showPrerequisiteOnboarding = true
            }
            if !model.items.isEmpty {
                Button("Remove All Sources", role: .destructive) { model.clearInput() }
            }
            if !model.finishedOutputs.isEmpty {
                Button("Reveal Output") { model.revealOutput() }
            }
        }
    }

    private var statusText: String {
        if model.isDownloadingYouTube { return "Downloading" }
        if model.isQueueRunning {
            let done = model.finishedCount + model.failedCount
            return model.items.count > 1
                ? "\(done)/\(model.items.count) done · \(model.runningCount) running"
                : model.statusText
        }
        if !model.items.isEmpty { return model.statusText.isEmpty ? "Ready" : model.statusText }
        if !model.youtubeDownloadStatus.isEmpty, !model.youtubeURLText.isEmpty { return model.youtubeDownloadStatus }
        return model.prerequisitesReady ? "Ready" : "Requirements missing"
    }

    private var statusColor: Color {
        if model.isDownloadingYouTube || model.isQueueRunning { return .squishyBlue }
        if model.failedCount > 0 { return .red }
        if model.finishedCount > 0 { return .green }
        return model.prerequisitesReady ? .squishyBlue : .orange
    }

    // MARK: - Export panel

    private var exportPanel: some View {
        VStack(spacing: 0) {
            exportHeader

            VStack(spacing: 32) {
                exportFields
                compressionControls
                Spacer(minLength: 0)
                exportFooter
            }
            .padding(16)
        }
        .background(Color(white: 0.98))
    }

    private var exportHeader: some View {
        HStack(spacing: 16) {
            Text(model.items.count > 1
                 ? "\(model.settings.format.actionVerb) \(model.items.count) Files"
                 : model.settings.format.actionVerb)
                .font(.system(.body, design: .rounded, weight: .bold))
            Spacer()

            if model.isQueueRunning {
                compactIconButton("xmark", help: "Cancel all exports") { model.cancelAll() }
            } else if !model.finishedOutputs.isEmpty {
                compactIconButton("folder", help: "Reveal outputs") { model.revealOutput() }
            }

            compactIconButton("plus", help: "Add more files") { model.chooseInput() }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    /// Output names are per file, so the field edits whichever queue row is selected.
    private var selectedNameBinding: Binding<String> {
        Binding(
            get: { model.selectedItem?.outputName ?? "" },
            set: { newValue in
                guard let id = model.selectedItem?.id,
                      let index = model.items.firstIndex(where: { $0.id == id }) else { return }
                model.items[index].outputName = newValue
            }
        )
    }

    private var exportFields: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Name")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.items.count > 1 {
                        Text("Selected file")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Output name", text: selectedNameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.squishyField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.squishyBorder, lineWidth: 1)
                    }
                    .disabled(model.isQueueRunning)
            }

            pickerRow("Destination") {
                Menu {
                    Button("Alongside Originals") { model.useSourceFolders() }
                    Button("Choose Folder…") { model.chooseDestinationFolder() }
                } label: {
                    Text(model.destinationText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 175)
                .disabled(model.isQueueRunning)
            }

            pickerRow("Format") {
                Picker("", selection: $model.settings.format) {
                    ForEach(OutputFormat.allCases.filter { $0.isImage == (model.queueKind == .image) }) { format in
                        Text(format.title).tag(format)
                    }
                }
                .onChange(of: model.settings.format) { model.normalizeSettingsAfterFormatChange() }
                .frame(width: 145)
                .disabled(model.isQueueRunning)
            }

            pickerRow("Resolution") {
                Picker("", selection: $model.settings.resolution) {
                    ForEach(ResolutionOption.allCases) { option in
                        Text(option.title.uppercased()).tag(option)
                    }
                }
                .frame(width: 130)
                .disabled(model.settings.format.isAudioOnly || model.isQueueRunning)
            }
        }
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            content()
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var compressionControls: some View {
        if model.settings.format.isLossless {
            losslessNote
        } else {
            qualityControls
        }
    }

    private var losslessNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.squishyBlue)

            Text("\(model.settings.format.title) is lossless, so there is nothing to compress — files are converted at full quality. Pick JPEG or WebP to trade quality for a smaller file.")
                .font(.system(.callout, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.squishyField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var qualityControls: some View {
        VStack(spacing: 16) {
            Picker("Compression control", selection: $compressionControl) {
                ForEach(CompressionControl.allCases) { control in
                    Text(control.rawValue).tag(control)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: compressionControl) { _, control in
                if control == .quality {
                    model.settings.targetSizeText = ""
                }
            }

            if compressionControl == .quality {
                VStack(spacing: 8) {
                    HStack {
                        Text("Quality")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.settings.quality))%")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.system(.body, design: .rounded, weight: .medium))

                    Slider(value: $model.settings.quality, in: 0...100, step: 1)
                        .disabled(model.isQueueRunning || !model.settings.format.supportsQuality)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target size (optional)")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        TextField("e.g. 25", text: $model.settings.targetSizeText)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.squishyField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.squishyBorder, lineWidth: 1)
                            }

                        Picker("Unit", selection: $model.settings.targetSizeUnit) {
                            ForEach(SizeUnit.allCases) { unit in
                                Text(unit.title).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 102)
                    }
                    .disabled(model.isQueueRunning || !model.settings.format.supportsTargetSize)
                }
            }
        }
    }

    private var exportFooter: some View {
        VStack(spacing: 10) {
            if model.isQueueRunning {
                VStack(spacing: 6) {
                    ProgressView(value: model.overallProgress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(model.finishedCount + model.failedCount) of \(model.items.count) done")
                        Spacer()
                        Text("\(model.runningCount) running · \(model.queuedCount) waiting")
                    }
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            } else if let validationMessage = model.validationMessage, !model.items.isEmpty {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if model.isQueueRunning {
                Button("Cancel", role: .destructive) { model.cancelAll() }
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    model.compressAll()
                } label: {
                    Label(
                        model.items.count > 1
                            ? "\(model.settings.format.actionVerb) \(model.items.count) Files"
                            : model.settings.format.actionVerb,
                        systemImage: model.settings.format.actionSymbol
                    )
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Color.squishyBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRun)
                .opacity(model.canRun ? 1 : 0.55)
            }
        }
    }

    private func durationText(_ duration: Double) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Collects every dropped file URL and adds them to the queue in the order they were dropped.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let collector = DroppedURLCollector(count: providers.count)

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.store(url, at: index)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            model.addInputs(collector.urls)
        }
        return true
    }
}

@main
struct SquishyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 422, height: 724)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .squishyCheckForUpdates, object: nil)
                }
            }
        }
    }
}
