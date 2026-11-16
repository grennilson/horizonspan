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

    func render(_ image: CGImage, for display: Display, to url: URL) throws {
        guard let context = CGContext(data: nil, width: display.pixelWidth, height: display.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw WallpaperError.render(display.name)
        }
        let screen = rect(for: display)
        let xScale = CGFloat(display.pixelWidth) / screen.width
        let yScale = CGFloat(display.pixelHeight) / screen.height
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: display.pixelWidth, height: display.pixelHeight))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (imageRect.minX - screen.minX) * xScale,
                                       y: (screen.maxY - imageRect.maxY) * yScale,
                                       width: imageRect.width * xScale, height: imageRect.height * yScale))
        guard let output = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
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
                     completion: @escaping (Result<URL, Error>) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                completion(.success(url))
            } else {
                completion(.failure(error ?? WallpaperError.image))
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
    var canChooseImage: Bool { !isBusy && !choosingImage && !showEdgeOptions }
    var undoTitle: String { undoEdits.last.map { "Undo \($0.name)" } ?? "Undo" }
    var redoTitle: String { redoEdits.last.map { "Redo \($0.name)" } ?? "Redo" }
    var canUndo: Bool { canChooseImage && !undoEdits.isEmpty }
    var canRedo: Bool { canChooseImage && !redoEdits.isEmpty }
    private var currentImage: FramedImage? {
        source.map { FramedImage(source: $0, framing: framing, zoom: zoom, pan: pan) }
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
    private let store = try? WallpaperStore.userStore()
    private var observers = Set<AnyCancellable>()
    private var restoreTask: Task<Void, Never>?

    init() {
        saved = store?.current()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.displays = Display.connected()
                self?.scheduleRestore(when: WallpaperPreferences.restoreOnDisplays)
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
        scheduleRestore {
            WallpaperPreferences.restoreOnDisplays() || WallpaperPreferences.syncSpaces()
        }
    }

    func chooseImage() {
        guard canChooseImage else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        choosingImage = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.choosingImage = false
            if response == .OK, let url = panel.url { self.loadImage(url) }
        }
    }

    func loadImage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            source = try SourceImage(url: url)
            original = nil
            undoEdits.removeAll()
            redoEdits.removeAll()
            showOriginal = false
            edgeDescription = ""
            framing = .fit
            zoom = 1
            pan = .zero
            status = ""
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
    }

    func apply() {
        let targets = Display.connected()
        guard let source, !targets.isEmpty, !isBusy, !showOriginal else { return }
        guard let store else {
            errorMessage = WallpaperError.save.localizedDescription
            return
        }
        let wallpaper = SavedWallpaper(source: source, framing: framing, zoom: zoom, pan: pan)
        isApplying = true
        status = ""
        Task {
            defer { isApplying = false }
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try store.store(source.image, as: wallpaper)
                    return try store.render(source.image, wallpaper: wallpaper, displays: targets)
                }.value
                try assign(urls, to: targets, skipMatching: false) {
                    do { try store.select(wallpaper) }
                    catch { throw WallpaperError.save }
                }
                saved = wallpaper
                status = "Applied to \(targets.count) \(targets.count == 1 ? "display" : "displays")"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleRestore(when enabled: @escaping () -> Bool) {
        guard saved != nil, enabled() else { return }
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            // A display or Space change can finish after macOS sends the notification.
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, enabled() else { return }
            await self?.restore(force: true, when: enabled)
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, enabled() else { return }
            await self?.restore(force: false, when: enabled)
        }
    }

    func reapplySavedWallpaper() {
        restoreTask?.cancel()
        restoreTask = Task { await restore(force: true, reportResult: true) }
    }

    private func restore(force: Bool, reportResult: Bool = false, when enabled: () -> Bool = { true }) async {
        guard let store, let wallpaper = saved else { return }
        while isApplying {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        guard wallpaper.id == saved?.id, !Task.isCancelled, enabled() else { return }
        let targets = Display.connected()
        guard !targets.isEmpty else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            let (source, urls) = try await Task.detached(priority: .utility) {
                let source = try store.source(for: wallpaper)
                let urls = try store.render(source.image, wallpaper: wallpaper, displays: targets)
                return (source, urls)
            }.value
            guard !Task.isCancelled, enabled() else { return }
            try assign(urls, to: targets, skipMatching: !force)
            if self.source == nil {
                self.source = source
                framing = wallpaper.framing
                zoom = wallpaper.zoom
                pan = wallpaper.pan
            }
            if reportResult { status = "Restored saved wallpaper" }
        } catch {
            if reportResult && !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
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
                         ?? "Choose one image for all your displays.")
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Choose Image…", action: model.chooseImage)
                    .keyboardShortcut("o")
                    .onDrop(of: [.fileURL], isTargeted: nil, perform: receiveImageDrop)
                    .disabled(!model.canChooseImage)
            }

            GeometryReader { geometry in
                if let source, !displays.isEmpty {
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
                        Text(displays.isEmpty ? "No displays detected" : "Drag an image here")
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
                if source != nil && !model.showOriginal {
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
                    .disabled(model.isBusy || model.showOriginal)
                    Spacer()
                }
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
                .disabled(model.showOriginal)
                Button("Reset", action: resetFramingPosition)
                    .disabled(model.showOriginal)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Button("Apply Wallpaper", action: model.apply).buttonStyle(.borderedProminent)
                    .disabled(model.source == nil || displays.isEmpty || model.isBusy || model.showOriginal)
            }
            .disabled(model.source == nil || model.isBusy)
        }
        .padding(24)
        .frame(minWidth: 735, minHeight: 490)
        .sheet(isPresented: $model.showEdgeOptions) {
            edgeOptions
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
                case .success(let url): model.loadImage(url)
                case .failure: model.errorMessage = "Drop an image file from Finder."
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
        .disabled(model.isBusy)
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
    private func assign(_ urls: [URL], to targets: [Display], skipMatching: Bool,
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
                }
            }
            Section("Wallpaper") {
                Toggle("Sync wallpaper across macOS desktops", isOn: $syncSpaces)
                Toggle("Reapply wallpaper when displays change or wake", isOn: $restoreOnDisplays)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470, height: 285)
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
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",")
        }
    }
}

final class HorizonSpanDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct HorizonSpanApp: App {
    @NSApplicationDelegateAdaptor(HorizonSpanDelegate.self) private var delegate
    @StateObject private var model = WallpaperState()
    @AppStorage(WallpaperPreferences.menuBarKey) private var showMenuBarIcon = true

    var body: some Scene {
        WindowGroup("ScreenSpan Wallpaper", id: "main", for: Bool.self) { _ in
            WallpaperView(model: model)
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

        MenuBarExtra("ScreenSpan Wallpaper", systemImage: "display.2", isInserted: $showMenuBarIcon) {
            WallpaperMenu(model: model)
        }
    }
}
