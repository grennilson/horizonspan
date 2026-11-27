import AppKit
import Combine
import ImageIO
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct Display: Identifiable {
    let id: UInt32
    let name: String
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let hardwareKey: String

    init(id: UInt32, name: String, frame: CGRect, pixelWidth: Int, pixelHeight: Int,
         persistentID: String? = nil) {
        self.id = id
        self.name = name
        self.frame = frame
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        if let persistentID {
            hardwareKey = persistentID
        } else if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            hardwareKey = CFUUIDCreateString(nil, uuid) as String
        } else {
            hardwareKey = "\(name)-\(id)"
        }
    }

    static func connected() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return Display(id: number.uint32Value, name: screen.localizedName, frame: screen.frame,
                           pixelWidth: Int((screen.frame.width * screen.backingScaleFactor).rounded()),
                           pixelHeight: Int((screen.frame.height * screen.backingScaleFactor).rounded()))
        }.sorted { ($0.frame.minX, -$0.frame.maxY, $0.id) < ($1.frame.minX, -$1.frame.maxY, $1.id) }
    }
}

enum ImageFraming: String, Codable {
    case fit, fill

    func scale(image: CGSize, in bounds: CGSize) -> CGFloat {
        let horizontal = bounds.width / image.width
        let vertical = bounds.height / image.height
        return self == .fit ? min(horizontal, vertical) : max(horizontal, vertical)
    }
}

struct WallpaperLayout {
    let bounds: CGRect
    let imageRect: CGRect

    init(displays: [Display], imageSize: CGSize, framing: ImageFraming, zoom: CGFloat, pan: CGSize) {
        bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
        let scale = framing.scale(image: imageSize, in: bounds.size) * zoom
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let xLimit = abs(size.width - bounds.width) / 2
        let yLimit = abs(size.height - bounds.height) / 2
        let x = min(max(pan.width * bounds.width, -xLimit), xLimit)
        let y = min(max(pan.height * bounds.height, -yLimit), yLimit)
        imageRect = CGRect(x: (bounds.width - size.width) / 2 + x, y: (bounds.height - size.height) / 2 + y,
                           width: size.width, height: size.height)
    }

    func rect(for display: Display) -> CGRect {
        CGRect(x: display.frame.minX - bounds.minX, y: bounds.maxY - display.frame.maxY,
               width: display.frame.width, height: display.frame.height)
    }

    func image(_ image: CGImage, for display: Display, background: CGColor = CGColor(gray: 0, alpha: 1)) throws -> CGImage {
        guard let context = CGContext(data: nil, width: display.pixelWidth, height: display.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw WallpaperError.render(display.name)
        }
        let screen = rect(for: display)
        let xScale = CGFloat(display.pixelWidth) / screen.width
        let yScale = CGFloat(display.pixelHeight) / screen.height
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: display.pixelWidth, height: display.pixelHeight))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (imageRect.minX - screen.minX) * xScale,
                                       y: (screen.maxY - imageRect.maxY) * yScale,
                                       width: imageRect.width * xScale, height: imageRect.height * yScale))
        guard let output = context.makeImage() else { throw WallpaperError.render(display.name) }
        return output
    }

    func render(_ image: CGImage, for display: Display, to url: URL) throws {
        let output = try self.image(image, for: display)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw WallpaperError.render(display.name)
        }
        CGImageDestinationAddImage(destination, output, nil)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.render(display.name) }
    }
}

enum WallpaperError: LocalizedError {
    case image, save, displays, render(String), apply(String, Bool)

    var errorDescription: String? {
        switch self {
        case .image: return "This image couldn’t be opened."
        case .save: return "ScreenSpan Wallpaper couldn’t save the wallpaper for automatic restoration."
        case .displays: return "Your display arrangement changed. Check the preview and try again."
        case .render(let name): return "Couldn’t create the wallpaper for \(name)."
        case .apply(let name, let restored):
            return restored ? "Couldn’t apply the wallpaper to \(name). Earlier changes were restored."
                : "Couldn’t apply the wallpaper to \(name). Some displays may still show the new image."
        }
    }
}

struct SourceImage {
    let filename: String
    let image: CGImage

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height)
              ] as CFDictionary) else { throw WallpaperError.image }
        filename = url.lastPathComponent
        self.image = image
    }

    init(filename: String, image: CGImage) {
        self.filename = filename
        self.image = image
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
}

final class ImageDropTarget: ObservableObject {
    @Published var isTargeted = false

    static func load(_ providers: [NSItemProvider],
                     completion: @escaping (Result<[URL], Error>) -> Void) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        Task {
            do {
                var urls: [URL] = []
                for provider in files {
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                            if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                                continuation.resume(returning: url)
                            } else {
                                continuation.resume(throwing: error ?? WallpaperError.image)
                            }
                        }
                    }
                    urls.append(url)
                }
                completion(.success(urls))
            } catch {
                completion(.failure(error))
            }
        }
        return true
    }
}

@MainActor
final class WallpaperState: ObservableObject {
    struct FramedImage {
        let source: SourceImage
        let framing: ImageFraming
        let zoom: CGFloat
        let pan: CGSize
        let design: WallpaperDesign
        let groupImages: [Int: SourceImage]
    }

    private struct Edit {
        let name: String
        let current: FramedImage
        let original: FramedImage?
    }

    @Published var displays = Display.connected()
    @Published var source: SourceImage?
    @Published private(set) var original: FramedImage?
    @Published var showOriginal = false
    @Published var isProcessingAI = false
    @Published private var undoEdits: [Edit] = []
    @Published private var redoEdits: [Edit] = []
    @Published private var choosingImage = false

    var isBusy: Bool { isApplying || isProcessingAI }
    var canChooseImage: Bool { !isBusy && !choosingImage && !showEdgeOptions && !showCombineImages && cropRect == nil && !showDesignOptions }
    @Published var cropRect: CGRect?
    @Published var showCombineImages = false
    @Published var imagesToCombine: [SourceImage] = []
    @Published var combinationArrangement = ImageArrangement.horizontal
    var undoTitle: String { undoEdits.last.map { "Undo \($0.name)" } ?? "Undo" }
    var redoTitle: String { redoEdits.last.map { "Redo \($0.name)" } ?? "Redo" }
    var canUndo: Bool { canChooseImage && !undoEdits.isEmpty }
    var canRedo: Bool { canChooseImage && !redoEdits.isEmpty }
    private var currentImage: FramedImage? {
        source.map { FramedImage(source: $0, framing: framing, zoom: zoom, pan: pan, design: design, groupImages: groupImages) }
    }
    @Published var framing: ImageFraming = .fit
    @Published var zoom: CGFloat = 1
    @Published var pan = CGSize.zero
    @Published var status = ""
    @Published var isApplying = false
    @Published var errorMessage: String?
    @Published var showEdgeOptions = false
    @Published var edgeDescription = ""
    @Published private(set) var saved: SavedWallpaper?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var loginError: String?
    let store = try? WallpaperStore.userStore()
    @Published var design = WallpaperDesign.standard
    @Published var groupImages: [Int: SourceImage] = [:]
    @Published var showDesignOptions = false
    @Published var libraryEntries: [LibraryEntry] = []
    @Published var libraryIndex = LibraryIndex()
    var editingProject: URL?
    @Published var selectedLibraryID: UUID?
    @Published var libraryTitle = ""
    @Published var setupName = "My Desk"
    @Published var featureError: String?
    @Published var autoMatchSetups = UserDefaults.standard.bool(forKey: "autoMatchSetups") {
        didSet { UserDefaults.standard.set(autoMatchSetups, forKey: "autoMatchSetups") }
    }
    @Published var rotationEnabled = UserDefaults.standard.bool(forKey: "rotateFavorites") {
        didSet {
            UserDefaults.standard.set(rotationEnabled, forKey: "rotateFavorites")
            resetRotationClock()
        }
    }
    @Published var rotationMinutes = max(1, UserDefaults.standard.integer(forKey: "rotationMinutes")) {
        didSet {
            UserDefaults.standard.set(rotationMinutes, forKey: "rotationMinutes")
            resetRotationClock()
        }
    }
    var nextRotation = Date.distantFuture
    @Published var updateStatus = ""
    @Published var updateURL: URL?
    @Published var checkingUpdates = false
    private var observers = Set<AnyCancellable>()
    private var restoreTask: Task<Void, Never>?
    private let startupRestoreUntil = Date().addingTimeInterval(45)

    init(observeSystem: Bool = true) {
        saved = store?.current()
        guard observeSystem else { return }
        refreshLibrary()
        resetRotationClock()
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.rotateIfDue() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.displays = Display.connected()
                if self?.cropRect != nil { self?.beginCrop() }
                self?.scheduleRestore(matchSetup: true) { WallpaperPreferences.restoreOnDisplays() || self?.autoMatchSetups == true }
            }
            .store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRestore(when: WallpaperPreferences.syncSpaces) }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshLoginStatus() }
            .store(in: &observers)
        WallpaperRestoreLog.record("Started; saved=\(saved?.id.uuidString ?? "none"); login=\(loginStatus.rawValue)")
        scheduleRestore(matchSetup: true) {
            WallpaperPreferences.restoreOnDisplays() || WallpaperPreferences.syncSpaces() || self.autoMatchSetups
        }
    }

    func chooseImage() {
        guard canChooseImage else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .screenSpanWallpaper]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        choosingImage = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.choosingImage = false
            if response == .OK {
                DispatchQueue.main.async { self.loadImages(panel.urls) }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func loadImages(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1 {
            loadImage(urls[0])
            return
        }
        guard urls.allSatisfy({ $0.pathExtension.lowercased() != "ssw" }) else {
            errorMessage = "Open one wallpaper project at a time, or select image files to combine."
            return
        }
        do {
            let images = try urls.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }.map { url in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try SourceImage(url: url)
            }
            imagesToCombine = images
            combinationArrangement = .horizontal
            showCombineImages = true
        } catch { errorMessage = error.localizedDescription }
    }

    func combineImages(_ arrangement: ImageArrangement) {
        guard !isBusy, imagesToCombine.count >= 2 else { return }
        let images = imagesToCombine
        showCombineImages = false
        isProcessingAI = true
        status = "Combining images…"
        Task {
            defer { isProcessingAI = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try arrangement.combine(images)
                }.value
                source = result
                editingProject = nil
                design = .standard
                groupImages = [:]
                original = nil
                undoEdits.removeAll()
                redoEdits.removeAll()
                showOriginal = false
                framing = .fit
                zoom = 1
                pan = .zero
                edgeDescription = ""
                imagesToCombine = []
                status = "Combined \(images.count) images"
            } catch {
                imagesToCombine = []
                status = ""
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadImage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let project = url.pathExtension.lowercased() == "ssw" ? try WallpaperProject.open(url) : nil
            let loaded = try project?.0 ?? SourceImage(url: url)
            let assets = try project.map { try WallpaperProject.assets(at: url, settings: $0.1) } ?? [:]
            source = loaded
            editingProject = project == nil ? nil : url
            design = project?.1.design ?? .standard
            groupImages = assets
            original = nil
            undoEdits.removeAll()
            redoEdits.removeAll()
            showOriginal = false
            edgeDescription = ""
            framing = project?.1.framing ?? .fit
            zoom = project?.1.zoom ?? 1
            pan = project?.1.pan ?? .zero
            status = project == nil ? "" : "Opened saved project"
        } catch { errorMessage = error.localizedDescription }
    }

    func finishImageEdit(_ action: ImageAIAction, image: CGImage) {
        guard let currentImage else { return }
        let name = action == .fade ? ImageAIAction.extend.title : action.title
        recordEdit(name, currentImage)
        original = original ?? currentImage
        source = SourceImage(filename: currentImage.source.filename, image: image)
        if action != .enhance {
            framing = .fit
            zoom = 1
            pan = .zero
        }
        status = action.result
    }

    func beginCrop() {
        guard let source, !displays.isEmpty, !isBusy, !showOriginal else { return }
        let layout = WallpaperLayout(displays: displays, imageSize: source.size, framing: framing, zoom: zoom, pan: pan)
        let scale = layout.imageRect.width / source.size.width
        let visible = CGRect(x: -layout.imageRect.minX / scale, y: -layout.imageRect.minY / scale,
                             width: layout.bounds.width / scale, height: layout.bounds.height / scale)
        let imageBounds = CGRect(origin: .zero, size: source.size)
        cropRect = imageBounds.contains(visible) ? visible :
            CropGeometry.fitted(in: source.size, ratio: layout.bounds.width / layout.bounds.height)
        status = ""
    }

    func applyCrop() {
        guard !isBusy, let currentImage, let cropRect,
              let image = currentImage.source.image.cropping(to: CropGeometry.pixels(cropRect, in: currentImage.source.image))
        else { return }
        recordEdit("Crop", currentImage)
        original = original ?? currentImage
        source = SourceImage(filename: currentImage.source.filename, image: image)
        framing = .fit
        zoom = 1
        pan = .zero
        self.cropRect = nil
        status = "Cropped image"
    }

    func revertToOriginal() {
        guard let currentImage, let original else { return }
        recordEdit("Revert to Original", currentImage)
        restoreFraming(original)
        self.original = nil
        showOriginal = false
        status = "Restored original image"
    }

    func undoImageEdit() {
        guard canUndo, let currentImage, let edit = undoEdits.popLast() else { return }
        redoEdits.append(Edit(name: edit.name, current: currentImage, original: original))
        restoreEdit(edit)
        status = "Undid \(edit.name)"
    }

    func redoImageEdit() {
        guard canRedo, let currentImage, let edit = redoEdits.popLast() else { return }
        undoEdits.append(Edit(name: edit.name, current: currentImage, original: original))
        restoreEdit(edit)
        status = "Redid \(edit.name)"
    }

    private func recordEdit(_ name: String, _ image: FramedImage) {
        undoEdits.append(Edit(name: name, current: image, original: original))
        // Full-resolution images can be very large. Keep the most recent edits and the original.
        if undoEdits.count > 5 { undoEdits.removeFirst() }
        redoEdits.removeAll()
    }

    private func restoreEdit(_ edit: Edit) {
        restoreFraming(edit.current)
        original = edit.original
        showOriginal = false
    }

    private func restoreFraming(_ image: FramedImage) {
        source = image.source
        framing = image.framing
        zoom = image.zoom
        pan = image.pan
        design = image.design
        groupImages = image.groupImages
    }

    func apply() {
        guard let source, !displays.isEmpty, !isBusy, !showOriginal, cropRect == nil, !showDesignOptions else { return }
        let wallpaper = SavedWallpaper(source: source, framing: framing, zoom: zoom, pan: pan, design: currentDesign)
        isApplying = true
        Task {
            defer { isApplying = false }
            do {
                try await applyPrepared(source: source, wallpaper: wallpaper, assets: groupImages, archive: true)
                refreshLibrary()
                offerStartupRestoration()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func applyPrepared(source: SourceImage, wallpaper: SavedWallpaper, assets: [Int: SourceImage], archive: Bool) async throws {
        guard let store else { throw WallpaperError.save }
        let targets = Display.connected()
        guard !targets.isEmpty else { throw WallpaperError.displays }
        let preferredID = saved?.id
        let target = editingProject
        let (selection, urls, projectURL) = try await Task.detached(priority: .userInitiated) {
            var selection = wallpaper
            var projectURL: URL?
            if archive {
                let url = try WallpaperProject.save(source: source, wallpaper: wallpaper, displays: targets,
                    assets: assets, preferredID: preferredID, updating: target)
                selection = try WallpaperProject.manifest(at: url).wallpaper
                projectURL = url
            }
            try store.store(source.image, as: selection, assets: assets)
            return (selection, try store.render(source.image, wallpaper: selection, displays: targets, assets: assets), projectURL)
        }.value
        try assign(urls, to: targets, skipMatching: false) {
            do { try store.select(selection) } catch { throw WallpaperError.save }
        }
        saved = selection
        if archive { editingProject = projectURL }
        refreshLibrary()
        status = "Applied to \(targets.count) \(targets.count == 1 ? "display" : "displays")"
    }

    func saveProject() { saveWallpaper(asNew: false) }

    func saveNewWallpaper() { saveWallpaper(asNew: true) }

    func saveWallpaper(asNew: Bool) {
        guard let source, !isBusy, !showOriginal, !displays.isEmpty, cropRect == nil else { return }
        let wallpaper = SavedWallpaper(source: source, framing: framing, zoom: zoom, pan: pan, design: currentDesign)
        let targets = displays
        let assets = groupImages
        let preferredID = saved?.id
        let target = asNew ? nil : editingProject
        isApplying = true
        status = "Saving wallpaper…"
        Task {
            defer { isApplying = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try WallpaperProject.save(source: source, wallpaper: wallpaper, displays: targets,
                        assets: assets, preferredID: preferredID, updating: target, asNew: asNew)
                }.value
                editingProject = url
                refreshLibrary()
                status = "Saved in Pictures"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                status = ""
                errorMessage = "Couldn’t save the wallpaper. \(error.localizedDescription)"
            }
        }
    }

    func showWallpaperLibrary() {
        do { NSWorkspace.shared.open(try WallpaperProject.library()) }
        catch { errorMessage = error.localizedDescription }
    }

    private func scheduleRestore(matchSetup: Bool = false, when enabled: @escaping () -> Bool) {
        guard saved != nil, enabled() else { return }
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            guard let self else { return }
            let delays = Date() < self.startupRestoreUntil ? WallpaperRestoreSchedule.startup : WallpaperRestoreSchedule.changed
            await WallpaperRestoreSchedule.run(delays: delays, enabled: enabled) { [weak self] in
                await self?.restore(force: true, matchSetup: matchSetup, when: enabled)
            }
        }
    }

    func reapplySavedWallpaper() {
        restoreTask?.cancel()
        restoreTask = Task { await restore(force: true, reportResult: true) }
    }

    private func restore(force: Bool, reportResult: Bool = false, matchSetup: Bool = false, when enabled: () -> Bool = { true }) async {
        guard let store, let wallpaper = saved else { return }
        while isApplying {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        guard wallpaper.id == saved?.id, !Task.isCancelled, enabled() else { return }
        let targets = Display.connected()
        WallpaperRestoreLog.record("Restore \(wallpaper.id); displays=\(targets.count); force=\(force)")
        if matchSetup, autoMatchSetups, let entry = matchedSetup(for: targets), entry.id != wallpaper.id {
            isApplying = true
            defer { isApplying = false }
            do {
                let (source, selection, assets) = try await Self.readProject(entry.url)
                guard !Task.isCancelled, enabled() else { return }
                try await applyPrepared(source: source, wallpaper: selection, assets: assets, archive: false)
                if self.source == nil {
                    self.source = source
                    design = selection.design ?? .standard
                    groupImages = assets
                    framing = selection.framing
                    zoom = selection.zoom
                    pan = selection.pan
                }
            } catch {
                WallpaperRestoreLog.record("Monitor setup restore failed: \(error.localizedDescription)")
                status = "Couldn’t restore the saved monitor setup"
            }
            return
        }
        guard !targets.isEmpty else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let (source, urls, assets) = try await Task.detached(priority: .utility) {
                let source = try store.source(for: wallpaper)
                let assets = try store.assets(for: wallpaper)
                let urls = try store.render(source.image, wallpaper: wallpaper, displays: targets, assets: assets)
                return (source, urls, assets)
            }.value
            guard !Task.isCancelled, enabled() else { return }
            try assign(urls, to: targets, skipMatching: !force)
            WallpaperRestoreLog.record("Restored \(wallpaper.id) to \(targets.map(\.name).joined(separator: ", "))")
            if self.source == nil {
                self.source = source
                design = wallpaper.design ?? .standard
                groupImages = assets
                framing = wallpaper.framing
                zoom = wallpaper.zoom
                pan = wallpaper.pan
            }
            if reportResult { status = "Restored saved wallpaper" }
        } catch {
            if !Task.isCancelled { WallpaperRestoreLog.record("Restore failed: \(error.localizedDescription)") }
            if reportResult && !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    private func offerStartupRestoration() {
        refreshLoginStatus()
        let defaults = UserDefaults.standard
        guard loginStatus != .enabled,
              WallpaperPreferences.restoreOnDisplays() || WallpaperPreferences.syncSpaces() || autoMatchSetups,
              !defaults.bool(forKey: "startupRestorationOfferShown") else { return }
        defaults.set(true, forKey: "startupRestorationOfferShown")
        let alert = NSAlert()
        alert.messageText = "Restore this wallpaper after restarting?"
        alert.informativeText = "ScreenSpan needs to open at login to restore your wallpaper as macOS finishes connecting the displays. You can change this later in Settings."
        alert.addButton(withTitle: "Enable Open at Login")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn { toggleOpenAtLogin() }
    }

    func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        defer { refreshLoginStatus() }
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try service.register()
            }
        } catch {
            loginError = error.localizedDescription
        }
    }
}

struct WallpaperView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: WallpaperState
    @GestureState private var drag = CGSize.zero
    @StateObject private var dropTarget = ImageDropTarget()

    var body: some View {
        let displays = model.displays
        let comparison = model.showOriginal ? model.original : nil
        let source = comparison?.source ?? model.source
        let framing = comparison?.framing ?? model.framing
        let zoom = comparison?.zoom ?? model.zoom
        let pan = comparison?.pan ?? model.pan
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ScreenSpan Wallpaper").font(.title.bold())
                    Text(source.map { "\($0.filename) · \($0.image.width) × \($0.image.height)" }
                         ?? "Choose images for your wallpaper.")
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Library") { openWindow(id: "library") }
                Button("Choose Image…", action: model.chooseImage)
                    .keyboardShortcut("o")
                    .onDrop(of: [.fileURL], isTargeted: nil, perform: receiveImageDrop)
                    .disabled(!model.canChooseImage)
            }

            GeometryReader { geometry in
                if let source, model.cropRect != nil {
                    CropPreview(image: source.image, selection: Binding(
                        get: { model.cropRect ?? .zero }, set: { model.cropRect = $0 }))
                    .accessibilityLabel("Crop preview. Drag inside the rectangle to move it, drag a corner to resize, or scroll to zoom.")
                } else if let source, !displays.isEmpty, (comparison?.design ?? model.currentDesign) != .standard {
                    DesignedPreview(source: source, wallpaper: SavedWallpaper(source: source, framing: framing,
                        zoom: zoom, pan: pan, design: comparison?.design ?? model.currentDesign),
                        displays: displays, assets: comparison?.groupImages ?? model.groupImages)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onEnded { value in
                            guard !model.isBusy, !model.showOriginal else { return }
                            let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
                            let scale = min(max(1, geometry.size.width - 44) / bounds.width,
                                            max(1, geometry.size.height - 44) / bounds.height)
                            model.pan.width += value.translation.width / (bounds.width * scale)
                            model.pan.height += value.translation.height / (bounds.height * scale)
                        })
                } else if let source, !displays.isEmpty {
                    let layout = WallpaperLayout(displays: displays, imageSize: source.size, framing: framing, zoom: zoom, pan: pan)
                    let scale = min(max(geometry.size.width - 44, 1) / layout.bounds.width,
                                    max(geometry.size.height - 44, 1) / layout.bounds.height)
                    let width = layout.bounds.width * scale
                    let height = layout.bounds.height * scale
                    let active = WallpaperLayout(displays: displays, imageSize: source.size, framing: framing, zoom: zoom,
                                                 pan: CGSize(width: pan.width + drag.width / width,
                                                             height: pan.height + drag.height / height))
                    Canvas { context, size in
                        let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
                        func previewRect(_ rect: CGRect) -> CGRect {
                            CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
                                   width: rect.width * scale, height: rect.height * scale)
                        }
                        let preview = Image(decorative: source.image, scale: 1)
                        for (index, display) in displays.enumerated() {
                            let rect = previewRect(active.rect(for: display))
                            let outline = Path(rect)
                            var clipped = context
                            clipped.clip(to: outline)
                            clipped.fill(outline, with: .color(.black))
                            clipped.draw(preview, in: previewRect(active.imageRect))
                            context.stroke(outline, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                            let badge = Path(roundedRect: CGRect(x: rect.minX + 9, y: rect.minY + 9, width: 24, height: 21),
                                             cornerRadius: 5)
                            clipped.fill(badge, with: .color(.black.opacity(0.75)))
                            clipped.draw(Text("\(index + 1)").font(.caption.bold()).foregroundColor(.white),
                                         at: CGPoint(x: rect.minX + 21, y: rect.minY + 19))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture()
                        .updating($drag) { value, state, _ in
                            if !model.isBusy && !model.showOriginal { state = value.translation }
                        }
                        .onEnded { value in
                            guard !model.isBusy, !model.showOriginal else { return }
                            let next = WallpaperLayout(displays: displays, imageSize: source.size, framing: framing, zoom: zoom,
                                pan: CGSize(width: pan.width + value.translation.width / width,
                                            height: pan.height + value.translation.height / height))
                            model.pan = CGSize(width: (next.imageRect.midX - next.bounds.width / 2) / next.bounds.width,
                                         height: (next.imageRect.midY - next.bounds.height / 2) / next.bounds.height)
                            model.status = ""
                        })
                    .accessibilityLabel("Preview of wallpaper across \(displays.count) displays")
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "display.2").font(.system(size: 35))
                        Text(displays.isEmpty ? "No displays detected" : "Drag images here")
                        if !displays.isEmpty {
                            Button("Choose Image…", action: model.chooseImage)
                                .disabled(!model.canChooseImage)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(dropTarget.isTargeted ? Color.accentColor : Color.secondary.opacity(0.18),
                                  lineWidth: dropTarget.isTargeted ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $dropTarget.isTargeted, perform: receiveImageDrop)

            HStack(spacing: 13) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    Text("\(index + 1)  \(display.name)").font(.caption).lineLimit(1)
                }
                Spacer()
                if model.cropRect != nil {
                    Text("Drag corners to crop · Scroll to zoom").font(.caption).foregroundStyle(.secondary)
                } else if source != nil && !model.showOriginal {
                    Text("Drag the preview to reposition").font(.caption).foregroundStyle(.secondary)
                }
            }

            if let selected = model.source {
                HStack {
                    Picker("Framing", selection: Binding(get: { model.framing }, set: { value in
                        model.framing = value
                        resetFramingPosition()
                    })) {
                        Text("Fit Entire Photo").tag(ImageFraming.fit)
                        Text("Fill & Crop").tag(ImageFraming.fill)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help("Fit keeps the entire photo visible at minimum zoom. Fill covers the displays and may crop the photo.")
                    .disabled(model.isBusy || model.showOriginal || model.cropRect != nil)
                    Spacer()
                    if let crop = model.cropRect {
                        Text(CropGeometry.ratioLabel(displays.reduce(CGRect.null) { $0.union($1.frame) }.size))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(crop.width)) × \(Int(crop.height))").font(.caption).foregroundStyle(.secondary)
                        Button("Cancel Crop") { model.cropRect = nil }
                        Button("Apply Crop", action: model.applyCrop).buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                    } else {
                        Button("Crop Image", action: model.beginCrop)
                            .disabled(model.isBusy || model.showOriginal || displays.isEmpty)
                    }
                }
                Button("Displays & Appearance…") { model.showDesignOptions = true }
                    .disabled(model.isBusy || model.showOriginal || model.cropRect != nil)
                imageTools(for: selected)
            }
            Divider()
            HStack {
                Text("Zoom")
                Slider(value: Binding(get: { model.zoom }, set: { value in
                    model.zoom = value
                    model.status = ""
                }), in: 1...3)
                .frame(width: 120)
                .accessibilityLabel("Zoom")
                .disabled(model.showOriginal || model.cropRect != nil)
                Button("Reset", action: resetFramingPosition)
                    .disabled(model.showOriginal || model.cropRect != nil)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Menu {
                    Button("Save Wallpaper", action: model.saveProject)
                    Button("Save as New Wallpaper", action: model.saveNewWallpaper)
                } label: { Text("Save Wallpaper") } primaryAction: { model.saveProject() }
                    .disabled(model.source == nil || displays.isEmpty || model.isBusy || model.showOriginal || model.cropRect != nil)
                Button("Apply Wallpaper", action: model.apply).buttonStyle(.borderedProminent)
                    .disabled(model.source == nil || displays.isEmpty || model.isBusy || model.showOriginal || model.cropRect != nil)
            }
            .disabled(model.source == nil || model.isBusy)
        }
        .padding(24)
        .frame(minWidth: 735, minHeight: 490)
        .sheet(isPresented: $model.showEdgeOptions) {
            edgeOptions
        }
        .sheet(isPresented: $model.showCombineImages) {
            CombineImagesView(model: model)
        }
        .sheet(isPresented: $model.showDesignOptions) {
            WallpaperDesignView(model: model)
        }
        .alert("ScreenSpan Wallpaper", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func resetFramingPosition() {
        model.zoom = 1
        model.pan = .zero
        if !model.isBusy { model.status = "" }
    }

    private func receiveImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.canChooseImage else { return false }
        return ImageDropTarget.load(providers) { result in
            DispatchQueue.main.async {
                guard model.canChooseImage else { return }
                switch result {
                case .success(let urls): model.loadImages(urls)
                case .failure: model.errorMessage = "Drop image files from Finder."
                }
            }
        }
    }

    private func imageTools(for source: SourceImage) -> some View {
        let extend = ImageAIPlan(.extend, image: source.image, displays: model.displays, framing: model.framing, zoom: model.zoom)
        let enhance = ImageAIPlan(.enhance, image: source.image, displays: model.displays, framing: model.framing, zoom: model.zoom)
        return HStack(spacing: 10) {
            Button(ImageAIAction.extend.title) {
                model.showEdgeOptions = true
            }
            .disabled(extend == nil || model.showOriginal)
            .help("Fill the space around the photo using a dark fade or generated scenery.")
            Button(ImageAIAction.enhance.title) {
                if let enhance { process(.enhance, source: source, plan: enhance) }
            }
            .disabled(enhance == nil || !LocalImageAI.isSupported || model.showOriginal)
            .help("Upscale a low-resolution image on this Mac. Model size is about 67 MB. First use downloads the model and any missing local AI tools.")
            Spacer()
            if model.canUndo || model.canRedo {
                Button("Undo", action: model.undoImageEdit).disabled(!model.canUndo).help(model.undoTitle)
                Button("Redo", action: model.redoImageEdit).disabled(!model.canRedo).help(model.redoTitle)
            }
            if model.original != nil {
                Toggle("Show Original", isOn: $model.showOriginal).toggleStyle(.checkbox)
                Button("Revert to Original", action: model.revertToOriginal)
            } else if !model.canUndo && !model.canRedo {
                Text(LocalImageAI.isSupported ? "On-device AI · First use downloads models" : "Local AI requires Apple Silicon")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.isBusy || model.cropRect != nil)
    }

    private var edgeOptions: some View {
        let selected = model.source
        let plan = selected.flatMap {
            ImageAIPlan(.extend, image: $0.image, displays: model.displays, framing: model.framing,
                        zoom: model.zoom, pan: model.pan)
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Extend Edges").font(.title2.bold())
            if let plan {
                Text("The original keeps its position in a \(plan.width) × \(plan.height) image.")
                    .foregroundStyle(.secondary)
            }
            Text("Fade to Black continues the edge texture into a dark background.")
                .foregroundStyle(.secondary)
            if LocalImageAI.isSupported {
                TextField("Describe what AI should add at the edges (optional)", text: $model.edgeDescription)
                    .textFieldStyle(.roundedBorder)
                Text("Generate with AI runs on this Mac. The first use downloads about 7 GB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.showEdgeOptions = false }.keyboardShortcut(.cancelAction)
                Button(ImageAIAction.fade.title) {
                    guard let selected, let plan else { return }
                    model.showEdgeOptions = false
                    process(.fade, source: selected, plan: plan)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil)
                if LocalImageAI.isSupported {
                    Button("Generate with AI") {
                        guard let selected, let plan else { return }
                        model.showEdgeOptions = false
                        process(.extend, source: selected, plan: plan, prompt: model.edgeDescription)
                    }
                    .disabled(plan == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 515)
    }

    private func process(_ action: ImageAIAction, source: SourceImage, plan: ImageAIPlan, prompt: String = "") {
        guard !model.isBusy else { return }
        model.isProcessingAI = true
        model.status = action == .fade ? "Fading edges…" : "Preparing local AI…"
        model.showOriginal = false
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try LocalImageAI.run(action, image: source.image, plan: plan, prompt: prompt) { status in
                    DispatchQueue.main.async { model.status = status }
                }
            }
            DispatchQueue.main.async {
                model.isProcessingAI = false
                switch result {
                case .success(let image):
                    model.finishImageEdit(action, image: image)
                case .failure(let error):
                    model.status = ""
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

}

extension WallpaperState {
    func assign(_ urls: [URL], to targets: [Display], skipMatching: Bool,
                        commit: () throws -> Void = {}) throws {
        let screens = NSScreen.screens
        let current = Display.connected()
        guard urls.count == targets.count, targets.count == current.count,
              zip(targets, current).allSatisfy({ $0.id == $1.id && $0.frame == $1.frame &&
                  $0.pixelWidth == $1.pixelWidth && $0.pixelHeight == $1.pixelHeight })
        else { throw WallpaperError.displays }

        let workspace = NSWorkspace.shared
        var applied: [(NSScreen, URL?, [NSWorkspace.DesktopImageOptionKey: Any])] = []
        var applyingDisplay: String?
        do {
            for (display, url) in zip(targets, urls) {
                guard let screen = screens.first(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
                }) else { throw WallpaperError.displays }
                let oldURL = workspace.desktopImageURL(for: screen)
                if skipMatching && oldURL?.standardizedFileURL == url.standardizedFileURL { continue }
                let oldOptions = workspace.desktopImageOptions(for: screen) ?? [:]
                applyingDisplay = display.name
                try workspace.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                    .allowClipping: false
                ])
                applied.append((screen, oldURL, oldOptions))
                applyingDisplay = nil
            }
            try commit()
        } catch {
            var restored = true
            for (screen, previous, options) in applied.reversed() {
                guard let previous else { restored = false; continue }
                do { try workspace.setDesktopImageURL(previous, for: screen, options: options) }
                catch { restored = false }
            }
            if let applyingDisplay { throw WallpaperError.apply(applyingDisplay, restored) }
            throw error
        }
    }
}

enum WallpaperPreferences {
    static let menuBarKey = "showMenuBarIcon"
    static let displaysKey = "restoreOnDisplayChanges"
    static let spacesKey = "syncWallpaperAcrossSpaces"

    static func restoreOnDisplays() -> Bool { UserDefaults.standard.object(forKey: displaysKey) as? Bool ?? true }
    static func syncSpaces() -> Bool { UserDefaults.standard.object(forKey: spacesKey) as? Bool ?? true }
}

struct WallpaperSettings: View {
    @ObservedObject var model: WallpaperState
    @AppStorage(WallpaperPreferences.menuBarKey) private var showMenuBarIcon = true
    @AppStorage(WallpaperPreferences.displaysKey) private var restoreOnDisplays = true
    @AppStorage(WallpaperPreferences.spacesKey) private var syncSpaces = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
                Toggle("Open at Login", isOn: Binding(get: { model.loginStatus == .enabled },
                                                      set: { _ in model.toggleOpenAtLogin() }))
                    .disabled(model.loginStatus == .requiresApproval)
                if model.loginStatus == .requiresApproval {
                    Button("Approve in System Settings…", action: model.toggleOpenAtLogin)
                } else if model.loginStatus != .enabled {
                    Text("Open at Login is off. Enable it so ScreenSpan can restore your wallpaper after a restart.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if restoreOnDisplays || syncSpaces || model.autoMatchSetups {
                    Text("ScreenSpan will open at login and restore your last applied wallpaper while displays finish connecting.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Open at Login is enabled. Turn on a wallpaper restoration option below to restore the wallpaper automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Wallpaper") {
                Toggle("Sync wallpaper across macOS desktops", isOn: $syncSpaces)
                Toggle("Reapply wallpaper when displays change or wake", isOn: $restoreOnDisplays)
                Toggle("Automatically match saved monitor setups", isOn: $model.autoMatchSetups)
            }
            Section("Rotation") {
                Toggle("Rotate favorite wallpapers", isOn: $model.rotationEnabled)
                Picker("Change every", selection: $model.rotationMinutes) {
                    ForEach([1, 5, 15, 30, 60, 120], id: \.self) {
                        Text($0 == 1 ? "1 minute" : "\($0) minutes").tag($0)
                    }
                }
                Text("Favorite projects in the library to include them in rotation.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Button("Check for Updates", action: model.checkForUpdates).disabled(model.checkingUpdates)
                if !model.updateStatus.isEmpty { Text(model.updateStatus).font(.caption) }
                if let url = model.updateURL {
                    Button("View Release") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 570)
        .onAppear(perform: model.refreshLoginStatus)
        .alert("Open at Login", isPresented: Binding(get: { model.loginError != nil },
                                                    set: { if !$0 { model.loginError = nil } })) {
            Button("OK") { model.loginError = nil }
        } message: {
            Text(model.loginError ?? "")
        }
    }
}

struct WallpaperMenu: View {
    @ObservedObject var model: WallpaperState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open ScreenSpan Wallpaper") {
            openWindow(id: "main", value: true)
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("New Wallpaper…") {
            openWindow(id: "main", value: true)
            NSApp.activate(ignoringOtherApps: true)
            model.chooseImage()
        }
        .disabled(!model.canChooseImage)
        Button("Reapply Saved Wallpaper", action: model.reapplySavedWallpaper)
            .disabled(model.saved == nil || model.isApplying || model.displays.isEmpty)
        Button("Wallpaper Library…") { openWindow(id: "library"); NSApp.activate(ignoringOtherApps: true) }
        Button("Next Wallpaper") { model.nextWallpaper() }.disabled(model.isBusy)
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit ScreenSpan Wallpaper") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct WallpaperCommands: Commands {
    @ObservedObject var model: WallpaperState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Wallpaper…") {
                openWindow(id: "main", value: true)
                model.chooseImage()
            }
            .keyboardShortcut("n")
            .disabled(!model.canChooseImage)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(model.undoTitle, action: model.undoImageEdit)
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
            Button(model.redoTitle, action: model.redoImageEdit)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
        }
        CommandGroup(after: .newItem) {
            Button("Save Wallpaper", action: model.saveProject)
                .keyboardShortcut("s")
                .disabled(model.source == nil || model.isBusy || model.showOriginal || model.displays.isEmpty || model.cropRect != nil)
            Button("Save as New Wallpaper", action: model.saveNewWallpaper)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.source == nil || model.isBusy || model.showOriginal || model.displays.isEmpty || model.cropRect != nil)
            Button("Wallpaper Library…") { openWindow(id: "library") }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",")
        }
    }
}

final class HorizonSpanDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#if !SCREENSPAN_TESTING
@main
#endif
struct HorizonSpanApp: App {
    @NSApplicationDelegateAdaptor(HorizonSpanDelegate.self) private var delegate
    @StateObject private var model = WallpaperState()
    @AppStorage(WallpaperPreferences.menuBarKey) private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup("ScreenSpan Wallpaper", id: "main", for: Bool.self) { _ in
            WallpaperView(model: model)
                .onOpenURL { url in
                    guard model.canChooseImage else {
                        model.errorMessage = "Finish the current operation before opening a project."
                        return
                    }
                    model.loadImage(url)
                }
        } defaultValue: {
            true
        }
        .defaultSize(width: 820, height: 540)
        .windowResizability(.contentMinSize)
        .commands { WallpaperCommands(model: model) }

        Window("ScreenSpan Wallpaper Settings", id: "settings") {
            WallpaperSettings(model: model)
        }
        .windowResizability(.contentSize)

        Window("Wallpaper Library", id: "library") { WallpaperLibraryView(model: model) }
            .defaultSize(width: 820, height: 580)
            .windowResizability(.contentMinSize)

        MenuBarExtra("ScreenSpan Wallpaper", systemImage: "display.2", isInserted: $showMenuBarIcon) {
            WallpaperMenu(model: model)
        }
    }
}
