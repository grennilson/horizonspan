import AppKit
import ImageIO

struct LibraryEntry: Identifiable {
    let id: UUID
    let url: URL
    var title: String
    var favorite: Bool
    let date: Date
    var thumbnailImage: NSImage {
        guard let input = CGImageSourceCreateWithURL(thumbnail as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 700
              ] as CFDictionary) else { return NSImage() }
        return NSImage(cgImage: image, size: .zero)
    }

    var thumbnail: URL {
        let small = url.appendingPathComponent("Thumbnail.png")
        return FileManager.default.fileExists(atPath: small.path) ? small : url.appendingPathComponent("Wallpaper.png")
    }
}

struct LibraryDetails: Codable {
    var title: String
    var favorite: Bool
}

struct SetupProfile: Codable {
    var name: String
    var projectID: UUID
}

struct LibraryIndex: Codable {
    var entries: [String: LibraryDetails] = [:]
    var setups: [String: SetupProfile] = [:]
}

struct WallpaperLibraryStore {
    let root: URL

    init(root: URL? = nil) throws {
        self.root = try root ?? WallpaperProject.library()
    }

    func index() throws -> LibraryIndex {
        let file = root.appendingPathComponent(".Library.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return LibraryIndex() }
        return try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: file))
    }

    func write(_ index: LibraryIndex) throws {
        try JSONEncoder().encode(index).write(to: root.appendingPathComponent(".Library.json"), options: .atomic)
    }

    func entries(index: LibraryIndex) throws -> [LibraryEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey],
                                                               options: [.skipsHiddenFiles])
        return urls.filter { $0.pathExtension.lowercased() == "ssw" }.compactMap { url in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("Settings.json")),
                  let project = try? JSONDecoder().decode(WallpaperProject.self, from: data),
                  (1...2).contains(project.formatVersion), project.wallpaper.design?.isValid ?? true else { return nil }
            let id = project.wallpaper.id
            let details = index.entries[id.uuidString]
            let title = details?.title ?? URL(fileURLWithPath: project.wallpaper.filename).deletingPathExtension().lastPathComponent
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return LibraryEntry(id: id, url: url, title: title, favorite: details?.favorite ?? false, date: date)
        }.sorted { $0.date > $1.date }
    }
}

struct ReleaseInfo: Decodable {
    let tag_name: String
    let html_url: URL
}

enum ReleaseVersion {
    static func components(_ value: String) -> [Int]? {
        let clean = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
            return Int(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard var a = components(candidate), var b = components(current) else { return false }
        let count = max(a.count, b.count)
        a += Array(repeating: 0, count: count - a.count)
        b += Array(repeating: 0, count: count - b.count)
        return b.lexicographicallyPrecedes(a)
    }
}
