import Foundation
import os

/// アプリに同梱した言語別のデータを読み込む。
/// 読めないファイルがあっても止めず、その種類のデータを空として返す。
struct ContentLoader {
    private let bundle: Bundle
    private let reportFailure: (String) -> Void

    /// - Parameter reportFailure: ファイルの欠落・形式不正を見つけたときに呼ぶ。
    ///   既定ではデバッグビルドで停止させ、出荷前に気づけるようにする。
    init(
        bundle: Bundle = .main,
        reportFailure: @escaping (String) -> Void = { assertionFailure($0) }
    ) {
        self.bundle = bundle
        self.reportFailure = reportFailure
    }

    func load(language: ContentLanguage) -> ContentBundle {
        let templates = decode(TemplatesFile.self, name: "templates", language: language)
        let terms = decode(DetectionTerms.self, name: "detection-terms", language: language)
        let messages = decode(CompletionMessagesFile.self, name: "completion-messages", language: language)
        return ContentBundle(
            templates: templates?.categories ?? [],
            terms: terms ?? .empty,
            completionMessages: messages?.messages ?? []
        )
    }

    /// 言語はファイル名で選ぶ（`templates.ja.json` など）。リソースの自動言語選択には頼らない。
    private func decode<File: Decodable>(_ type: File.Type, name: String, language: ContentLanguage) -> File? {
        let resource = "\(name).\(language.rawValue)"
        guard let url = bundle.url(forResource: resource, withExtension: "json") else {
            report("\(resource).json が見つからない")
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            report("\(resource).json を読めない: \(error)")
            return nil
        }
    }

    private func report(_ message: String) {
        Log.data.error("\(message)")
        reportFailure(message)
    }
}

private nonisolated struct TemplatesFile: Decodable {
    let categories: [TemplateCategory]
}

private nonisolated struct CompletionMessagesFile: Decodable {
    let messages: [String]
}
