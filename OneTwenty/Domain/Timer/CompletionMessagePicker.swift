import Foundation

/// 完了時に表示する一言を選ぶ。直前と同じ文言は選ばない。
nonisolated enum CompletionMessagePicker {
    /// - Parameter previous: 直前に表示した文言。
    /// - Returns: 一覧が空なら `nil`。直前と異なる文言がなければ（1 件しかない場合など）、一覧の先頭を返す。
    static func pick(
        from messages: [String],
        excluding previous: String?,
        using rng: inout some RandomNumberGenerator
    ) -> String? {
        let candidates = messages.filter { $0 != previous }
        return candidates.randomElement(using: &rng) ?? messages.first
    }
}
