import Foundation

/// リマインダーを届ける時刻。日付やタイムゾーンを含まない「毎日この時刻」。
nonisolated struct ReminderTime: Equatable, Sendable {
    let hour: Int
    let minute: Int

    static let `default` = ReminderTime(hour: 8, minute: 0)
}

nonisolated enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

protocol SettingsStore: AnyObject {
    var reminderTime: ReminderTime { get set }
    var reminderEnabled: Bool { get set }
    var theme: AppTheme { get set }
    var onboardingCompleted: Bool { get set }
}

final class UserDefaultsSettingsStore: SettingsStore {
    private enum Key {
        static let reminderHour = "onetwenty.settings.reminderHour"
        static let reminderMinute = "onetwenty.settings.reminderMinute"
        static let reminderEnabled = "onetwenty.settings.reminderEnabled"
        static let theme = "onetwenty.settings.theme"
        static let onboardingCompleted = "onetwenty.onboarding.completed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var reminderTime: ReminderTime {
        get {
            guard
                let hour = defaults.object(forKey: Key.reminderHour) as? Int,
                let minute = defaults.object(forKey: Key.reminderMinute) as? Int,
                (0...23).contains(hour), (0...59).contains(minute)
            else { return .default }
            return ReminderTime(hour: hour, minute: minute)
        }
        set {
            defaults.set(newValue.hour, forKey: Key.reminderHour)
            defaults.set(newValue.minute, forKey: Key.reminderMinute)
        }
    }

    var reminderEnabled: Bool {
        get { defaults.object(forKey: Key.reminderEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.reminderEnabled) }
    }

    var theme: AppTheme {
        get { defaults.string(forKey: Key.theme).flatMap(AppTheme.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Key.onboardingCompleted) }
        set { defaults.set(newValue, forKey: Key.onboardingCompleted) }
    }
}
