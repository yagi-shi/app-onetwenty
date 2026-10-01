import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct SettingsStoreTests {
    private let isolated = IsolatedDefaults()
    private var store: UserDefaultsSettingsStore { UserDefaultsSettingsStore(defaults: isolated.defaults) }

    @Test("何も保存していないときの既定値")
    func defaultValues() {
        #expect(store.reminderTime == ReminderTime(hour: 8, minute: 0))
        #expect(store.reminderEnabled == true)
        #expect(store.theme == .system)
        #expect(store.onboardingCompleted == false)
    }

    @Test("保存した値は、ストアを作り直しても読み出せる")
    func valuesPersist() {
        store.reminderTime = ReminderTime(hour: 21, minute: 30)
        store.reminderEnabled = false
        store.theme = .dark
        store.onboardingCompleted = true

        let reopened = UserDefaultsSettingsStore(defaults: isolated.defaults)

        #expect(reopened.reminderTime == ReminderTime(hour: 21, minute: 30))
        #expect(reopened.reminderEnabled == false)
        #expect(reopened.theme == .dark)
        #expect(reopened.onboardingCompleted == true)
    }

    @Test("0:00 を通知時刻に設定できる")
    func midnightReminderTime() {
        store.reminderTime = ReminderTime(hour: 0, minute: 0)

        #expect(store.reminderTime == ReminderTime(hour: 0, minute: 0))
    }

    @Test("テーマは 3 種類とも保存できる", arguments: AppTheme.allCases)
    func allThemes(theme: AppTheme) {
        store.theme = theme

        #expect(store.theme == theme)
    }

    @Test("保存値が範囲外や未知の値なら既定値として扱う")
    func invalidStoredValuesFallBackToDefaults() {
        isolated.defaults.set(24, forKey: "onetwenty.settings.reminderHour")
        isolated.defaults.set(0, forKey: "onetwenty.settings.reminderMinute")
        isolated.defaults.set("sepia", forKey: "onetwenty.settings.theme")

        #expect(store.reminderTime == .default)
        #expect(store.theme == .system)
    }

    @Test("設計で定めたキーに保存する")
    func usesDesignedKeys() {
        store.reminderTime = ReminderTime(hour: 6, minute: 45)
        store.reminderEnabled = false
        store.theme = .light
        store.onboardingCompleted = true

        let defaults = isolated.defaults
        #expect(defaults.integer(forKey: "onetwenty.settings.reminderHour") == 6)
        #expect(defaults.integer(forKey: "onetwenty.settings.reminderMinute") == 45)
        #expect(defaults.object(forKey: "onetwenty.settings.reminderEnabled") as? Bool == false)
        #expect(defaults.string(forKey: "onetwenty.settings.theme") == "light")
        #expect(defaults.bool(forKey: "onetwenty.onboarding.completed") == true)
    }
}
