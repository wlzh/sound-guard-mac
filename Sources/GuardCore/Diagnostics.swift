import Foundation

public struct DiagnosticEvent: Codable, Equatable {
    public let timestamp: TimeInterval
    public let kind: String
    public let phase: String
    public let message: String
    public let attempt: Int
    public init(kind: String, phase: String, message: String, attempt: Int) {
        timestamp = Date().timeIntervalSince1970
        self.kind = kind; self.phase = phase
        self.message = String(message.prefix(512)); self.attempt = attempt
    }
}

/// Bounded, event-only diagnostics. No audio, device identifiers or playback app names.
public final class DiagnosticJournal {
    public private(set) var events: [DiagnosticEvent] = []
    private let file: URL
    public init(file: URL) {
        self.file = file
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 131_072,
           let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
            events = Array(saved.suffix(64))
        }
    }
    public func append(_ event: DiagnosticEvent) {
        events.append(event); events = Array(events.suffix(64))
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(events)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { /* Diagnostics must not affect audio protection. */ }
    }
}
