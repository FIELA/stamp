import SwiftUI

struct StampInspector: View {
    @Binding var design: StampDesign
    @ViewState private var tab = 0
    @ViewState private var layerIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置", selection: $tab) {
                Text("章面").tag(0)
                Text("文字").tag(1)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 17)
            .padding(.vertical, 17)
            Divider()
            ScrollView {
                Group {
                    if tab == 0 { face }
                    else { typography }
                }
                .padding(17)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 15) {
            Picker("形状", selection: $design.shape) {
                ForEach(StampShape.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("印文", selection: $design.polarity) {
                    ForEach(StampPolarity.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("朱文为有色文字，阴文在有色印面上镂空")
                Spacer(minLength: 8)
                ColorPicker("印色", selection: Binding(
                    get: { Color(nsColor: design.ink.color) },
                    set: { if let value = StampInk(color: NSColor($0)) { design.ink = value } }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            Divider()
            LazyVGrid(columns: columns, spacing: 12) {
                field(design.shape == .circle ? "外圈直径" : "外框边长", Binding(
                    get: { design.diameter }, set: { design.resize(to: $0) }
                ), StampDesign.diameters)
                field("外框线宽", Binding(
                    get: { design.outerStroke },
                    set: { design.outerStroke = $0; design.fitInnerRing() }
                ), 0...min(5, design.diameter / 6))
            }
            Toggle("显示内框", isOn: $design.showsInnerRing)
            if design.showsInnerRing {
                LazyVGrid(columns: columns, spacing: 12) {
                    field(design.shape == .circle ? "内圈直径" : "内框边长",
                          $design.innerDiameter, 1...design.maxInnerDiameter)
                    field("内框线宽", Binding(
                        get: { design.innerStroke },
                        set: { design.innerStroke = $0; design.fitInnerRing() }
                    ), 0.05...min(5, design.diameter / 6))
                }
            }
            Divider()
            Toggle("显示五角星", isOn: $design.showsStar)
            if design.showsStar {
                LazyVGrid(columns: columns, spacing: 12) {
                    field("五星直径", $design.starDiameter, 1...(design.diameter * 0.75))
                    field("右移", $design.starShift, offsetRange)
                    field("下移", $design.starDrop, offsetRange)
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                ValueField(title: "导出分辨率", value: Binding(
                    get: { Double(design.dpi) }, set: { design.dpi = Int($0.rounded()) }
                ), range: Double(StampDesign.resolutions.lowerBound)...Double(StampDesign.resolutions.upperBound), unit: "DPI")
                Menu("常用") {
                    ForEach([150, 300, 600, 1200], id: \.self) { dpi in
                        Button("\(dpi) DPI") { design.dpi = dpi }
                    }
                }
                .fixedSize()
                .accessibilityLabel("常用分辨率")
            }
            Picker("绘制质量", selection: $design.quality) {
                ForEach(DrawingQuality.allCases) { Text($0.rawValue).tag($0) }
            }
        }
    }

    private var typography: some View {
        let layer = $design.texts[layerIndex]
        let missing = layer.wrappedValue.typeface.missingCharacters(in: layer.wrappedValue.text)
        return VStack(alignment: .leading, spacing: 13) {
            Picker("文字组", selection: $layerIndex) {
                ForEach(StampText.layerNames.indices, id: \.self) {
                    Text(StampText.layerNames[$0]).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 7) {
                Text("文字内容").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: layer.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(height: 75)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.background, in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .accessibilityLabel("文字内容")
            }
            Picker("字体", selection: layer.typeface) {
                ForEach(StampTypeface.allCases) { Text($0.rawValue).tag($0) }
            }
            if !missing.isEmpty {
                Text("「\(missing)」在此字体中缺字，已用系统字形显示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("排法", selection: layer.arrangement) {
                ForEach(TextArrangement.allCases) { Text($0.rawValue).tag($0) }
            }
            if layer.wrappedValue.arrangement == .columns {
                Stepper("列数 \(layer.wrappedValue.columnCount)", value: layer.columnCount, in: 1...6)
                    .help("从右到左。换行可手动指定各列。")
            }
            Divider()
            LazyVGrid(columns: columns, spacing: 12) {
                field("字号", layer.size, 0.5...max(1, design.diameter / 2))
                field("字宽", layer.widthPercent, 20...200, unit: "%")
                field("字高比例", layer.heightPercent, 20...240, unit: "%")
                field("字距", layer.spacingPercent, 30...240, unit: "%")
                Toggle("斜体", isOn: layer.italic)
                if layer.wrappedValue.arrangement.isArc {
                    field("环排角度", layer.span, 10...340, unit: "°")
                    field("环排半径", layer.radius, 1...design.diameter / 2)
                }
                field("右移", layer.shiftX, offsetRange)
                field("下移", layer.shiftY, offsetRange)
            }
        }
        .id(layerIndex)
    }

    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible())] }
    private var offsetRange: ClosedRange<Double> { (-design.diameter / 2)...(design.diameter / 2) }
    private func field(_ name: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, unit: String = "mm") -> some View {
        ValueField(title: name, value: value, range: range, unit: unit)
    }
}

struct ValueField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var showTitle = true
    @ViewState private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showTitle { Text(title).font(.callout).foregroundStyle(.secondary) }
            HStack(spacing: 5) {
                TextField(title, text: $draft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .focused($editing)
                    .onSubmit(commit)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { draft = formattedValue }
        .onChange(of: draft) { _, updated in
            if editing, let number = parse(updated), range.contains(number) { value = number }
        }
        .onChange(of: value) { _, _ in if !editing { draft = formattedValue } }
        .onChange(of: editing) { _, focused in if !focused { commit() } }
    }

    private var formattedValue: String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    private func parse(_ input: String) -> Double? {
        Double(input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func commit() {
        if let parsed = parse(draft), parsed.isFinite { value = min(max(parsed, range.lowerBound), range.upperBound) }
        draft = formattedValue
    }
}
