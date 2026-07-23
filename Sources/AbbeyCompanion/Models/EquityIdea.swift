import Foundation
import SwiftData

/// A synthetic "instrument" produced by the equity research module. Every instrument
/// is prefixed `QX-` and every surface that renders one (Discord embed, CLI, this app's
/// SwiftUI views) MUST show the disclaimer text. This is idea-generation scaffolding
/// over a made-up universe — never real tickers, never real market data, and never
/// framed as investment advice.
@Model
final class EquityIdea {
    @Attribute(.unique) var symbol: String        // e.g. "QX-4471"
    var thesisSummary: String
    var syntheticScore: Double                     // 0.0–1.0, from FactorScreen
    var factorBreakdown: [String: Double]
    var generatedAt: Date

    static let disclaimer =
        "Synthetic instrument, synthetic data. Not investment advice, not a real security."

    init(symbol: String, thesisSummary: String, syntheticScore: Double, factorBreakdown: [String: Double], generatedAt: Date = .now) {
        self.symbol = symbol
        self.thesisSummary = thesisSummary
        self.syntheticScore = syntheticScore
        self.factorBreakdown = factorBreakdown
        self.generatedAt = generatedAt
    }
}
