import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum StampFormat: String, CaseIterable, Identifiable {
    case png, gif, bmp, jpg, tiff
    var id: Self { self }
    var title: String {
        switch self {
        case .png: "PNG（透明）"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .jpg: "JPG"
        case .tiff: "TIFF"
        }
    }

    var type: UTType {
        switch self {
        case .png: .png
        case .gif: .gif
        case .bmp: .bmp
        case .jpg: .jpeg
        case .tiff: .tiff
        }
    }

    var opaque: Bool { self == .jpg || self == .bmp }
}

enum StampRenderer {
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static func draw(_ design: StampDesign, in context: CGContext) {
        let ink = design.ink.color
        let edge = design.polarity == .yin ? design.stampSize : design.canvasSize
        context.saveGState()
        context.setAllowsAntialiasing(design.quality != .draft)
        context.setShouldAntialias(design.quality != .draft)
        context.addPath(outline(design.shape, size: edge))
        context.clip()

        if design.polarity == .yin {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(ink.cgColor)
            context.addPath(outline(design.shape, size: edge))
            context.fillPath()
            context.setBlendMode(.destinationOut)
        }

        context.setFillColor(ink.cgColor)
        context.setStrokeColor(ink.cgColor)
        if design.outerStroke > 0 {
            drawBorder(design.shape, size: design.diameter, width: design.outerStroke, in: context)
        }
        if design.showsInnerRing {
            drawBorder(design.shape, size: design.innerDiameter, width: design.innerStroke, in: context)
        }
        if design.showsStar {
            context.saveGState()
            context.translateBy(x: design.starShift, y: -design.starDrop)
            drawStar(diameter: design.starDiameter, in: context)
            context.restoreGState()
        }
        for layer in design.texts where !layer.text.isEmpty {
            drawLayer(layer, design: design, in: context)
        }

        if design.polarity == .yin { context.endTransparencyLayer() }
        context.restoreGState()
    }

    static func bitmap(width: Int, height: Int) throws -> CGContext {
        guard width > 0, height > 0, width <= 32_768, height <= 32_768, width * height <= 96_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StampError.message("图像太大。请降低 DPI，或选用较小的原图。")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    static func image(_ design: StampDesign) throws -> CGImage {
        let pixels = design.exportPixels
        let antialiasScale = design.quality == .high && pixels <= 3_500 ? 2 : 1
        let target = pixels * antialiasScale
        let context = try bitmap(width: target, height: target)
        let scale = Double(design.dpi) * Double(antialiasScale) / 25.4
        context.translateBy(x: CGFloat(target) / 2, y: CGFloat(target) / 2)
        context.scaleBy(x: scale, y: scale)
        draw(design, in: context)
        guard let image = context.makeImage() else { throw StampError.image }
        if antialiasScale == 1 { return image }
        let reduced = try bitmap(width: pixels, height: pixels)
        reduced.interpolationQuality = .high
        reduced.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let result = reduced.makeImage() else { throw StampError.image }
        return result
    }

    static func encode(_ image: CGImage, format: StampFormat, dpi: CGSize?) throws -> Data {
        let processed: CGImage
        if format.opaque {
            let background = try bitmap(width: image.width, height: image.height)
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            background.setFillColor(CGColor(gray: 1, alpha: 1))
            background.fill(bounds)
            background.draw(image, in: bounds)
            guard let opaque = background.makeImage() else { throw StampError.image }
            processed = opaque
        } else {
            processed = image
        }
        let data = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
            throw StampError.image
        }
        var properties: [String: Any] = [:]
        if let dpi, format != .gif {
            properties[kCGImagePropertyDPIWidth as String] = dpi.width
            properties[kCGImagePropertyDPIHeight as String] = dpi.height
        }
        if format == .jpg { properties[kCGImageDestinationLossyCompressionQuality as String] = 0.96 }
        CGImageDestinationAddImage(writer, processed, properties as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw StampError.image }
        return data as Data
    }

    private static func outline(_ shape: StampShape, size: Double) -> CGPath {
        let box = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        return shape == .circle ? CGPath(ellipseIn: box, transform: nil) : CGPath(rect: box, transform: nil)
    }

    private static func drawBorder(_ shape: StampShape, size: Double, width: Double, in context: CGContext) {
        context.setLineWidth(width)
        context.addPath(outline(shape, size: size))
        context.strokePath()
    }

    private static func drawStar(diameter: Double, in context: CGContext) {
        let path = CGMutablePath()
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5
            let radius = diameter / 2 * (index.isMultiple(of: 2) ? 1 : 0.381966)
            let point = CGPoint(x: sin(angle) * radius, y: cos(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.addPath(path)
        context.fillPath()
    }

    private static func drawLayer(_ layer: StampText, design: StampDesign, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: layer.typeface.font(size: layer.size),
            .foregroundColor: design.ink.color,
            .kern: layer.size * (layer.spacingPercent / 100 - 1) / 2
        ]
        func line(_ text: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }

        context.saveGState()
        context.translateBy(x: layer.shiftX, y: -layer.shiftY)
        let heightScale = layer.heightPercent / 100
        let inkEdge = (design.showsInnerRing
            ? design.innerDiameter - design.innerStroke
            : design.diameter - design.outerStroke) / 2
        switch layer.arrangement {
        case .upperArc, .lowerArc:
            drawArc(layer, lines: Array(layer.text.filter { !$0.isNewline }).map { line(String($0)) }, in: context)
        case .horizontal:
            let lines = layer.text.components(separatedBy: .newlines).map(line)
            let step = layer.size * heightScale * 1.15
            for (index, textLine) in lines.enumerated() {
                let y = (Double(lines.count - 1) / 2 - Double(index)) * step
                let bounds = CTLineGetBoundsWithOptions(textLine, .useGlyphPathBounds)
                let limit = design.shape == .circle
                    ? sqrt(max(1, pow(inkEdge - 0.6, 2) - pow(abs(layer.shiftY - y) + bounds.height * heightScale / 2, 2)))
                    : inkEdge - 0.6
                context.saveGState()
                context.translateBy(x: 0, y: y)
                drawLine(textLine, widthScale: layer.widthPercent / 100, heightScale: heightScale,
                         maxWidth: max(0.2, 2 * (limit - abs(layer.shiftX))), italic: layer.italic, in: context)
                context.restoreGState()
            }
        case .vertical, .columns:
            let source = layer.text.split(whereSeparator: \.isNewline).map(Array.init)
            let characters = source.flatMap { $0 }
            let columns: [[Character]]
            if layer.arrangement == .vertical || source.count > 1 {
                columns = source
            } else {
                let columnCount = min(layer.columnCount, max(1, characters.count))
                columns = (0..<columnCount).map { column in
                    let start = (characters.count * column + columnCount - 1) / columnCount
                    let end = (characters.count * (column + 1) + columnCount - 1) / columnCount
                    return Array(characters[start..<end])
                }
            }
            let safeSpan = (inkEdge - 0.8) * (design.shape == .circle ? 1.39 : 2)
            let width = min(safeSpan / Double(max(columns.count, 1)), layer.size * layer.spacingPercent / 100)
            let height = min(safeSpan / Double(max(columns.map(\.count).max() ?? 1, 1)), layer.size * heightScale * layer.spacingPercent / 100)
            for (column, characters) in columns.enumerated() {
                for (row, glyph) in characters.enumerated() {
                    context.saveGState()
                    context.translateBy(x: (Double(columns.count - 1) / 2 - Double(column)) * width,
                                        y: (Double(characters.count - 1) / 2 - Double(row)) * height)
                    drawLine(line(String(glyph)), widthScale: layer.widthPercent / 100, heightScale: heightScale,
                             maxWidth: width * 0.93, maxHeight: height * 0.95, italic: layer.italic, in: context)
                    context.restoreGState()
                }
            }
        }
        context.restoreGState()
    }

    private static func drawArc(_ layer: StampText, lines: [CTLine], in context: CGContext) {
        let upper = layer.arrangement == .upperArc
        let span = layer.span * .pi / 180
        let step = span / Double(max(lines.count - 1, 1))
        let spacing = 2 * layer.radius * sin(step / 2) * layer.spacingPercent / 100
        for (index, line) in lines.enumerated() {
            let angle = lines.count == 1 ? 0 : Double(index) * step - span / 2
            context.saveGState()
            context.translateBy(x: sin(angle) * layer.radius, y: cos(angle) * layer.radius * (upper ? 1 : -1))
            context.rotate(by: upper ? -angle : angle)
            drawLine(line, widthScale: layer.widthPercent / 100, heightScale: layer.heightPercent / 100,
                     maxWidth: lines.count > 1 ? spacing * 0.93 : .infinity, italic: layer.italic, in: context)
            context.restoreGState()
        }
    }

    private static func drawLine(_ line: CTLine, widthScale: Double, heightScale: Double, maxWidth: Double,
                                 maxHeight: Double = .infinity, italic: Bool, in context: CGContext) {
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard bounds.width > 0 && bounds.height > 0 else { return }
        let fittedHeight = min(heightScale, maxHeight / bounds.height)
        let fittedWidth = widthScale * fittedHeight / heightScale
        context.scaleBy(x: min(fittedWidth, maxWidth / bounds.width), y: fittedHeight)
        if italic { context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0.19, d: 1, tx: 0, ty: 0)) }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
    }
}

enum StampError: LocalizedError {
    case message(String)
    case image
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .image: "无法读取或生成图像。"
        }
    }
}
