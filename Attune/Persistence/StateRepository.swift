import Foundation

protocol StateRepository: Sendable {
    func loadState() async throws -> AppStateDocument
    func saveState(_ document: AppStateDocument) async throws
    func loadHistory() async throws -> HistoryDocument
    func saveHistory(_ document: HistoryDocument) async throws
    func commitTerminal(_ summary: SessionSummary, clearing sessionID: UUID) async throws
}

enum PersistenceDocumentKind: String, Equatable, Sendable {
    case state
    case history
}

enum PersistenceOperation: String, Equatable, Sendable {
    case prepareDirectory
    case read
    case encode
    case write
    case terminalCheckpoint
}

enum StateRepositoryError: Error, Equatable, Sendable {
    case invalidDocument(document: PersistenceDocumentKind, description: String)
    case unsupportedSchemaVersion(
        document: PersistenceDocumentKind,
        found: Int,
        supported: Int
    )
    case fileSystemFailure(
        document: PersistenceDocumentKind?,
        operation: PersistenceOperation,
        description: String
    )
}
