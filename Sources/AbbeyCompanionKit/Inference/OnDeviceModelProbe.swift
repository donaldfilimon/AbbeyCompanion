import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum OnDeviceModelStatus: Sendable, Equatable {
    case available
    case unavailable(String)
    case unsupportedPlatform

    var label: String {
        switch self {
        case .available: return "Available"
        case .unavailable(let reason): return "Unavailable — \(reason)"
        case .unsupportedPlatform: return "Requires macOS 26+"
        }
    }
}

enum OnDeviceModelProbe {
    @MainActor
    static func status() -> OnDeviceModelStatus {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .unsupportedPlatform }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(String(describing: reason))
        @unknown default:
            return .unavailable("unknown")
        }
        #else
        return .unsupportedPlatform
        #endif
    }
}
