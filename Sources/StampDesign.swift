import AppKit
import CoreText

struct StampInk: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let stampRed = Self(red: 1, green: 0, blue: 0)
    static let cinnabar = Self(red: 179.0 / 255, green: 35.0 / 255, blue: 43.0 / 255)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    var color: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var isValid: Bool { [red, green, blue].allSatisfy { (0...1).contains($0) } }
}

enum StampTypeface: String, Codable, CaseIterable, Identifiable {
    case songBold = "宋体（粗体）"
    case song = "宋体"
    case hei = "黑体"
    case kai = "楷体"
    case seal = "小篆 · 霞鹜篆书"
    case bronze = "金文 · 敬峰中山王篆"
    case brush = "毛笔楷书 · 马善政"

    var id: Self { self }

    var postScriptName: String {
        switch self {
        case .songBold: "STSongti-SC-Bold"
        case .song: "STSongti-SC-Regular"
        case .hei: "PingFangSC-Semibold"
        case .kai: "STKaitiSC-Regular"
        case .seal: "LXGWSeal-Regular"
        case .bronze: "JFZSKSealScript"
        case .brush: "MaShanZheng-Regular"
        }
    }

    func font(size: CGFloat) -> NSFont {
        NSFont(name: postScriptName, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    func missingCharacters(in text: String) -> String {
        guard self == .seal || self == .bronze || self == .brush else { return "" }
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        var missing = Set<Character>()
        return String(text.filter { character in
            guard character.unicodeScalars.contains(where: { $0.properties.isIdeographic }) else { return false }
            let units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            return !CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
                && missing.insert(character).inserted
        }.prefix(24))
    }

    static func registerBundledFonts(in directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Fonts")) {
        guard let directory, let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum StampShape: String, Codable, CaseIterable, Identifiable {
    case circle = "圆形"
    case square = "方形"
    var id: Self { self }
}

enum StampPolarity: String, Codable, CaseIterable, Identifiable {
    case yang = "朱文"
    case yin = "阴文"
    var id: Self { self }
}

enum DrawingQuality: String, Codable, CaseIterable, Identifiable {
    case draft = "传统"
    case standard = "标准"
    case high = "精细"
    var id: Self { self }
}

enum TextArrangement: String, Codable, CaseIterable, Identifiable {
    case upperArc = "上弧"
    case lowerArc = "下弧"
    case horizontal = "横排"
    case vertical = "竖排"
    case columns = "篆刻分列"
    var id: Self { self }
    var isArc: Bool { self == .upperArc || self == .lowerArc }
}

struct StampText: Codable, Equatable {
    var text = ""
    var typeface: StampTypeface = .songBold
    var arrangement: TextArrangement = .horizontal
    var size = 4.25
    var widthPercent = 76.0
    var verticalScale: Double? = nil
    var shiftX = 0.0
    var shiftY = 0.0
    var span = 238.0
    var radius = 14.65
    var columnCount = 2
    var spacingPercent = 100.0
    var italic = false

    static let layerNames = ["文字 1", "文字 2", "文字 3", "附加文字"]

    var heightPercent: Double {
        get { verticalScale ?? 100 }
        set { verticalScale = newValue }
    }

    mutating func scale(by ratio: Double) {
        for dimension in [\Self.size, \.shiftX, \.shiftY, \.radius] {
            self[keyPath: dimension] = (self[keyPath: dimension] * ratio * 100).rounded() / 100
        }
        size = min(50, max(0.5, size))
        radius = min(100, max(1, radius))
    }

    var isValid: Bool {
        text.utf16.count <= 4000 && (0.5...50).contains(size)
            && (20...200).contains(widthPercent) && (20...240).contains(heightPercent) && (10...340).contains(span)
            && (1...100).contains(radius) && (1...6).contains(columnCount)
            && (30...240).contains(spacingPercent) && abs(shiftX) <= 100 && abs(shiftY) <= 100
    }
}

struct StampDesign: Codable, Equatable {
    var shape: StampShape = .circle
    var polarity: StampPolarity = .yang
    var ink = StampInk.stampRed
    var diameter = 38.0
    var outerStroke = 0.6
    var showsInnerRing = true
    var innerDiameter = 36.7
    var innerStroke = 0.2
    var showsStar = true
    var starDiameter = 12.5
    var starDrop = 0.0
    var starShift = 0.0
    var texts = [
        StampText(text: "高二年级地理学习促进委员会", arrangement: .upperArc, size: 6.35, widthPercent: 78),
        StampText(text: "1、2、5班", shiftY: 12.35), StampText(), StampText()
    ]
    var dpi = 600
    var quality: DrawingQuality = .standard

    static let diameters = 15.0...100.0
    static let resolutions = 72...2400
    static let squareSeal: Self = {
        var stamp = Self()
        stamp.shape = .square
        stamp.polarity = .yin
        stamp.ink = .cinnabar
        stamp.resize(to: 25)
        stamp.outerStroke = 0
        stamp.showsInnerRing = false
        stamp.showsStar = false
        stamp.texts = [
            StampText(text: "吉祥", typeface: .seal, arrangement: .columns, size: 12.5,
                      widthPercent: 90, verticalScale: 168),
            StampText(), StampText(), StampText()
        ]
        return stamp
    }()

    var stampSize: Double { diameter + outerStroke }
    var canvasSize: Double { stampSize + 0.8 }
    var exportPixels: Int { Int(ceil(canvasSize * Double(dpi) / 25.4)) }
    var maxInnerDiameter: Double { diameter - outerStroke - innerStroke - 0.1 }
    var isValid: Bool {
        Self.diameters.contains(diameter) && Self.resolutions.contains(dpi) && ink.isValid
            && (0...5).contains(outerStroke) && (0.05...5).contains(innerStroke)
            && (1...diameter).contains(innerDiameter) && (1...diameter).contains(starDiameter)
            && abs(starDrop) <= diameter && abs(starShift) <= diameter
            && texts.count == StampText.layerNames.count && texts.allSatisfy(\.isValid)
    }

    mutating func resize(to newDiameter: Double) {
        guard newDiameter != diameter, Self.diameters.contains(newDiameter) else { return }
        let ratio = newDiameter / diameter
        for dimension in [\Self.outerStroke, \.innerDiameter, \.innerStroke, \.starDiameter, \.starDrop, \.starShift] {
            self[keyPath: dimension] = (self[keyPath: dimension] * ratio * 100).rounded() / 100
        }
        diameter = newDiameter
        outerStroke = min(outerStroke, 5)
        innerStroke = min(max(innerStroke, 0.05), 5)
        innerDiameter = max(innerDiameter, 1)
        starDiameter = max(starDiameter, 1)
        for index in texts.indices { texts[index].scale(by: ratio) }
        fitInnerRing()
    }

    mutating func fitInnerRing() {
        innerDiameter = min(innerDiameter, (maxInnerDiameter * 100).rounded(.down) / 100)
    }
}

// The 1.0 archive stored a single draft under the stampDesign preference.
struct FirstVersionStamp: Decodable {
    var arcText: String
    var bottomText: String
    var typeface: StampTypeface
    var ink: StampInk
    var diameter: Double
    var outerStroke: Double
    var showsInnerRing: Bool
    var innerDiameter: Double
    var innerStroke: Double
    var showsStar: Bool
    var starDiameter: Double
    var starDrop: Double
    var arcFontSize: Double
    var arcWidthPercent: Double
    var arcSpan: Double
    var arcRadius: Double
    var bottomFontSize: Double
    var bottomDrop: Double
    var dpi: Int

    var design: StampDesign {
        var result = StampDesign(ink: ink, diameter: diameter, outerStroke: outerStroke,
                                 showsInnerRing: showsInnerRing, innerDiameter: innerDiameter, innerStroke: innerStroke,
                                 showsStar: showsStar, starDiameter: starDiameter, starDrop: starDrop, dpi: dpi)
        result.texts[0] = StampText(text: arcText, typeface: typeface, arrangement: .upperArc, size: arcFontSize,
                                    widthPercent: arcWidthPercent, span: arcSpan, radius: arcRadius)
        result.texts[1] = StampText(text: bottomText, typeface: typeface, size: bottomFontSize, shiftY: bottomDrop)
        return result
    }
}
