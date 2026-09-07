import Darwin
import Foundation

protocol PersistenceFileSystem: Sendable {
    func createDirectory(at url: URL, permissions: mode_t) throws
    func fileExists(at url: URL) -> Bool
    func setPermissions(_ permissions: mode_t, at url: URL) throws
    func readData(at url: URL) throws -> Data
    func atomicallyReplaceFile(at url: URL, with data: Data, permissions: mode_t) throws
}

final class LocalPersistenceFileSystem: PersistenceFileSystem, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func createDirectory(at url: URL, permissions: mode_t) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: permissions)]
        )
        try setPermissions(permissions, at: url)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func setPermissions(_ permissions: mode_t, at url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                errno = EINVAL
                return Int32(-1)
            }
            return Darwin.chmod(path, permissions)
        }

        guard result == 0 else {
            throw currentPOSIXError()
        }
    }

    func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func atomicallyReplaceFile(at url: URL, with data: Data, permissions: mode_t) throws {
        let temporaryURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")

        var descriptor = temporaryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                errno = EINVAL
                return Int32(-1)
            }
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL, permissions)
        }

        guard descriptor >= 0 else {
            throw currentPOSIXError()
        }

        var shouldRemoveTemporaryFile = true
        defer {
            if descriptor >= 0 {
                _ = Darwin.close(descriptor)
            }
            if shouldRemoveTemporaryFile {
                _ = temporaryURL.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return Int32(-1) }
                    return Darwin.unlink(path)
                }
            }
        }

        guard Darwin.fchmod(descriptor, permissions) == 0 else {
            throw currentPOSIXError()
        }

        try data.withUnsafeBytes { buffer in
            guard var cursor = buffer.baseAddress else { return }
            var remaining = buffer.count

            while remaining > 0 {
                let written = Darwin.write(descriptor, cursor, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw currentPOSIXError()
                }
                guard written > 0 else {
                    throw POSIXError(.EIO)
                }
                remaining -= written
                cursor = cursor.advanced(by: written)
            }
        }

        guard Darwin.fsync(descriptor) == 0 else {
            throw currentPOSIXError()
        }

        let closeResult = Darwin.close(descriptor)
        descriptor = -1
        guard closeResult == 0 else {
            throw currentPOSIXError()
        }

        let replaceResult = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            url.withUnsafeFileSystemRepresentation { destinationPath in
                guard let temporaryPath, let destinationPath else {
                    errno = EINVAL
                    return Int32(-1)
                }
                return Darwin.rename(temporaryPath, destinationPath)
            }
        }

        guard replaceResult == 0 else {
            throw currentPOSIXError()
        }
        shouldRemoveTemporaryFile = false
    }

    private func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

actor FileStateRepository: StateRepository {
    typealias TerminalCommitCheckpoint = @Sendable () throws -> Void

    private static let stateFileName = "state.json"
    private static let historyFileName = "history.json"
    private static let directoryPermissions: mode_t = 0o700
    private static let filePermissions: mode_t = 0o600

    private let baseDirectory: URL
    private let fileSystem: any PersistenceFileSystem
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let afterTerminalHistoryWrite: TerminalCommitCheckpoint

    init(
        baseDirectory: URL = FileStateRepository.defaultBaseDirectory(),
        fileSystem: any PersistenceFileSystem = LocalPersistenceFileSystem(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() },
        afterTerminalHistoryWrite: @escaping TerminalCommitCheckpoint = {}
    ) {
        self.baseDirectory = baseDirectory
        self.fileSystem = fileSystem
        self.calendar = calendar
        self.now = now
        self.afterTerminalHistoryWrite = afterTerminalHistoryWrite
    }

    func loadState() async throws -> AppStateDocument {
        var state = try readStateDocument()

        guard let activeSessionID = state.activeSession?.id else {
            return state
        }

        let rawHistory = try readHistoryDocument()
        let terminalOutcomeWasRecorded = rawHistory.sessions.contains {
            $0.id == activeSessionID
        }

        if terminalOutcomeWasRecorded {
            state.activeSession = nil
            try writeStateDocument(state)
        }

        let retainedHistory = rawHistory.retainingSessions(
            accordingTo: state.preferences.historyRetention,
            relativeTo: now(),
            calendar: calendar
        )
        if retainedHistory != rawHistory {
            try writeHistoryDocument(retainedHistory)
        }

        return state
    }

    func saveState(_ document: AppStateDocument) async throws {
        try validateSchemaVersion(
            document.schemaVersion,
            expected: AppStateDocument.currentSchemaVersion,
            document: .state
        )
        try writeStateDocument(document)

        let history = try readHistoryDocument()
        let retainedHistory = history.retainingSessions(
            accordingTo: document.preferences.historyRetention,
            relativeTo: now(),
            calendar: calendar
        )
        if retainedHistory != history {
            try writeHistoryDocument(retainedHistory)
        }
    }

    func loadHistory() async throws -> HistoryDocument {
        let history = try readHistoryDocument()
        let state = try readStateDocument()
        let retainedHistory = history.retainingSessions(
            accordingTo: state.preferences.historyRetention,
            relativeTo: now(),
            calendar: calendar
        )
        if retainedHistory != history {
            try writeHistoryDocument(retainedHistory)
        }
        return retainedHistory
    }

    func saveHistory(_ document: HistoryDocument) async throws {
        try validateSchemaVersion(
            document.schemaVersion,
            expected: HistoryDocument.currentSchemaVersion,
            document: .history
        )

        let state = try readStateDocument()
        let retainedHistory = document.retainingSessions(
            accordingTo: state.preferences.historyRetention,
            relativeTo: now(),
            calendar: calendar
        )
        try writeHistoryDocument(retainedHistory)
    }

    func commitTerminal(_ summary: SessionSummary, clearing sessionID: UUID) async throws {
        var history = try readHistoryDocument()
        let state = try readStateDocument()

        history.upsert(summary)
        history = history.retainingSessions(
            accordingTo: state.preferences.historyRetention,
            relativeTo: now(),
            calendar: calendar
        )
        try writeHistoryDocument(history)

        do {
            try afterTerminalHistoryWrite()
        } catch {
            throw StateRepositoryError.fileSystemFailure(
                document: nil,
                operation: .terminalCheckpoint,
                description: String(describing: error)
            )
        }

        guard state.activeSession?.id == sessionID else {
            return
        }

        var clearedState = state
        clearedState.activeSession = nil
        try writeStateDocument(clearedState)
    }

    nonisolated static func defaultBaseDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Attune", isDirectory: true)
    }

    private var stateFileURL: URL {
        baseDirectory.appendingPathComponent(Self.stateFileName, isDirectory: false)
    }

    private var historyFileURL: URL {
        baseDirectory.appendingPathComponent(Self.historyFileName, isDirectory: false)
    }

    private func readStateDocument() throws -> AppStateDocument {
        try readDocument(
            AppStateDocument.self,
            from: stateFileURL,
            kind: .state,
            expectedSchemaVersion: AppStateDocument.currentSchemaVersion,
            missingValue: .initial
        )
    }

    private func readHistoryDocument() throws -> HistoryDocument {
        try readDocument(
            HistoryDocument.self,
            from: historyFileURL,
            kind: .history,
            expectedSchemaVersion: HistoryDocument.currentSchemaVersion,
            missingValue: .initial
        )
    }

    private func writeStateDocument(_ document: AppStateDocument) throws {
        try writeDocument(document, to: stateFileURL, kind: .state)
    }

    private func writeHistoryDocument(_ document: HistoryDocument) throws {
        try writeDocument(document, to: historyFileURL, kind: .history)
    }

    private func readDocument<Document: Decodable>(
        _ type: Document.Type,
        from url: URL,
        kind: PersistenceDocumentKind,
        expectedSchemaVersion: Int,
        missingValue: @autoclosure () -> Document
    ) throws -> Document {
        try prepareStorageDirectory()

        guard fileSystem.fileExists(at: url) else {
            return missingValue()
        }

        let data: Data
        do {
            try fileSystem.setPermissions(Self.filePermissions, at: url)
            data = try fileSystem.readData(at: url)
        } catch {
            throw fileSystemError(error, document: kind, operation: .read)
        }

        let decoder = JSONDecoder()
        let schemaVersion: Int
        do {
            schemaVersion = try decoder.decode(SchemaVersionProbe.self, from: data).schemaVersion
        } catch {
            throw StateRepositoryError.invalidDocument(
                document: kind,
                description: String(describing: error)
            )
        }

        try validateSchemaVersion(
            schemaVersion,
            expected: expectedSchemaVersion,
            document: kind
        )

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StateRepositoryError.invalidDocument(
                document: kind,
                description: String(describing: error)
            )
        }
    }

    private func writeDocument<Document: Encodable>(
        _ document: Document,
        to url: URL,
        kind: PersistenceDocumentKind
    ) throws {
        try prepareStorageDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw StateRepositoryError.fileSystemFailure(
                document: kind,
                operation: .encode,
                description: String(describing: error)
            )
        }

        do {
            try fileSystem.atomicallyReplaceFile(
                at: url,
                with: data,
                permissions: Self.filePermissions
            )
        } catch {
            throw fileSystemError(error, document: kind, operation: .write)
        }
    }

    private func prepareStorageDirectory() throws {
        do {
            try fileSystem.createDirectory(
                at: baseDirectory,
                permissions: Self.directoryPermissions
            )
        } catch {
            throw fileSystemError(error, document: nil, operation: .prepareDirectory)
        }
    }

    private func validateSchemaVersion(
        _ found: Int,
        expected: Int,
        document: PersistenceDocumentKind
    ) throws {
        guard found == expected else {
            throw StateRepositoryError.unsupportedSchemaVersion(
                document: document,
                found: found,
                supported: expected
            )
        }
    }

    private func fileSystemError(
        _ error: Error,
        document: PersistenceDocumentKind?,
        operation: PersistenceOperation
    ) -> StateRepositoryError {
        if let repositoryError = error as? StateRepositoryError {
            return repositoryError
        }
        return StateRepositoryError.fileSystemFailure(
            document: document,
            operation: operation,
            description: String(describing: error)
        )
    }
}

private struct SchemaVersionProbe: Decodable {
    let schemaVersion: Int
}
