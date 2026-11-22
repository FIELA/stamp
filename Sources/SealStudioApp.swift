import SwiftUI
import UniformTypeIdentifiers

// Use the property wrapper on SDKs where @State also names a macro.
typealias ViewState<Value> = State<Value>

@main
struct SealStudioApp: App {
    init() { StampTypeface.registerBundledFonts() }

    var body: some Scene {
        Window("图章", id: "stamp") {
            StampEditor()
                .frame(minWidth: 950, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

private struct StampEditor: View {
    @StateObject private var library = StampLibrary()
    @ViewState private var photo: StampPhoto?
    @ViewState private var errorMessage: String?
    @ViewState private var renaming: StampEntry?
    @ViewState private var renameDraft = ""
    @ViewState private var removing: StampEntry?
    @ViewState private var copied = false
    @ViewState private var transparent = false
    @ViewState private var zoom = 100.0
    @Environment(\.colorScheme) private var colorScheme

    private let red = Color(red: 0.68, green: 0.16, blue: 0.18)

    private var savedDesign: Binding<StampDesign> {
        let entry = library.active
        return Binding(get: { library.entries.first(where: { $0.id == entry.id })?.design ?? entry.design },
                       set: { library.update($0, for: entry.id) })
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 198)
            Divider()
            preview
            Divider()
            StampInspector(design: savedDesign)
                .id(library.active.id)
                .frame(width: 325)
        }
        .tint(red)
        .sheet(item: $photo) { photo in
            PhotoStampSheet(photo: photo, design: library.active.design, onSave: saveStampedPhoto)
        }
        .alert("重命名图章", isPresented: inProgress($renaming), presenting: renaming) { entry in
            TextField("图章名称", text: $renameDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { library.rename(entry.id, to: renameDraft) }
        }
        .confirmationDialog("删除「\(removing?.name ?? "")」？", isPresented: inProgress($removing),
                            titleVisibility: .visible, presenting: removing) { entry in
            Button("删除", role: .destructive) { library.remove(entry.id) }
            Button("取消", role: .cancel) {}
        }
        .alert("操作未完成", isPresented: inProgress($errorMessage)) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("印章库").font(.headline)
                Spacer()
                Menu {
                    Button(StampShape.circle.stampName) { library.add(StampDesign(), named: StampShape.circle.stampName) }
                    Button(StampShape.square.stampName) { library.add(.squareSeal, named: StampShape.square.stampName) }
                } label: {
                    Image(systemName: "plus").fontWeight(.medium)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("新建图章")
                .help("新建图章")
                .disabled(library.entries.count >= 500)
            }
            .padding(.horizontal, 16)
            .padding(.top, 21)
            .padding(.bottom, 9)

            List(selection: Binding(get: { library.selection }, set: { if let id = $0 { library.select(id) } })) {
                ForEach(library.entries) { entry in
                    Label(entry.name, systemImage: entry.design.shape == .circle ? "circle" : "square")
                        .lineLimit(1)
                        .tag(entry.id)
                        .contextMenu { entryActions(entry) }
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("印章库")

            Divider()
            Menu {
                entryActions(library.active)
                Divider()
                Button("导入印章库…", action: importLibrary)
                Button("导出印章库…", action: exportLibrary)
            } label: {
                Label("管理", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func entryActions(_ entry: StampEntry) -> some View {
        Button("重命名…") {
            renameDraft = entry.name
            renaming = entry
        }
        Button("复制为新图章") {
            library.add(entry.design, named: entry.name)
        }
        .disabled(library.entries.count >= 500)
        Button("删除…", role: .destructive) { removing = entry }
            .disabled(library.entries.count <= 1)
    }

    private var preview: some View {
        let design = library.active.design
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("预览").font(.headline)
                Spacer()
                Picker("预览背景", selection: $transparent) {
                    Text("白底").tag(false)
                    Text("透明").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                Menu {
                    ForEach(StampFormat.allCases) { format in
                        Button(format.title) { exportStamp(as: format) }
                            .keyboardShortcut(format == .png ? KeyboardShortcut("e", modifiers: .command) : nil)
                    }
                    Divider()
                    Button("复制图章", action: copyStamp)
                    Button("打印预览…", action: printPreview)
                        .keyboardShortcut("p", modifiers: .command)
                    Button("给图片盖章…", action: openPhoto)
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderedButton)
                .buttonStyle(.borderedProminent)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            GeometryReader { space in
                let fit = max(1, min(space.size.width - 44, space.size.height - 42, 640))
                let edge = fit * zoom / 100
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(.white)
                        if transparent { Checkerboard().clipShape(.rect(cornerRadius: 8)) }
                        StampCanvas(design: design).padding(edge * 0.075)
                        RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.1), lineWidth: 1)
                    }
                    .frame(width: edge, height: edge)
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.09), radius: 12, y: 5)
                    .padding(18)
                    .frame(minWidth: space.size.width, minHeight: space.size.height)
                }
            }

            HStack(spacing: 12) {
                Text("\(design.exportPixels) × \(design.exportPixels) px")
                    .help("导出尺寸")
                Spacer()
                if copied { Text("已复制").accessibilityAddTraits(.updatesFrequently) }
                ValueField(title: "预览缩放", value: $zoom, range: 25...400, unit: "%", showTitle: false)
                    .frame(width: 65)
                Button("适应窗口") { zoom = 100 }
                    .buttonStyle(.borderless)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(colorScheme == .dark ? Color(white: 0.14) : Color(red: 0.951, green: 0.943, blue: 0.924))
    }

    private func inProgress<T>(_ state: Binding<T?>) -> Binding<Bool> {
        Binding(get: { state.wrappedValue != nil }, set: { if !$0 { state.wrappedValue = nil } })
    }

    private func exportStamp(as format: StampFormat) {
        let entry = library.active
        savePanel(title: "导出图章", name: entry.name, extension: format.rawValue, type: format.type) {
            let dpi = Double(entry.design.dpi)
            return try StampRenderer.encode(StampRenderer.image(entry.design), format: format,
                                            dpi: CGSize(width: dpi, height: dpi))
        }
    }

    private func copyStamp() {
        do {
            try StampClipboard.copy(library.active.design, to: .general)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func printPreview() {
        let entry = library.active
        StampPrintView(design: entry.design).showPreview(title: entry.name, on: NSApp.keyWindow)
    }

    private func openPhoto() {
        openPanel(title: "选择要盖章的图片", type: .image) { url in
            photo = try StampPhoto(url: url)
        }
    }

    private func saveStampedPhoto(_ photo: StampPhoto, _ design: StampDesign, _ placement: StampPlacement, _ format: StampFormat) {
        savePanel(title: "保存盖章后的图片", name: "\(photo.name)-盖章", extension: format.rawValue, type: format.type) {
            try StampRenderer.encode(photo.emboss(design, placement: placement), format: format, dpi: photo.dpi)
        }
    }

    private func importLibrary() {
        openPanel(title: "导入印章库", type: .json) { url in
            let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard byteCount <= 8_000_000 else { throw StampError.message("印章库文件过大。") }
            try library.merge(StampLibraryArchive.read(Data(contentsOf: url)))
        }
    }

    private func exportLibrary() {
        let archive = library.archive
        savePanel(title: "导出印章库", name: "图章-印章库", extension: "json", type: .json) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(archive)
        }
    }

    private func savePanel(title: String, name: String, extension suffix: String,
                           type: UTType, makeData: @escaping () throws -> Data) {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = "保存"
        panel.nameFieldStringValue = "\(name).\(suffix)"
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do { try makeData().write(to: destination, options: .atomic) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func openPanel(title: String, type: UTType, onOpen: @escaping (URL) throws -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [type]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try onOpen(url) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct StampCanvas: View {
    let design: StampDesign
    var includeMargin = true

    var body: some View {
        Canvas { context, size in
            context.withCGContext { canvas in
                let edge = includeMargin ? design.canvasSize : design.stampSize
                canvas.translateBy(x: size.width / 2, y: size.height / 2)
                canvas.scaleBy(x: size.width / edge, y: -size.height / edge)
                StampRenderer.draw(design, in: canvas)
            }
        }
        .accessibilityLabel("图章预览")
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile = 12.0
            var squares = Path()
            for row in 0..<Int(ceil(size.height / tile)) {
                for column in stride(from: row % 2, to: Int(ceil(size.width / tile)), by: 2) {
                    squares.addRect(CGRect(x: Double(column) * tile, y: Double(row) * tile, width: tile, height: tile))
                }
            }
            context.fill(squares, with: .color(Color(white: 0.92)))
        }
        .accessibilityHidden(true)
    }
}

private struct PhotoStampSheet: View {
    let photo: StampPhoto
    let design: StampDesign
    let onSave: (StampPhoto, StampDesign, StampPlacement, StampFormat) -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState private var placement: StampPlacement
    @ViewState private var format = StampFormat.png

    init(photo: StampPhoto, design: StampDesign, onSave: @escaping (StampPhoto, StampDesign, StampPlacement, StampFormat) -> Void) {
        self.photo = photo
        self.design = design
        self.onSave = onSave
        _placement = ViewState(wrappedValue: StampPlacement(size: design.stampSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("给图片盖章").font(.headline)
            GeometryReader { space in
                let fit = photo.sizeToFit(space.size)
                let stamp = photo.stampRect(placement)
                let scaleX = fit.width / Double(photo.image.width)
                let scaleY = fit.height / Double(photo.image.height)
                ZStack(alignment: .topLeading) {
                    Image(decorative: photo.image, scale: 1)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                    StampCanvas(design: design, includeMargin: false)
                        .frame(width: stamp.width * scaleX, height: stamp.height * scaleY)
                        .offset(x: stamp.minX * scaleX, y: stamp.minY * scaleY)
                        .allowsHitTesting(false)
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let availableWidth = max(1, fit.width - stamp.width * scaleX)
                    let availableHeight = max(1, fit.height - stamp.height * scaleY)
                    placement.x = min(100, max(0, (drag.location.x - stamp.width * scaleX / 2) * 100 / availableWidth))
                    placement.y = min(100, max(0, (drag.location.y - stamp.height * scaleY / 2) * 100 / availableHeight))
                })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: 14) {
                ValueField(title: "章面大小", value: $placement.size, range: 1...100, unit: "mm")
                ValueField(title: "水平位置", value: $placement.x, range: 0...100, unit: "%")
                ValueField(title: "垂直位置", value: $placement.y, range: 0...100, unit: "%")
            }
            HStack {
                Picker("格式", selection: $format) {
                    ForEach(StampFormat.allCases) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("另存图片…") { onSave(photo, design, placement, format) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(minWidth: 660, minHeight: 530)
    }
}
