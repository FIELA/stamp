import Foundation
import Combine

struct StampEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var design: StampDesign
}

struct StampLibraryArchive: Codable {
    var version = 2
    var entries: [StampEntry]
    var selection: UUID?

    static func read(_ data: Data) throws -> Self {
        guard data.count <= 8_000_000 else { throw StampError.message("印章库文件过大。") }
        let library = try JSONDecoder().decode(Self.self, from: data)
        guard library.version == 2, !library.entries.isEmpty, library.entries.count <= 500,
              Set(library.entries.map(\.id)).count == library.entries.count,
              library.entries.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 80 && $0.design.isValid }) else {
            throw StampError.message("无法导入该印章库。请使用「图章」导出的印章库文件。")
        }
        return library
    }
}

@MainActor
final class StampLibrary: ObservableObject {
    @Published private(set) var archive: StampLibraryArchive {
        didSet {
            if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: Self.key) }
        }
    }
    private let defaults: UserDefaults
    private static let key = "stampLibraryV2"

    var entries: [StampEntry] { archive.entries }
    var selection: UUID? { archive.selection }
    var active: StampEntry {
        archive.entries.first(where: { $0.id == selection }) ?? archive.entries[0]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.data(forKey: Self.key),
           let existing = try? StampLibraryArchive.read(stored) {
            archive = existing
        } else {
            let previous = defaults.data(forKey: "stampDesign").flatMap {
                try? JSONDecoder().decode(FirstVersionStamp.self, from: $0)
            }
            let migrated = previous.map(\.design).flatMap { $0.isValid ? $0 : nil }
            let starter = StampEntry(name: migrated == nil ? StampShape.circle.stampName : "表扬印章",
                                     design: migrated ?? StampDesign())
            archive = StampLibraryArchive(entries: [starter], selection: starter.id)
        }
    }

    func select(_ id: UUID) {
        guard archive.entries.contains(where: { $0.id == id }), id != selection else { return }
        archive.selection = id
    }

    func update(_ design: StampDesign, for id: UUID) {
        guard design.isValid, let index = archive.entries.firstIndex(where: { $0.id == id }),
              archive.entries[index].design != design else { return }
        archive.entries[index].design = design
    }

    func add(_ design: StampDesign, named name: String) {
        guard entries.count < 500 else { return }
        let entry = StampEntry(name: uniqueName(name, among: entries), design: design)
        archive = StampLibraryArchive(entries: entries + [entry], selection: entry.id)
    }

    func rename(_ id: UUID, to newName: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        archive.entries[index].name = uniqueName(newName, among: entries.filter { $0.id != id })
    }

    func remove(_ id: UUID) {
        guard entries.count > 1, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var remaining = entries
        remaining.remove(at: index)
        let next = selection == id ? remaining[max(0, index - 1)].id : selection
        archive = StampLibraryArchive(entries: remaining, selection: next)
    }

    func merge(_ incoming: StampLibraryArchive) throws {
        guard entries.count + incoming.entries.count <= 500 else {
            throw StampError.message("印章库最多保存 500 枚章。")
        }
        var merged = entries
        var first: UUID?
        for item in incoming.entries where !merged.contains(where: { $0.name == item.name && $0.design == item.design }) {
            let new = StampEntry(name: uniqueName(item.name, among: merged), design: item.design)
            if first == nil { first = new.id }
            merged.append(new)
        }
        archive = StampLibraryArchive(entries: merged, selection: first ?? selection)
    }

    private func uniqueName(_ value: String, among entries: [StampEntry]) -> String {
        let clean = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(70))
        let base = clean.isEmpty ? "未命名图章" : clean
        let existing = Set(entries.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }
}
