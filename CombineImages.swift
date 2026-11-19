import CoreGraphics
import SwiftUI

enum ImageArrangement: String, CaseIterable {
    case horizontal = "Side by Side"
    case vertical = "Stacked"

    func rectangles(for images: [SourceImage]) -> [CGRect] {
        let crossSize = images.map { self == .horizontal ? $0.size.height : $0.size.width }.min() ?? 0
        var offset: CGFloat = 0
        return images.map { image in
            let length = self == .horizontal
                ? (image.size.width * crossSize / image.size.height).rounded()
                : (image.size.height * crossSize / image.size.width).rounded()
            let rect = self == .horizontal
                ? CGRect(x: offset, y: 0, width: length, height: crossSize)
                : CGRect(x: 0, y: offset, width: crossSize, height: length)
            offset += length
            return rect
        }
    }

    func combine(_ images: [SourceImage]) throws -> SourceImage {
        guard images.count >= 2 else { throw WallpaperError.image }
        let rectangles = rectangles(for: images)
        let bounds = rectangles.reduce(CGRect.null) { $0.union($1) }
        let scale = min(1, sqrt(64_000_000 / (bounds.width * bounds.height)))
        let width = max(1, Int((bounds.width * scale).rounded(.down)))
        let height = max(1, Int((bounds.height * scale).rounded(.down)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw WallpaperError.image }
        context.interpolationQuality = .high
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (source, rect) in zip(images, rectangles) {
            // Round shared boundaries identically so adjacent images meet without a gap.
            let left = (rect.minX * CGFloat(width) / bounds.width).rounded()
            let right = (rect.maxX * CGFloat(width) / bounds.width).rounded()
            let top = (rect.minY * CGFloat(height) / bounds.height).rounded()
            let bottom = (rect.maxY * CGFloat(height) / bounds.height).rounded()
            context.draw(source.image, in: CGRect(x: left, y: CGFloat(height) - bottom,
                                                  width: right - left, height: bottom - top))
        }
        guard let image = context.makeImage() else { throw WallpaperError.image }
        let stem = URL(fileURLWithPath: images[0].filename).deletingPathExtension().lastPathComponent
        return SourceImage(filename: stem + " - Combined.png", image: image)
    }
}

struct CombineImagesView: View {
    @ObservedObject var model: WallpaperState

    var body: some View {
        let arrangement = model.combinationArrangement
        VStack(alignment: .leading, spacing: 16) {
            Text("Combine Images").font(.title2.bold())
            Picker("Arrangement", selection: $model.combinationArrangement) {
                ForEach(ImageArrangement.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            let images = model.imagesToCombine
            let rectangles = arrangement.rectangles(for: images)
            let bounds = rectangles.reduce(CGRect.null) { $0.union($1) }
            Canvas { context, size in
                guard !images.isEmpty, bounds.width > 0, bounds.height > 0 else { return }
                let scale = min(size.width / bounds.width, size.height / bounds.height)
                let origin = CGPoint(x: (size.width - bounds.width * scale) / 2,
                                     y: (size.height - bounds.height * scale) / 2)
                for (source, rect) in zip(images, rectangles) {
                    context.draw(Image(decorative: source.image, scale: 1),
                                 in: CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
                                            width: rect.width * scale, height: rect.height * scale))
                }
            }
            .frame(height: 170)
            .background(Color.black)
            Text(arrangement == .horizontal ? "Images are ordered from left to right." : "Images are ordered from top to bottom.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        HStack {
                            Image(decorative: image.image, scale: 1).resizable().scaledToFit()
                                .frame(width: 64, height: 40)
                            Text(image.filename).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { model.imagesToCombine.swapAt(index, index - 1) } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(index == 0)
                            .accessibilityLabel("Move image \(index + 1) earlier")
                            Button { model.imagesToCombine.swapAt(index, index + 1) } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(index == images.count - 1)
                            .accessibilityLabel("Move image \(index + 1) later")
                        }
                    }
                }
            }
            .frame(maxHeight: 170)
            HStack {
                Spacer()
                Button("Cancel") {
                    model.showCombineImages = false
                    model.imagesToCombine = []
                }
                .keyboardShortcut(.cancelAction)
                Button("Combine Images") { model.combineImages(arrangement) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 610)
    }
}
