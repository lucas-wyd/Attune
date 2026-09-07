import Foundation

struct SessionMetrics: Codable, Equatable, Sendable {
    var interventionCount: Int
    var softReturnCount: Int
    var softOpenCount: Int
    var contextCheckInCount: Int
    var inactivityCheckInCount: Int
    var enforcementFailureCount: Int

    init(
        interventionCount: Int = 0,
        softReturnCount: Int = 0,
        softOpenCount: Int = 0,
        contextCheckInCount: Int = 0,
        inactivityCheckInCount: Int = 0,
        enforcementFailureCount: Int = 0
    ) {
        self.interventionCount = interventionCount
        self.softReturnCount = softReturnCount
        self.softOpenCount = softOpenCount
        self.contextCheckInCount = contextCheckInCount
        self.inactivityCheckInCount = inactivityCheckInCount
        self.enforcementFailureCount = enforcementFailureCount
    }
}
