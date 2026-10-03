import Foundation

/// 同時に持てる習慣の数の上限。
nonisolated enum HabitSlotPolicy {
    static let maxActiveHabits = 3

    static func canRegister(activeCount: Int) -> Bool {
        activeCount < maxActiveHabits
    }
}
