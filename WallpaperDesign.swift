import AppKit
import CoreImage

struct WallpaperAppearance: Codable, Equatable {
    var brightness: Double = 0
    var saturation: Double = 1
    var dim: Double = 0
    var red: Double = 0
    var green: Double = 0
    var blue: Double = 0

    var background: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    var isValid: Bool {
        (-0.5...0.5).contains(brightness) && (0...2).contains(saturation) && (0...0.8).contains(dim)
            && (0...1).contains(red) && (0...1).contains(green) && (0...1).contains(blue)
    }

    func image(_ image: CGImage) throws -> CGImage {
        guard self != WallpaperAppearance() else { return image }
        let input = CIImage(cgImage: image)
        let colored = input.applyingFilter("CIColorControls",
            parameters: [kCIInputBrightnessKey: brightness, kCIInputSaturationKey: saturation])
        let multiplier = 1 - dim
        let output = colored.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: multiplier, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: multiplier, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: multiplier, w: 0)
        ])
        guard let result = Self.context.createCGImage(output, from: input.extent) else { throw WallpaperError.image }
        return result
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
}

struct MonitorPlacement: Codable, Equatable {
    var key: String
    var group = 0
    var offsetX: Double = 0
    var offsetY: Double = 0
    var sizeScale: Double = 1

    var isValid: Bool {
        (0...32).contains(group) && (-20000...20000).contains(offsetX)
            && (-20000...20000).contains(offsetY) && (0.25...4).contains(sizeScale)
    }
}

struct WallpaperDesign: Codable, Equatable {
    var appearance = WallpaperAppearance()
    var monitors: [MonitorPlacement] = []
    var customGroups: [Int] = []

    static let standard = WallpaperDesign()

    func placement(for display: Display) -> MonitorPlacement {
        monitors.first { $0.key == display.hardwareKey } ?? MonitorPlacement(key: display.hardwareKey)
    }

    var isValid: Bool {
        appearance.isValid && monitors.count <= 32 && monitors.allSatisfy(\.isValid)
            && Set(monitors.map(\.key)).count == monitors.count
            && customGroups.allSatisfy { (1...32).contains($0) }
            && Set(customGroups).count == customGroups.count
    }

    static func setupKey(_ displays: [Display]) -> String {
        let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
        return displays.map {
            "\($0.hardwareKey):\($0.pixelWidth)x\($0.pixelHeight):\($0.frame.minX - bounds.minX),\($0.frame.minY - bounds.minY),\($0.frame.width),\($0.frame.height)"
        }.sorted().joined(separator: "|")
    }
}

enum WallpaperRenderer {
    static func images(source: CGImage, wallpaper: SavedWallpaper, displays: [Display],
                       assets: [Int: SourceImage] = [:], preview: Bool = false) throws -> [CGImage] {
        let design = wallpaper.design ?? .standard
        let virtual = displays.map { display -> Display in
            let placement = design.placement(for: display)
            let frame = CGRect(x: display.frame.minX + placement.offsetX,
                               y: display.frame.minY + placement.offsetY,
                               width: display.frame.width * placement.sizeScale,
                               height: display.frame.height * placement.sizeScale)
            let limit: CGFloat = preview ? min(1, 640 / CGFloat(max(display.pixelWidth, display.pixelHeight))) : 1
            return Display(id: display.id, name: display.name, frame: frame,
                           pixelWidth: max(1, Int(CGFloat(display.pixelWidth) * limit)),
                           pixelHeight: max(1, Int(CGFloat(display.pixelHeight) * limit)), persistentID: display.hardwareKey)
        }
        var prepared: [Int: CGImage] = [:]
        return try displays.enumerated().map { index, display in
            let group = design.placement(for: display).group
            if prepared[group] == nil {
                let input = assets[group]?.image ?? source
                prepared[group] = try design.appearance.image(preview ? reduced(input) : input)
            }
            let members = displays.indices.filter { design.placement(for: displays[$0]).group == group }.map { virtual[$0] }
            let image = prepared[group]!
            let layout = WallpaperLayout(displays: members, imageSize: CGSize(width: image.width, height: image.height),
                                         framing: wallpaper.framing, zoom: wallpaper.zoom, pan: wallpaper.pan)
            return try layout.image(image, for: virtual[index], background: design.appearance.background)
        }
    }

    private static func reduced(_ image: CGImage) throws -> CGImage {
        let scale = min(1, 1600 / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw WallpaperError.image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { throw WallpaperError.image }
        return result
    }

    static func combined(_ images: [CGImage], displays: [Display], maxPixels: CGFloat = 64_000_000) throws -> CGImage {
        guard !displays.isEmpty, displays.count == images.count else { throw WallpaperError.displays }
        let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
        let density = displays.reduce(CGFloat(1)) {
            max($0, CGFloat($1.pixelWidth) / $1.frame.width, CGFloat($1.pixelHeight) / $1.frame.height)
        }
        let scale = min(density, sqrt(maxPixels / (bounds.width * bounds.height)))
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw WallpaperError.image }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (image, screen) in zip(images, displays) {
            context.draw(image, in: CGRect(x: (screen.frame.minX - bounds.minX) * scale,
                                           y: (screen.frame.minY - bounds.minY) * scale,
                                           width: screen.frame.width * scale, height: screen.frame.height * scale))
        }
        guard let result = context.makeImage() else { throw WallpaperError.image }
        return result
    }
}
