import Foundation

enum AtomicJSONFile {
    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        let data = try Data(contentsOf: url)
        return try JSONCoding.decoder().decode(type, from: data)
    }

    static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            let data = try JSONCoding.encoder().encode(value)
            try data.write(to: temporaryURL, options: .withoutOverwriting)

            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func quarantineCorruptFile(at url: URL, now: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let milliseconds = Int64(now.timeIntervalSince1970 * 1_000)
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(milliseconds).bak")
        try FileManager.default.moveItem(at: url, to: backupURL)
    }
}
