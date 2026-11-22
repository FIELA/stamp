import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconFolder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let sizes = [16, 32, 128, 256, 512]

func ink(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: 1)
}

func makeIcon(pixels: Int) -> CGImage {
    let canvas = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                           bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    canvas.scaleBy(x: scale, y: scale)

    let tileBounds = CGRect(x: 98, y: 105, width: 828, height: 828)
    let tile = CGPath(roundedRect: tileBounds, cornerWidth: 184, cornerHeight: 184, transform: nil)
    canvas.saveGState()
    canvas.setShadow(offset: CGSize(width: 0, height: -13), blur: 26, color: CGColor(gray: 0, alpha: 0.25))
    canvas.setFillColor(ink(0.99, 0.97, 0.92))
    canvas.addPath(tile)
    canvas.fillPath()
    canvas.restoreGState()

    canvas.saveGState()
    canvas.addPath(tile)
    canvas.clip()
    let colors = [ink(1, 0.99, 0.96), ink(0.94, 0.88, 0.8)] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    canvas.drawLinearGradient(gradient, start: CGPoint(x: 250, y: 930), end: CGPoint(x: 770, y: 110), options: [])
    canvas.restoreGState()

    let red = ink(0.78, 0.12, 0.16)
    canvas.setStrokeColor(red)
    canvas.setFillColor(red)
    canvas.setLineWidth(32)
    canvas.strokeEllipse(in: CGRect(x: 222, y: 228, width: 580, height: 580))
    canvas.setLineWidth(12)
    canvas.strokeEllipse(in: CGRect(x: 258, y: 264, width: 508, height: 508))

    let star = CGMutablePath()
    for index in 0..<10 {
        let angle = Double(index) * .pi / 5
        let radius = index.isMultiple(of: 2) ? 165.0 : 63.025
        let point = CGPoint(x: 512 + sin(angle) * radius, y: 517 + cos(angle) * radius)
        if index == 0 { star.move(to: point) } else { star.addLine(to: point) }
    }
    star.closeSubpath()
    canvas.addPath(star)
    canvas.fillPath()
    return canvas.makeImage()!
}

for size in sizes {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        let url = iconFolder.appendingPathComponent(name)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, makeIcon(pixels: size * scale), nil)
        precondition(CGImageDestinationFinalize(destination))
    }
}
