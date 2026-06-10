import Foundation

/// Per-model token rates in USD per 1M tokens. Approximate published rates as
/// of late 2025; refine if Anthropic publishes updates.
struct ModelPricing: Sendable {
    let inputPer1M: Double
    let outputPer1M: Double
    let cacheReadPer1M: Double
    let cacheCreationPer1M: Double

    static let opus = ModelPricing(
        inputPer1M: 15.00, outputPer1M: 75.00,
        cacheReadPer1M: 1.50, cacheCreationPer1M: 18.75
    )
    static let sonnet = ModelPricing(
        inputPer1M: 3.00, outputPer1M: 15.00,
        cacheReadPer1M: 0.30, cacheCreationPer1M: 3.75
    )
    static let haiku = ModelPricing(
        inputPer1M: 1.00, outputPer1M: 5.00,
        cacheReadPer1M: 0.10, cacheCreationPer1M: 1.25
    )
    /// Fallback when we see a model id we don't recognize — assume Sonnet rates
    /// (mid-tier, avoids extreme over- or under-estimates).
    static let unknown = sonnet

    /// Best-effort lookup keyed on the `model` field Anthropic emits.
    /// Match by family substring so future point releases (4.7.1 etc.) still resolve.
    static func resolve(_ modelId: String) -> ModelPricing {
        let m = modelId.lowercased()
        if m.contains("opus")   { return .opus }
        if m.contains("sonnet") { return .sonnet }
        if m.contains("haiku")  { return .haiku }
        return .unknown
    }

    func cost(for usage: TokenUsage) -> Double {
        let perToken = 1.0 / 1_000_000
        return Double(usage.input) * inputPer1M * perToken
            + Double(usage.output) * outputPer1M * perToken
            + Double(usage.cacheRead) * cacheReadPer1M * perToken
            + Double(usage.cacheCreation) * cacheCreationPer1M * perToken
    }
}

/// Context-window size per model id. Claude models are 200k unless the id
/// carries the long-context marker (e.g. "claude-sonnet-4-6[1m]").
enum ContextWindow {
    static func limit(for modelId: String?) -> Int {
        guard let m = modelId?.lowercased() else { return 200_000 }
        return m.contains("[1m]") ? 1_000_000 : 200_000
    }
}

extension Double {
    /// "$0.42" / "$1.23" / "$15.00".
    var asUSD: String {
        if self < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", self)
    }
}
