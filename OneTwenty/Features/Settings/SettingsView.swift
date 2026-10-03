import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    let coordinator: AppCoordinator

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            preferences
            habitsSection
        }
        // 並べ替えの取っ手を常に出しておく（削除はできない）
        .environment(\.editMode, .constant(.active))
        .navigationTitle(Text("settings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: coordinator.dataVersion) {
            viewModel.reload()
        }
        .task {
            await viewModel.refreshAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshAuthorization() }
        }
        .confirmationDialog(
            archiveTitle,
            isPresented: isArchiveDialogPresented,
            titleVisibility: .visible
        ) {
            Button("settings.archive.confirm", role: .destructive) {
                Task { await viewModel.confirmArchive() }
            }
            Button("settings.archive.cancel", role: .cancel) {
                viewModel.cancelArchive()
            }
        } message: {
            Text("settings.archive.message")
        }
        .alert(Text("common.alert.saveFailed"), isPresented: isSaveFailurePresented) {
            Button("common.ok") { viewModel.dismissSaveFailure() }
        }
    }

    // MARK: ユーザー設定

    private var preferences: some View {
        Section {
            DatePicker(
                selection: reminderDate,
                displayedComponents: .hourAndMinute
            ) {
                Text("settings.reminderTime")
            }
            .disabled(!viewModel.areReminderControlsEnabled)

            Toggle(isOn: reminderEnabled) {
                Text("settings.reminderEnabled")
            }
            // 標準の緑ではなく、アプリで使う 1 色に合わせる
            .tint(Color.accentColor)
            .disabled(!viewModel.areReminderControlsEnabled)

            if !viewModel.areReminderControlsEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("settings.notifications.denied")
                    Button("settings.notifications.openSettings") {
                        // 開けなかった場合も何も表示しない
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }

            Picker(selection: theme) {
                Text("settings.theme.system").tag(AppTheme.system)
                Text("settings.theme.light").tag(AppTheme.light)
                Text("settings.theme.dark").tag(AppTheme.dark)
            } label: {
                Text("settings.theme")
            }
        } header: {
            Text("settings.section.preferences")
                .foregroundStyle(Color.secondaryText)
        } footer: {
            // オフにするのはリマインダーだけで、タイマーの完了通知は止まらない
            Text("settings.reminder.footer")
                .foregroundStyle(Color.secondaryText)
        }
    }

    // MARK: 習慣の管理

    private var habitsSection: some View {
        Section {
            if viewModel.habits.isEmpty {
                Text("settings.habits.empty")
                    .foregroundStyle(Color.secondaryText)
            }
            ForEach(viewModel.habits) { habit in
                HStack {
                    Text(habit.title)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Menu {
                        Button("settings.rename") { viewModel.rename(habit) }
                        Button("settings.archive", role: .destructive) { viewModel.requestArchive(habit) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("settings.habitActions \(habit.title)"))
                    }
                }
            }
            .onMove { source, destination in
                var ids = viewModel.habits.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                viewModel.reorder(to: ids)
            }
        } header: {
            Text("settings.section.habits")
                .foregroundStyle(Color.secondaryText)
        }
    }

    // MARK: つなぎ

    /// 時・分だけを持つ設定値を、時刻の選択欄で扱える形に変換する。
    private var reminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: viewModel.reminderTime.hour,
                    minute: viewModel.reminderTime.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let time = ReminderTime(hour: components.hour ?? 8, minute: components.minute ?? 0)
                Task { await viewModel.setReminderTime(time) }
            }
        )
    }

    private var reminderEnabled: Binding<Bool> {
        Binding(
            get: { viewModel.reminderEnabled },
            set: { enabled in Task { await viewModel.setReminderEnabled(enabled) } }
        )
    }

    private var theme: Binding<AppTheme> {
        Binding(get: { viewModel.theme }, set: { viewModel.setTheme($0) })
    }

    private var archiveTitle: String {
        String(localized: "settings.archive.title \(viewModel.archiveCandidate?.title ?? "")")
    }

    private var isArchiveDialogPresented: Binding<Bool> {
        Binding(
            get: { viewModel.archiveCandidate != nil },
            set: { if !$0 { viewModel.cancelArchive() } }
        )
    }

    private var isSaveFailurePresented: Binding<Bool> {
        Binding(
            get: { viewModel.showsSaveFailure },
            set: { if !$0 { viewModel.dismissSaveFailure() } }
        )
    }
}
