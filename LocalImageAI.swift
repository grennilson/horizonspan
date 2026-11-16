import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageAIAction: String {
    case extend, fade, enhance

    var title: String {
        switch self {
        case .extend: return "Extend Edges"
        case .fade: return "Fade to Black"
        case .enhance: return "Enhance Detail"
        }
    }

    var result: String {
        switch self {
        case .extend: return "Edges extended"
        case .fade: return "Edges faded to black"
        case .enhance: return "Detail enhanced"
        }
    }
}

struct ImageAIPlan {
    let width: Int
    let height: Int
    let leadingExtension: Int

    init?(_ action: ImageAIAction, image: CGImage, displays: [Display], framing: ImageFraming,
          zoom: CGFloat, pan: CGSize = .zero) {
        let bounds = displays.reduce(CGRect.null) { $0.union($1.frame) }
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }

        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let ratio = bounds.width / bounds.height
        switch action {
        case .extend, .fade:
            let sourceRatio = sourceWidth / sourceHeight
            // Rounding an extension to whole pixels can leave a subpixel aspect mismatch.
            guard abs(sourceRatio / ratio - 1) > 0.0025 else { return nil }
            if sourceRatio < ratio {
                width = Int((sourceHeight * ratio).rounded())
                height = image.height
            } else {
                width = image.width
                height = Int((sourceWidth / ratio).rounded())
            }
            let horizontal = width > image.width
            let space = horizontal ? width - image.width : height - image.height
            let offset = (horizontal ? pan.width : pan.height) * CGFloat(horizontal ? width : height)
            let position = min(max(CGFloat(space) / 2 + offset, 0), CGFloat(space))
            leadingExtension = Int(position.rounded())
        case .enhance:
            leadingExtension = 0
            let density = displays.reduce(CGFloat(1)) { density, display in
                max(density, CGFloat(display.pixelWidth) / display.frame.width,
                    CGFloat(display.pixelHeight) / display.frame.height)
            }
            let scale = framing.scale(image: CGSize(width: sourceWidth, height: sourceHeight), in: bounds.size) * density * zoom
            let pixelLimit = sqrt(64_000_000 / (sourceWidth * sourceHeight))
            let factor = min(scale, 4, pixelLimit)
            guard factor > 1.01 else { return nil }
            width = Int((sourceWidth * factor).rounded(.down))
            height = Int((sourceHeight * factor).rounded(.down))
        }
        guard width >= image.width, height >= image.height,
              width != image.width || height != image.height else { return nil }
    }
}

enum LocalImageAI {
    static var isSupported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static func run(_ action: ImageAIAction, image: CGImage, plan: ImageAIPlan, prompt: String = "",
                    onProgress: (String) -> Void) throws -> CGImage {
        guard plan.width * plan.height <= 64_000_000 else { throw Failure.tooLarge }
        if action == .fade {
            return try fadeEdges(image, plan: plan)
        }
        guard isSupported else { throw Failure.unsupported }
        let files = FileManager.default
        let support = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
        let runtime = support.appendingPathComponent("HorizonSpan/LocalAI-v1", isDirectory: true)
        let temporary = files.temporaryDirectory.appendingPathComponent("HorizonSpan-\(UUID().uuidString)",
                                                                        isDirectory: true)
        try files.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: temporary) }

        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("LocalAI", isDirectory: true),
              files.fileExists(atPath: resources.appendingPathComponent("setup.sh").path) else {
            throw Failure.missingResources
        }
        let input = temporary.appendingPathComponent("input.png")
        let output = temporary.appendingPathComponent("result.png")
        let log = temporary.appendingPathComponent("worker.log")
        guard let encoder = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.image }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw Failure.image }

        try runProcess(URL(fileURLWithPath: "/bin/bash"),
                       [resources.appendingPathComponent("setup.sh").path, runtime.path],
                       log: log, onProgress: onProgress)
        var arguments = [resources.appendingPathComponent("image_tools.py").path, action.rawValue,
                         input.path, output.path, runtime.appendingPathComponent("models").path,
                         String(plan.width), String(plan.height)]
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == .extend {
            arguments.append("--leading-extension=\(plan.leadingExtension)")
            if !description.isEmpty {
                arguments.append("--prompt=" + String(description.prefix(400)))
            }
        }
        try runProcess(runtime.appendingPathComponent("env/bin/python"), arguments,
                       log: log, onProgress: onProgress)

        guard let decoder = CGImageSourceCreateWithURL(output as CFURL, nil),
              let result = CGImageSourceCreateImageAtIndex(decoder, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              result.width == plan.width, result.height == plan.height else { throw Failure.image }
        return result
    }

    private static func fadeEdges(_ image: CGImage, plan: ImageAIPlan) throws -> CGImage {
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let canvas = CGContext(data: nil, width: plan.width, height: plan.height,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let fade = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(),
                                    colorComponents: [1, 1, 1, 0.9, 1, 0.44, 1, 0],
                                    locations: [0, 0.18, 0.55, 1], count: 4)
        else { throw Failure.image }
        let horizontal = plan.width > image.width
        let extra = horizontal ? plan.width - image.width : plan.height - image.height
        let trailing = extra - plan.leadingExtension
        let source = CGRect(x: horizontal ? plan.leadingExtension : 0, y: horizontal ? 0 : trailing,
                            width: image.width, height: image.height)
        let sourceLength = horizontal ? source.width : source.height
        let sampleLength = max(1, Int(sourceLength * 0.12))
        canvas.interpolationQuality = .high

        for (leading, gap) in [(true, plan.leadingExtension), (false, trailing)] where gap > 0 {
            let length = min(CGFloat(gap), max(1, (sourceLength * 0.34).rounded()))
            let sample: CGRect
            let band: CGRect
            let seam: CGPoint
            let end: CGPoint
            // Image crops start at the top left. The canvas starts at the bottom left.
            if horizontal {
                sample = CGRect(x: leading ? 0 : image.width - sampleLength, y: 0,
                                width: sampleLength, height: image.height)
                let edge = leading ? source.minX : source.maxX
                band = CGRect(x: leading ? edge - length : edge, y: source.minY,
                              width: length, height: source.height)
                seam = CGPoint(x: edge, y: source.midY)
                end = CGPoint(x: leading ? band.minX : band.maxX, y: source.midY)
            } else {
                sample = CGRect(x: 0, y: leading ? 0 : image.height - sampleLength,
                                width: image.width, height: sampleLength)
                let edge = leading ? source.maxY : source.minY
                band = CGRect(x: source.minX, y: leading ? edge : edge - length,
                              width: source.width, height: length)
                seam = CGPoint(x: source.midX, y: edge)
                end = CGPoint(x: source.midX, y: leading ? band.maxY : band.minY)
            }
            guard let edgeTexture = image.cropping(to: sample) else { throw Failure.image }
            canvas.saveGState()
            canvas.translateBy(x: horizontal ? band.minX + band.maxX : 0,
                               y: horizontal ? 0 : band.minY + band.maxY)
            canvas.scaleBy(x: horizontal ? -1 : 1, y: horizontal ? 1 : -1)
            canvas.draw(edgeTexture, in: band)
            canvas.restoreGState()

            canvas.saveGState()
            canvas.clip(to: band)
            canvas.setBlendMode(.destinationIn)
            canvas.drawLinearGradient(fade, start: seam, end: end, options: [])
            canvas.restoreGState()
        }

        canvas.setBlendMode(.destinationOver)
        canvas.setFillColor(gray: 0, alpha: 1)
        canvas.fill(CGRect(x: 0, y: 0, width: plan.width, height: plan.height))
        canvas.setBlendMode(.normal)
        canvas.interpolationQuality = .none
        canvas.draw(image, in: source)
        guard let result = canvas.makeImage() else { throw Failure.image }
        return result
    }

    private static func runProcess(_ executable: URL, _ arguments: [String], log: URL,
                                   onProgress: (String) -> Void) throws {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let errors = try FileHandle(forWritingTo: log)
        defer { try? errors.close() }
        let pipe = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = errors
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        process.environment = environment
        try process.run()

        var buffered = Data()
        for data in sequence(first: pipe.fileHandleForReading.availableData, next: { previous in
            previous.isEmpty ? nil : pipe.fileHandleForReading.availableData
        }) where !data.isEmpty {
            buffered.append(data)
            while let newline = buffered.firstIndex(of: 10) {
                let message = String(decoding: buffered[..<newline], as: UTF8.self)
                if !message.isEmpty { onProgress(message) }
                buffered.removeSubrange(...newline)
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let details = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            let lastLine = details.split(whereSeparator: \.isNewline).last.map(String.init)
            throw Failure.worker(lastLine.map { String($0.prefix(280)) } ?? "")
        }
    }

    private enum Failure: LocalizedError {
        case unsupported, tooLarge, missingResources, image, worker(String)

        var errorDescription: String? {
            switch self {
            case .unsupported: return "Local AI requires an Apple Silicon Mac."
            case .tooLarge: return "The result would exceed 64 megapixels. Try a smaller source image."
            case .missingResources: return "The local AI tools are missing from this copy of ScreenSpan Wallpaper."
            case .image: return "The local AI result could not be opened."
            case .worker(let details):
                return details.isEmpty ? "Local AI stopped before finishing." : "Local AI stopped before finishing.\n\n\(details)"
            }
        }
    }
}
