import AppKit
import ImageIO
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

struct WallpaperLayout {
    let bounds: CGRect
    let imageRect: CGRect

    init(displays: [Display], imageSize: CGSize, zoom: CGFloat, pan: CGSize) {
        bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height) * zoom
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let x = min(max(pan.width * bounds.width, -(size.width - bounds.width) / 2), (size.width - bounds.width) / 2)
        let y = min(max(pan.height * bounds.height, -(size.height - bounds.height) / 2), (size.height - bounds.height) / 2)
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
    case image, displays, render(String), apply(String, Bool)

    var errorDescription: String? {
        switch self {
        case .image: return "This image couldn’t be opened."
        case .displays: return "Your display arrangement changed. Check the preview and try again."
        case .render(let name): return "Couldn’t create the wallpaper for \(name)."
        case .apply(let name, let restored):
            return restored ? "Couldn’t apply the wallpaper to \(name). Earlier changes were restored."
                : "Couldn’t apply the wallpaper to \(name). Some displays may still show the new image."
        }
    }
}

struct SourceImage {
    let url: URL
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
        self.url = url
        self.image = image
    }

    var size: CGSize { CGSize(width: image.width, height: image.height) }
}

@MainActor
final class WallpaperState: ObservableObject {
    @Published var displays = Display.connected()
    @Published var source: SourceImage?
    @Published var zoom: CGFloat = 1
    @Published var pan = CGSize.zero
    @Published var status = ""
    @Published var isApplying = false
    @Published var errorMessage: String?
}

struct WallpaperView: View {
    @StateObject private var model = WallpaperState()
    @GestureState private var drag = CGSize.zero

    var body: some View {
        let displays = model.displays
        let source = model.source
        let zoom = model.zoom
        let pan = model.pan
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HorizonSpan").font(.title.bold())
                    Text(source?.url.lastPathComponent ?? "Choose one image for all your displays.")
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Choose Image…", action: chooseImage).keyboardShortcut("o")
                    .disabled(model.isApplying)
            }

            GeometryReader { geometry in
                if let source, !displays.isEmpty {
                    let layout = WallpaperLayout(displays: displays, imageSize: source.size, zoom: zoom, pan: pan)
                    let scale = min(max(geometry.size.width - 44, 1) / layout.bounds.width,
                                    max(geometry.size.height - 44, 1) / layout.bounds.height)
                    let width = layout.bounds.width * scale
                    let height = layout.bounds.height * scale
                    let active = WallpaperLayout(displays: displays, imageSize: source.size, zoom: zoom,
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
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            guard !model.isApplying else { return }
                            let next = WallpaperLayout(displays: displays, imageSize: source.size, zoom: zoom,
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
                        Text(displays.isEmpty ? "No displays detected" : "Choose an image to preview your wallpaper")
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))

            HStack(spacing: 13) {
                ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                    Text("\(index + 1)  \(display.name)").font(.caption).lineLimit(1)
                }
                Spacer()
                if source != nil { Text("Drag the preview to reposition").font(.caption).foregroundStyle(.secondary) }
            }

            Divider()
            HStack {
                Text("Zoom")
                Slider(value: $model.zoom, in: 1...3).frame(width: 120).accessibilityLabel("Zoom")
                Button("Reset") { model.zoom = 1; model.pan = .zero; model.status = "" }
                Spacer()
                if model.isApplying { ProgressView().controlSize(.small) }
                Text(model.status).font(.callout).foregroundStyle(.secondary)
                Button("Apply Wallpaper", action: apply).buttonStyle(.borderedProminent)
                    .disabled(model.source == nil || displays.isEmpty || model.isApplying)
            }
            .disabled(model.source == nil)
        }
        .padding(24)
        .frame(minWidth: 690, minHeight: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.displays = Display.connected()
        }
        .onChange(of: zoom) { _ in model.status = "" }
        .alert("HorizonSpan", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            model.source = try SourceImage(url: url)
            model.zoom = 1
            model.pan = .zero
            model.status = ""
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func apply() {
        guard let source = model.source, !model.displays.isEmpty, !model.isApplying else { return }
        let targets = model.displays
        let layout = WallpaperLayout(displays: targets, imageSize: source.size, zoom: model.zoom, pan: model.pan)
        model.isApplying = true
        model.status = ""
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                    .appendingPathComponent("HorizonSpan/Rendered/\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let urls = try targets.map { display in
                    let url = directory.appendingPathComponent("display-\(display.id).png")
                    try layout.render(source.image, for: display, to: url)
                    return url
                }
                DispatchQueue.main.async {
                    defer { model.isApplying = false }
                    do {
                        try assign(urls, to: targets)
                        model.status = "Applied to \(targets.count) \(targets.count == 1 ? "display" : "displays")"
                    } catch { model.errorMessage = error.localizedDescription }
                }
            } catch {
                DispatchQueue.main.async {
                    model.isApplying = false
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func assign(_ urls: [URL], to targets: [Display]) throws {
        let screens = NSScreen.screens
        guard zip(targets, Display.connected()).allSatisfy({ $0.id == $1.id && $0.frame == $1.frame &&
            $0.pixelWidth == $1.pixelWidth && $0.pixelHeight == $1.pixelHeight }),
            targets.count == screens.count else { throw WallpaperError.displays }
        let workspace = NSWorkspace.shared
        var applied: [(NSScreen, URL?, [NSWorkspace.DesktopImageOptionKey: Any])] = []
        for (display, url) in zip(targets, urls) {
            guard let screen = screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.id
            }) else { throw WallpaperError.displays }
            let oldURL = workspace.desktopImageURL(for: screen)
            let oldOptions = workspace.desktopImageOptions(for: screen) ?? [:]
            do {
                try workspace.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                    .allowClipping: false
                ])
                applied.append((screen, oldURL, oldOptions))
            } catch {
                var restored = true
                for (changed, previous, options) in applied.reversed() {
                    guard let previous else { restored = false; continue }
                    do { try workspace.setDesktopImageURL(previous, for: changed, options: options) }
                    catch { restored = false }
                }
                throw WallpaperError.apply(display.name, restored)
            }
        }
    }
}

@main
struct HorizonSpanApp: App {
    var body: some Scene {
        Window("HorizonSpan", id: "main") { WallpaperView() }
            .defaultSize(width: 820, height: 540)
            .windowResizability(.contentMinSize)
    }
}
