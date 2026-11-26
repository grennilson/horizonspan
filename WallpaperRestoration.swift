import Foundation

enum WallpaperRestoreSchedule {
    // Login's WallpaperAgent and display discovery can complete after the first
    // successful assignment. Repeat forced assignments for a bounded 30 seconds.
    static let startup: [Duration] = [.milliseconds(650), .seconds(1.5), .seconds(4), .seconds(8), .seconds(15)]
    static let changed: [Duration] = [.milliseconds(650), .seconds(1.5), .seconds(4)]

    @MainActor static func run(
        delays: [Duration],
        wait: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        enabled: () -> Bool,
        attempt: () async -> Void
    ) async {
        for delay in delays {
            do { try await wait(delay) } catch { return }
            guard !Task.isCancelled, enabled() else { return }
            await attempt()
        }
    }
}

enum WallpaperRestoreLog {
    @MainActor static func record(_ message: String) {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let folder = support.appendingPathComponent("HorizonSpan", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("WallpaperRestore.log")
        var data = (try? Data(contentsOf: url)) ?? Data()
        if data.count > 256_000 { data = Data() }
        let text = "\(ISO8601DateFormatter().string(from: Date())) \(message.replacingOccurrences(of: "\n", with: " "))\n"
        data.append(Data(text.utf8))
        try? data.write(to: url, options: .atomic)
    }
}
