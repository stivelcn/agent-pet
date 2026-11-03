import Foundation
import AgentPetCore

enum PetdexError: Error { case badStatus(Int) }

/// Petdex's asset CDN added hotlink protection: requests without a Referer from
/// its own site get 403, which broke all pet downloads. We're a documented
/// Petdex interop client, so we send the expected Referer.
enum PetdexAssets {
    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("https://petdex.crafter.run/", forHTTPHeaderField: "Referer")
        return r
    }

    /// Fetches an asset, retrying transient rate-limits (429) and server errors
    /// with backoff. Throws on a non-success status so callers never write an
    /// error body (e.g. a 429 "error code" page) to disk as if it were a sheet.
    static func data(_ url: URL) async throws -> Data {
        var lastStatus = 0
        for attempt in 0..<3 {
            let (data, resp) = try await URLSession.shared.data(for: request(url))
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            if (200..<300).contains(code) { return data }
            lastStatus = code
            guard code == 429 || code >= 500, attempt < 2 else { break }
            try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 900_000_000)
        }
        throw PetdexError.badStatus(lastStatus)
    }
}

/// Downloads a pet pack (pet.json + spritesheet) into `AgentPetPaths.baseDir/pets/<slug>/`.
/// Shared by the Browse gallery and first-run onboarding.
enum PetInstaller {
    private struct PackMeta: Decodable { let id: String?; let spritesheetPath: String }
    private struct LocalPackManifest: Encodable {
        let id: String
        let displayName: String
        let description: String?
        let spritesheetPath: String
    }

    /// Returns the installed pack's id (pet.json `id`); throws on failure so the
    /// caller can show a meaningful message.
    @discardableResult
    static func download(slug: String, petJsonURL: URL, spritesheetURL: URL) async throws -> String {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: AgentPetPaths.baseDir)
            .appendingPathComponent("pets").appendingPathComponent(slug)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let petJsonData = try await PetdexAssets.data(petJsonURL)
        let meta = try JSONDecoder().decode(PackMeta.self, from: petJsonData)
        try petJsonData.write(to: dir.appendingPathComponent("pet.json"))

        let sheetData = try await PetdexAssets.data(spritesheetURL)
        try sheetData.write(to: dir.appendingPathComponent(meta.spritesheetPath))

        return meta.id ?? slug
    }

    /// A user-facing reason for a failed download.
    static func message(for error: Error, pet: String) -> String {
        if case PetdexError.badStatus(let code) = error, code == 429 {
            return NSLocalizedString("Petdex is rate-limiting downloads right now. Wait a moment and tap Get again.", comment: "")
        }
        return String(format: NSLocalizedString("Could not download %@. Check your connection and try again.", comment: ""), pet)
    }

    /// Creates a new local pet pack from user-entered metadata and a
    /// spritesheet image. Returns the installed pack's id on success.
    @discardableResult
    static func createLocalPack(displayName: String,
                                description: String?,
                                spritesheetURL: URL) -> String? {
        let fm = FileManager.default
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = spritesheetURL.pathExtension.isEmpty ? "png" : spritesheetURL.pathExtension
        let sheetName = "spritesheet.\(ext.lowercased())"

        do {
            let petsDir = URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("pets")
            try fm.createDirectory(at: petsDir, withIntermediateDirectories: true)
            let id = uniquePetID(base: safeFolderName(cleanName), in: petsDir)
            let staging = petsDir.appendingPathComponent(".create-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var committed = false
            defer {
                if !committed {
                    try? fm.removeItem(at: staging)
                }
            }

            let manifest = LocalPackManifest(
                id: id,
                displayName: cleanName,
                description: description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                spritesheetPath: sheetName
            )

            let data = try JSONEncoder.petManifest.encode(manifest)
            try data.write(to: staging.appendingPathComponent("pet.json"))
            try fm.copyItem(at: spritesheetURL, to: staging.appendingPathComponent(sheetName))

            guard SpriteSlicer.loadPack(directory: staging) != nil else {
                return nil
            }

            let destination = petsDir.appendingPathComponent(id)
            try fm.moveItem(at: staging, to: destination)
            committed = true
            return id
        } catch {
            return nil
        }
    }

    private static func uniquePetID(base: String, in petsDir: URL) -> String {
        let fm = FileManager.default
        let seed = base.isEmpty ? UUID().uuidString : base
        var candidate = seed
        var index = 2
        while fm.fileExists(atPath: petsDir.appendingPathComponent(candidate).path) {
            candidate = "\(seed)-\(index)"
            index += 1
        }
        return candidate
    }

    private static func safeFolderName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return name.isEmpty ? UUID().uuidString : name
    }
}

private extension JSONEncoder {
    static var petManifest: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
