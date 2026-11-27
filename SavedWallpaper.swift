import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

struct SavedWallpaper: Codable {
    let id: UUID
    let revision: UUID?
    let filename: String
    let framing: ImageFraming
    let zoom: CGFloat
    let pan: CGSize
    let design: WallpaperDesign?

    init(source: SourceImage, framing: ImageFraming, zoom: CGFloat, pan: CGSize, design: WallpaperDesign? = nil, id: UUID = UUID(), revision: UUID? = nil) {
        self.id = id
        self.revision = revision
        filename = source.filename
        self.framing = framing
        self.zoom = zoom
        self.pan = pan
        self.design = design
    }
}

struct WallpaperStore {
    let root: URL

    static func userStore() throws -> WallpaperStore {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return WallpaperStore(root: support.appendingPathComponent("HorizonSpan/Saved", isDirectory: true))
    }

    private var selection: URL { root.appendingPathComponent("Current.json") }

    func current() -> SavedWallpaper? {
        guard let data = try? Data(contentsOf: selection) else { return nil }
        return try? JSONDecoder().decode(SavedWallpaper.self, from: data)
    }

    func select(_ wallpaper: SavedWallpaper) throws {
        try JSONEncoder().encode(wallpaper).write(to: selection, options: .atomic)
    }

    func store(_ image: CGImage, as wallpaper: SavedWallpaper, assets: [Int: SourceImage] = [:]) throws {
        let folder = directory(for: wallpaper)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Source.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WallpaperError.save }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.save }
        try WallpaperProject.writeAssets(assets, settings: wallpaper, to: folder)
    }

    func assets(for wallpaper: SavedWallpaper) throws -> [Int: SourceImage] {
        try WallpaperProject.assets(at: directory(for: wallpaper), settings: wallpaper)
    }

    func source(for wallpaper: SavedWallpaper) throws -> SourceImage {
        let url = directory(for: wallpaper).appendingPathComponent("Source.png")
        guard let input = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { throw WallpaperError.image }
        return SourceImage(filename: wallpaper.filename, image: image)
    }

    func render(_ image: CGImage, wallpaper: SavedWallpaper, displays: [Display], assets: [Int: SourceImage] = [:]) throws -> [URL] {
        let geometry = "physical-displays-v2|" + WallpaperDesign.setupKey(displays) + "|" + (wallpaper.revision?.uuidString ?? "original")
        let folder = directory(for: wallpaper)
        let key = SHA256.hash(data: Data(geometry.utf8)).map { String(format: "%02x", $0) }.joined()
        let output = folder.appendingPathComponent(key, isDirectory: true)
        let urls = displays.map {
            let identity = SHA256.hash(data: Data($0.hardwareKey.utf8)).map { String(format: "%02x", $0) }.joined()
            return output.appendingPathComponent("display-\(identity).png")
        }
        let files = FileManager.default
        if zip(urls, displays).allSatisfy({ url, display in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
            return width == display.pixelWidth && height == display.pixelHeight
        }) { return urls }

        let staging = folder.appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let images = try WallpaperRenderer.images(source: image, wallpaper: wallpaper, displays: displays, assets: assets)
        for (image, url) in zip(images, urls) {
            try WallpaperProject.write(image, to: staging.appendingPathComponent(url.lastPathComponent))
        }
        if files.fileExists(atPath: output.path) {
            _ = try files.replaceItemAt(output, withItemAt: staging)
        } else {
            try files.moveItem(at: staging, to: output)
        }
        return urls
    }

    private func directory(for wallpaper: SavedWallpaper) -> URL {
        root.appendingPathComponent(wallpaper.id.uuidString, isDirectory: true)
    }
}
