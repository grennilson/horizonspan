import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

extension UTType {
    static let screenSpanWallpaper = UTType(exportedAs: "io.github.grennilson.screenspan.wallpaper",
                                            conformingTo: .package)
}

struct WallpaperProject: Codable {
    struct Screen: Codable {
        let name: String
        let frame: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
    }

    let formatVersion: Int
    let wallpaper: SavedWallpaper
    let displays: [Screen]
    var contentFingerprint: String? = nil

    private struct Content: Encodable {
        let filename: String
        let framing: ImageFraming
        let zoom: CGFloat
        let pan: CGSize
        let design: WallpaperDesign
        let displays: [Screen]
    }

    private static func description(wallpaper: SavedWallpaper, displays: [Screen]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Content(filename: wallpaper.filename, framing: wallpaper.framing,
            zoom: wallpaper.zoom, pan: wallpaper.pan, design: wallpaper.design ?? .standard, displays: displays))
    }

    private static func fingerprint(source: SourceImage, wallpaper: SavedWallpaper, displays: [Screen],
                                    assets: [Int: SourceImage]) throws -> String {
        var hash = SHA256()
        hash.update(data: try description(wallpaper: wallpaper, displays: displays))
        func add(_ image: CGImage) throws {
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                let bytes = context.data else { throw WallpaperError.save }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            hash.update(data: Data("|\(image.width)x\(image.height)|".utf8))
            withExtendedLifetime(context) {
                hash.update(data: Data(bytesNoCopy: bytes, count: image.width * image.height * 4, deallocator: .none))
            }
        }
        try add(source.image)
        for group in (wallpaper.design?.customGroups ?? []).sorted() {
            guard let image = assets[group]?.image else { throw WallpaperError.save }
            hash.update(data: Data("|group=\(group)|".utf8))
            try add(image)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func manifest(at url: URL) throws -> WallpaperProject {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url.appendingPathComponent("Settings.json")))
    }

    static func library() throws -> URL {
        let pictures = try FileManager.default.url(for: .picturesDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let library = pictures.appendingPathComponent("ScreenSpan Wallpaper", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        return library
    }

    static func save(source: SourceImage, wallpaper: SavedWallpaper, displays: [Display],
                     library: URL? = nil, assets: [Int: SourceImage] = [:], preferredID: UUID? = nil) throws -> URL {
        guard !displays.isEmpty else { throw WallpaperError.displays }
        let library = try library ?? self.library()
        let files = FileManager.default
        try files.createDirectory(at: library, withIntermediateDirectories: true)
        let screens = displays.map { Screen(name: $0.name, frame: $0.frame, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight) }
        let wantedDescription = try description(wallpaper: wallpaper, displays: screens)
        let contentKey = try fingerprint(source: source, wallpaper: wallpaper, displays: screens, assets: assets)
        let candidates = try files.contentsOfDirectory(at: library, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]).filter { $0.pathExtension.lowercased() == "ssw" }.sorted {
                let first = (try? manifest(at: $0).wallpaper.id) == preferredID
                let second = (try? manifest(at: $1).wallpaper.id) == preferredID
                return first != second ? first : $0.lastPathComponent < $1.lastPathComponent
            }
        for candidate in candidates {
            guard let project = try? manifest(at: candidate), (1...2).contains(project.formatVersion),
                  project.contentFingerprint == nil || project.contentFingerprint == contentKey,
                  (try? description(wallpaper: project.wallpaper, displays: project.displays)) == wantedDescription,
                  let existing = try? open(candidate),
                  let groups = try? self.assets(at: candidate, settings: project.wallpaper) else { continue }
            let exports = ["Wallpaper.png", "Thumbnail.png"] + screens.indices.map { "Displays/Display-\($0 + 1).png" }
            guard exports.allSatisfy({ files.fileExists(atPath: candidate.appendingPathComponent($0).path) }) else { continue }
            if (try? fingerprint(source: existing.0, wallpaper: project.wallpaper, displays: project.displays, assets: groups)) == contentKey {
                return candidate
            }
        }
        let stem = URL(fileURLWithPath: source.filename).deletingPathExtension().lastPathComponent
        let name = String((stem.isEmpty ? "Wallpaper" : stem).prefix(100))
        var selection = wallpaper
        var output = library.appendingPathComponent("\(name) - \(selection.id.uuidString).ssw", isDirectory: true)
        if files.fileExists(atPath: output.path) {
            selection = SavedWallpaper(source: source, framing: wallpaper.framing, zoom: wallpaper.zoom,
                                       pan: wallpaper.pan, design: wallpaper.design)
            output = library.appendingPathComponent("\(name) - \(selection.id.uuidString).ssw", isDirectory: true)
        }
        let staging = library.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }

        let project = WallpaperProject(formatVersion: 2, wallpaper: selection, displays: screens, contentFingerprint: contentKey)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: staging.appendingPathComponent("Settings.json"))
        try write(source.image, to: staging.appendingPathComponent("Image.png"))

        try writeAssets(assets, settings: wallpaper, to: staging)
        let rendered = try WallpaperRenderer.images(source: source.image, wallpaper: wallpaper, displays: displays, assets: assets)
        let combined = try WallpaperRenderer.combined(rendered, displays: displays)
        try write(combined, to: staging.appendingPathComponent("Wallpaper.png"))
        let thumbnail = try WallpaperRenderer.combined(rendered, displays: displays, maxPixels: 240_000)
        try write(thumbnail, to: staging.appendingPathComponent("Thumbnail.png"))
        let screensFolder = staging.appendingPathComponent("Displays", isDirectory: true)
        try files.createDirectory(at: screensFolder, withIntermediateDirectories: false)
        for (index, image) in rendered.enumerated() {
            try write(image, to: screensFolder.appendingPathComponent("Display-\(index + 1).png"))
        }
        try files.moveItem(at: staging, to: output)
        return output
    }

    static func open(_ url: URL) throws -> (SourceImage, SavedWallpaper) {
        let project = try JSONDecoder().decode(Self.self,
            from: Data(contentsOf: url.appendingPathComponent("Settings.json")))
        let settings = project.wallpaper
        guard (1...2).contains(project.formatVersion), (settings.design?.isValid ?? true), settings.zoom.isFinite, (1...3).contains(settings.zoom),
              settings.pan.width.isFinite, settings.pan.height.isFinite else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let image = try SourceImage(url: url.appendingPathComponent("Image.png"))
        return (SourceImage(filename: settings.filename, image: image.image), settings)
    }

    static func assets(at folder: URL, settings: SavedWallpaper) throws -> [Int: SourceImage] {
        var result: [Int: SourceImage] = [:]
        guard settings.design?.isValid ?? true else { throw CocoaError(.fileReadCorruptFile) }
        for group in settings.design?.customGroups ?? [] {
            result[group] = try SourceImage(url: folder.appendingPathComponent("Group-\(group).png"))
        }
        return result
    }

    static func writeAssets(_ assets: [Int: SourceImage], settings: SavedWallpaper, to folder: URL) throws {
        for group in settings.design?.customGroups ?? [] {
            guard let image = assets[group]?.image else { throw CocoaError(.fileReadCorruptFile) }
            try write(image, to: folder.appendingPathComponent("Group-\(group).png"))
        }
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WallpaperError.save }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw WallpaperError.save }
    }
}
