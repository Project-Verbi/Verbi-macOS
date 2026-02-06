import Foundation

struct AppStoreConnectKey: Codable, Sendable {
    var keyID: String
    var issuerID: String
    var privateKey: String
    
    var encodedPrivateKey: Data? {
        privateKey.data(using: .utf8)
    }
    
    var isValid: Bool {
        !keyID.isEmpty && !issuerID.isEmpty && !privateKey.isEmpty
    }
}

struct AppStoreApp: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let bundleId: String
    let platform: String
    let sku: String
    let version: String?
    let versionState: String?
    let hasReleased: Bool
    let iconURL: URL?

    static var stub: AppStoreApp {
        AppStoreApp(
            id: "stub-app-id",
            name: "Stub App",
            bundleId: "com.example.stub",
            platform: "IOS",
            sku: "stub-sku",
            version: "1.0.0",
            versionState: "PREPARE_FOR_SUBMISSION",
            hasReleased: false,
            iconURL: nil
        )
    }
}

struct AppStoreVersionSummary: Identifiable, Hashable {
    enum Kind: String {
        case current = "Current"
        case upcoming = "Upcoming"
    }

    let id: String
    let version: String
    let state: String?
    let platform: String?
    let kind: Kind
    let isEditable: Bool
}

struct AppChangelog: Identifiable, Hashable {
    let id: String
    let locale: String
    var text: String
}

struct AppStoreBuild: Identifiable, Hashable {
    let id: String
    let version: String
    let uploadedDate: Date?
    let processingState: String?
    let isSelectable: Bool
}

enum ReleaseType: String, CaseIterable, Identifiable {
    case manual = "MANUAL"
    case afterApproval = "AFTER_APPROVAL"
    case scheduled = "SCHEDULED"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .manual:
            return "Manual Release"
        case .afterApproval:
            return "Automatic Release"
        case .scheduled:
            return "Scheduled Release"
        }
    }
    
    var description: String {
        switch self {
        case .manual:
            return "Release this version manually after it's approved"
        case .afterApproval:
            return "Release this version automatically as soon as it's approved"
        case .scheduled:
            return "Release this version on a specific date and time"
        }
    }
}

enum ReleaseOption: Hashable, Identifiable {
    case manual
    case afterApproval
    case scheduled(Date)

    enum Kind: String, CaseIterable, Identifiable {
        case manual
        case afterApproval
        case scheduled

        var id: String { rawValue }

        var releaseType: ReleaseType {
            switch self {
            case .manual:
                return .manual
            case .afterApproval:
                return .afterApproval
            case .scheduled:
                return .scheduled
            }
        }

        var displayName: String { releaseType.displayName }

        var description: String { releaseType.description }

        func defaultOption() -> ReleaseOption {
            switch self {
            case .manual:
                return .manual
            case .afterApproval:
                return .afterApproval
            case .scheduled:
                return .scheduled(ReleaseOption.defaultScheduledDate())
            }
        }
    }

    var id: String {
        switch self {
        case .manual:
            return "manual"
        case .afterApproval:
            return "afterApproval"
        case .scheduled:
            return "scheduled"
        }
    }

    var kind: Kind {
        switch self {
        case .manual:
            return .manual
        case .afterApproval:
            return .afterApproval
        case .scheduled:
            return .scheduled
        }
    }

    var displayName: String { kind.displayName }
    var description: String { kind.description }

    var releaseType: ReleaseType {
        switch kind {
        case .manual:
            return .manual
        case .afterApproval:
            return .afterApproval
        case .scheduled:
            return .scheduled
        }
    }

    var scheduledDate: Date? {
        switch self {
        case .scheduled(let date):
            return date
        default:
            return nil
        }
    }

    static func defaultScheduledDate(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date),
              let startOfTomorrow = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: tomorrow)),
              let result = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfTomorrow) else {
            return date
        }
        return result
    }
}
