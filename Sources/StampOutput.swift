import AppKit
import ImageIO
import UniformTypeIdentifiers

struct StampPhoto: Identifiable {
    let id = UUID()
    let image: CGImage
    let dpi: CGSize?
    let name: String

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32_768, height <= 32_768, width * height <= 96_000_000 else {
            throw StampError.message("无法打开图片，或图像尺寸过大。")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StampError.image
        }
        image = decoded
        name = url.deletingPathExtension().lastPathComponent
        if let x = properties[kCGImagePropertyDPIWidth] as? Double,
           let y = properties[kCGImagePropertyDPIHeight] as? Double, (1...10_000).contains(x), (1...10_000).contains(y) {
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            dpi = (5...8).contains(orientation) ? CGSize(width: y, height: x) : CGSize(width: x, height: y)
        } else {
            dpi = nil
        }
    }

    func sizeToFit(_ space: CGSize) -> CGSize {
        let ratio = min(space.width / CGFloat(image.width), space.height / CGFloat(image.height))
        return CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
    }

    func stampRect(_ placement: StampPlacement) -> CGRect {
        let resolution = dpi ?? CGSize(width: 300, height: 300)
        let width = Double(image.width)
        let height = Double(image.height)
        let pixelsWide = placement.size * resolution.width / 25.4
        let pixelsHigh = placement.size * resolution.height / 25.4
        let fit = min(1, width / pixelsWide, height / pixelsHigh)
        let stampWidth = pixelsWide * fit
        let stampHeight = pixelsHigh * fit
        return CGRect(x: (width - stampWidth) * placement.x / 100,
                      y: (height - stampHeight) * placement.y / 100,
                      width: stampWidth, height: stampHeight)
    }

    func emboss(_ design: StampDesign, placement: StampPlacement) throws -> CGImage {
        let context = try StampRenderer.bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let rect = stampRect(placement)
        context.translateBy(x: rect.midX, y: Double(image.height) - rect.midY)
        context.scaleBy(x: rect.width / design.stampSize, y: rect.height / design.stampSize)
        StampRenderer.draw(design, in: context)
        guard let result = context.makeImage() else { throw StampError.image }
        return result
    }
}

struct StampPlacement {
    var size = 38.6
    var x = 85.0
    var y = 85.0
}

@MainActor
final class StampPrintView: NSView {
    private let design: StampDesign

    init(design: StampDesign) {
        self.design = design
        let pointSize = design.canvasSize * 72 / 25.4
        super.init(frame: CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.scaleBy(x: 72 / 25.4, y: 72 / 25.4)
        StampRenderer.draw(design, in: context)
        context.restoreGState()
    }

    func showPreview(title: String, on window: NSWindow?) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let operation = NSPrintOperation(view: self, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.printPanel.options.insert(.showsPreview)
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}

@MainActor
enum StampClipboard {
    static func copy(_ design: StampDesign, to pasteboard: NSPasteboard) throws {
        let image = try StampRenderer.image(design)
        let dpi = CGSize(width: design.dpi, height: design.dpi)
        let item = NSPasteboardItem()
        item.setData(try StampRenderer.encode(image, format: .png, dpi: dpi), forType: .png)
        item.setData(try StampRenderer.encode(image, format: .tiff, dpi: dpi), forType: .tiff)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw StampError.message("无法写入剪贴板。") }
    }
}
