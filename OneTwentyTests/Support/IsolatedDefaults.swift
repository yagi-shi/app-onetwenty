import Foundation

/// テストごとに独立した UserDefaults。他のテストや本体アプリの保存値と混ざらない。
final class IsolatedDefaults {
    let defaults: UserDefaults
    private let suiteName: String

    init() {
        suiteName = "onetwenty.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
