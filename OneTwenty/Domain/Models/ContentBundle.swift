import Foundation

/// ウィザードで提示する「始め方の例」のまとまり。
nonisolated struct TemplateCategory: Codable, Identifiable, Equatable, Sendable {
    let id: String
    /// 自由入力との照合に使う語。
    let keywords: [String]
    let templates: [String]
}

/// 習慣名から検出する語。ここにない語は検出しない。
nonisolated struct DetectionTerms: Codable, Equatable, Sendable {
    let frequencyAdverbs: [String]
    let goalSuffixes: [String]

    static let empty = DetectionTerms(frequencyAdverbs: [], goalSuffixes: [])
}

/// アプリに同梱した、言語ごとのデータ一式。
nonisolated struct ContentBundle: Equatable, Sendable {
    let templates: [TemplateCategory]
    let terms: DetectionTerms
    let completionMessages: [String]
}
