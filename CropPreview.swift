import AppKit
import SwiftUI

enum CropGeometry {
    static func ratioLabel(_ size: CGSize) -> String {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        var divisor = width
        var remainder = height
        while remainder != 0 {
            (divisor, remainder) = (remainder, divisor % remainder)
        }
        return "\(width / divisor):\(height / divisor)"
    }

    static func fitted(in size: CGSize, ratio: CGFloat) -> CGRect {
        let width = min(size.width, size.height * ratio)
        let height = width / ratio
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }

    static func moved(_ rect: CGRect, by delta: CGSize, in size: CGSize) -> CGRect {
        CGRect(x: min(max(rect.minX + delta.width, 0), size.width - rect.width),
               y: min(max(rect.minY + delta.height, 0), size.height - rect.height),
               width: rect.width, height: rect.height)
    }

    static func resized(_ rect: CGRect, corner: Int, to point: CGPoint, in size: CGSize) -> CGRect {
        let right = corner == 1 || corner == 2
        let bottom = corner == 2 || corner == 3
        let anchor = CGPoint(x: right ? rect.minX : rect.maxX, y: bottom ? rect.minY : rect.maxY)
        let ratio = rect.width / rect.height
        let dx = (point.x - anchor.x) * (right ? 1 : -1)
        let dy = (point.y - anchor.y) * (bottom ? 1 : -1)
        let availableWidth = right ? size.width - anchor.x : anchor.x
        let availableHeight = bottom ? size.height - anchor.y : anchor.y
        let maximum = min(availableWidth, availableHeight * ratio)
        let minimum = min(maximum, min(16, size.height) * ratio)
        let width = min(maximum, max(minimum, (dx + dy / ratio) / (1 + 1 / (ratio * ratio))))
        let height = width / ratio
        return CGRect(x: right ? anchor.x : anchor.x - width,
                      y: bottom ? anchor.y : anchor.y - height, width: width, height: height)
    }

    static func zoomed(_ rect: CGRect, factor: CGFloat, in size: CGSize) -> CGRect {
        let maximum = min(size.width / rect.width, size.height / rect.height)
        let minimum = min(1, 16 / min(rect.width, rect.height))
        let multiplier = min(maximum, max(minimum, 1 / factor))
        let next = CGRect(x: rect.midX - rect.width * multiplier / 2,
                          y: rect.midY - rect.height * multiplier / 2,
                          width: rect.width * multiplier, height: rect.height * multiplier)
        return moved(next, by: .zero, in: size)
    }

    static func pixels(_ rect: CGRect, in image: CGImage) -> CGRect {
        let width = min(image.width, max(1, Int(rect.width.rounded(.down))))
        let height = min(image.height, max(1, Int(rect.height.rounded(.down))))
        return CGRect(x: min(image.width - width, max(0, Int(rect.minX.rounded()))),
                      y: min(image.height - height, max(0, Int(rect.minY.rounded()))),
                      width: width, height: height)
    }
}

struct CropPreview: NSViewRepresentable {
    let image: CGImage
    @Binding var selection: CGRect

    func makeNSView(context: Context) -> CropCanvas { CropCanvas() }

    func updateNSView(_ view: CropCanvas, context: Context) {
        view.image = image
        view.selection = selection
        view.onChange = { selection = $0 }
        view.needsDisplay = true
    }
}

final class CropCanvas: NSView {
    var image: CGImage?
    var selection = CGRect.zero
    var onChange: ((CGRect) -> Void)?
    private var viewZoom: CGFloat = 1
    private var imageOffset = CGSize.zero
    private var dragStart: CGPoint?
    private var originalSelection = CGRect.zero
    private var corner: Int?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var sourceSize: CGSize {
        CGSize(width: image?.width ?? 1, height: image?.height ?? 1)
    }

    private var imageFrame: CGRect {
        let scale = min(max(1, bounds.width - 48) / sourceSize.width,
                        max(1, bounds.height - 48) / sourceSize.height) * viewZoom
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + imageOffset.width,
                      y: (bounds.height - size.height) / 2 + imageOffset.height,
                      width: size.width, height: size.height)
    }

    private func screenRect(_ rect: CGRect) -> CGRect {
        let frame = imageFrame
        let scale = frame.width / sourceSize.width
        return CGRect(x: frame.minX + rect.minX * scale, y: frame.minY + rect.minY * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }

    private func sourcePoint(_ point: CGPoint) -> CGPoint {
        let frame = imageFrame
        let scale = frame.width / sourceSize.width
        return CGPoint(x: (point.x - frame.minX) / scale, y: (point.y - frame.minY) / scale)
    }

    private var handles: [CGPoint] {
        let rect = screenRect(selection)
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        NSImage(cgImage: image, size: sourceSize).draw(in: imageFrame, from: .zero,
            operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let rect = screenRect(selection)
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(rect)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.58).setFill()
        shade.fill()

        NSColor.white.withAlphaComponent(0.45).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for step in 1...2 {
            let x = rect.minX + rect.width * CGFloat(step) / 3
            let y = rect.minY + rect.height * CGFloat(step) / 3
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.line(to: CGPoint(x: x, y: rect.maxY))
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.line(to: CGPoint(x: rect.maxX, y: y))
        }
        grid.stroke()
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: rect)
        outline.lineWidth = 2
        outline.stroke()
        for point in handles {
            let handle = NSBezierPath(roundedRect: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12),
                                      xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            handle.fill()
            NSColor.black.withAlphaComponent(0.6).setStroke()
            handle.lineWidth = 1
            handle.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        corner = handles.firstIndex { hypot($0.x - point.x, $0.y - point.y) <= 14 }
        guard corner != nil || screenRect(selection).contains(point) else { return }
        dragStart = sourcePoint(point)
        originalSelection = selection
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = sourcePoint(convert(event.locationInWindow, from: nil))
        if let corner {
            change(CropGeometry.resized(originalSelection, corner: corner, to: point, in: sourceSize))
        } else {
            change(CropGeometry.moved(originalSelection,
                by: CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y), in: sourceSize))
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        corner = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard dragStart == nil else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.008 : 0.08)
        let targetZoom = min(12, max(1, viewZoom * exp(min(0.5, max(-0.5, delta)))))
        let factor = targetZoom / viewZoom
        let center = screenRect(selection).center
        let next = CropGeometry.zoomed(selection, factor: factor, in: sourceSize)
        viewZoom *= selection.width / next.width
        let nextCenter = screenRect(next).center
        imageOffset.width += center.x - nextCenter.x
        imageOffset.height += center.y - nextCenter.y
        change(next)
    }

    private func change(_ rect: CGRect) {
        selection = rect
        onChange?(rect)
        needsDisplay = true
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
