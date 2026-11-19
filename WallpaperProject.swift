import AppKit
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

    static func library() throws -> URL {
        let pictures = try FileManager.default.url(for: .picturesDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let library = pictures.appendingPathComponent("ScreenSpan Wallpaper", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        return library
    }

    static func save(source: SourceImage, wallpaper: SavedWallpaper, displays: [Display],
                     library: URL? = nil, assets: [Int: SourceImage] = [:]) throws -> URL {
        guard !displays.isEmpty else { throw WallpaperError.displays }
        let library = try library ?? self.library()
        let files = FileManager.default
        try files.createDirectory(at: library, withIntermediateDirectories: true)
        let stem = URL(fileURLWithPath: source.filename).deletingPathExtension().lastPathComponent
        let name = String((stem.isEmpty ? "Wallpaper" : stem).prefix(100))
        let output = library.appendingPathComponent("\(name) - \(wallpaper.id.uuidString).ssw", isDirectory: true)
        if files.fileExists(atPath: output.path) { return output }
        let staging = library.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }

        let project = WallpaperProject(formatVersion: 2, wallpaper: wallpaper, displays: displays.map {
            Screen(name: $0.name, frame: $0.frame, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
        })
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
        let screens = staging.appendingPathComponent("Displays", isDirectory: true)
        try files.createDirectory(at: screens, withIntermediateDirectories: false)
        for (index, image) in rendered.enumerated() {
            try write(image, to: screens.appendingPathComponent("Display-\(index + 1).png"))
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
