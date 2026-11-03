import AppKit
import AgentPetCore

/// Loads and imports spritesheet pet packs from `AgentPetPaths.baseDir/pets/`.
@MainActor
final class ImagePetStore: ObservableObject {
    static let shared = ImagePetStore()

    @Published private(set) var packs: [ImagePetPack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailures: [String: String] = [:]
    private var loadGeneration = UUID()

    func loadingMessage(for id: String?) -> String {
        guard let id else { return "请在设置中选择宠物" }
        if let failure = loadFailures[id] { return failure }
        return isLoading ? "正在加载宠物…" : "未找到所选宠物，请重新选择"
    }

    /// User-chosen names per pet id, overriding the pack's catalog name (#31).
    @Published private(set) var nameOverrides: [String: String] =
        (LocalPreferences.defaults.dictionary(forKey: "agentpet.petNames") as? [String: String]) ?? [:]

    private var petsDir: URL {
        URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("pets")
    }

    func pack(id: String) -> ImagePetPack? {
        packs.first { $0.id == id }
    }

    /// The name to show for a pet: the user's custom name, else the pack's
    /// catalog name, else the id. One place so every surface agrees.
    func displayName(for id: String?) -> String {
        guard let id else { return NSLocalizedString("Your pet", comment: "") }
        if let custom = nameOverrides[id], !custom.isEmpty { return custom }
        return pack(id: id)?.displayName ?? id
    }

    /// Renames a pet (empty/blank clears the override back to the catalog name).
    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == pack(id: id)?.displayName {
            nameOverrides.removeValue(forKey: id)
        } else {
            nameOverrides[id] = String(trimmed.prefix(40))
        }
        LocalPreferences.defaults.set(nameOverrides, forKey: "agentpet.petNames")
    }

    /// Deletes an installed pet's folder from disk. Drops it from the in-memory
    /// list directly instead of a full `reload()`: reload re-slices every other
    /// pack's spritesheet on the main actor (heavy pixel-scan per sheet), which
    /// froze the UI when deleting with many pets installed.
    func delete(_ pack: ImagePetPack) {
        try? FileManager.default.removeItem(at: pack.directory)
        packs.removeAll { $0.id == pack.id }
    }

    /// Full synchronous reload. Used after importing a pet, where slicing every
    /// pack up front is acceptable; launch uses `loadFast` to stay responsive.
    func reload() {
        loadGeneration = UUID() // discard a previous background launch load
        let result = Self.load(directories: Self.directories(in: petsDir))
        loadFailures = result.failures
        isLoading = false
        packs = result.packs.sorted { $0.displayName < $1.displayName }
    }

    /// Decode the selected pack immediately, then load the rest off the main actor.
    func loadFast(priorityID: String?) {
        let generation = UUID()
        loadGeneration = generation
        let dirs = Self.directories(in: petsDir)
        let priorityDir = priorityID
            .flatMap { pid in dirs.first { SpriteSlicer.manifestID(directory: $0) == pid } }
            ?? dirs.first
        let first = Self.load(directories: priorityDir.map { [$0] } ?? [])
        loadFailures = first.failures
        packs = first.packs
        let rest = dirs.filter { $0 != priorityDir }
        isLoading = !rest.isEmpty
        guard !rest.isEmpty else { return }
        Task.detached(priority: .utility) {
            let result = Self.load(directories: rest)
            let box = UncheckedSendableBox(result)
            await MainActor.run {
                let store = ImagePetStore.shared
                guard store.loadGeneration == generation else { return }
                store.loadFailures.merge(box.value.failures) { _, new in new }
                store.isLoading = false
                store.packs = (store.packs + box.value.packs).sorted { $0.displayName < $1.displayName }
            }
        }
    }

    nonisolated private static func load(directories: [URL]) -> (packs: [ImagePetPack], failures: [String: String]) {
        var packs: [ImagePetPack] = []
        var failures: [String: String] = [:]
        for dir in directories {
            if let pack = SpriteSlicer.loadPack(directory: dir) {
                packs.append(pack)
            } else {
                let id = SpriteSlicer.manifestID(directory: dir) ?? dir.lastPathComponent
                failures[id] = "宠物资源加载失败，请重新下载或导入"
            }
        }
        return (packs, failures)
    }

    private static func directories(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}

/// Carries a non-Sendable payload (sliced `ImagePetPack`s hold `NSImage`s) from
/// a background slicing task to the main actor. Safe because the packs are
/// immutable and built fresh off-thread, then only read on the main actor.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
