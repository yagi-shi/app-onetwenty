import Foundation
@testable import OneTwenty

/// 通知センターの代わり。予約の状態をメモリ上に持ち、呼び出しを記録する。
@MainActor
final class FakeNotificationClient: NotificationClient {
    struct AddFailure: Error {}

    var authorization: NotificationAuthorization = .authorized
    /// 許可を求めたときに、ユーザーが選んだことにする結果。
    var authorizationAfterRequest: NotificationAuthorization = .authorized
    /// 予約を失敗させる識別子。
    var failingIdentifiers: Set<String> = []
    /// 許可のダイアログを表示している間に起きることを差し込む（答える前にタイマーを中断する、など）。
    var whileRequestingAuthorization: (() async -> Void)?

    private(set) var pending: [LocalNotificationRequest] = []
    private(set) var addedIdentifiers: [String] = []
    private(set) var removedIdentifiers: [String] = []
    private(set) var requestAuthorizationCount = 0

    var pendingIdentifiers: Set<String> {
        Set(pending.map(\.identifier))
    }

    /// 既に予約されている状態を作る。
    func seed(_ request: LocalNotificationRequest) {
        pending.append(request)
    }

    /// 呼び出しの記録だけを消す（予約の状態は残す）。
    func resetCallHistory() {
        addedIdentifiers = []
        removedIdentifiers = []
    }

    func authorizationStatus() async -> NotificationAuthorization {
        authorization
    }

    func requestAuthorization() async -> NotificationAuthorization {
        requestAuthorizationCount += 1
        await whileRequestingAuthorization?()
        if authorization == .notDetermined {
            authorization = authorizationAfterRequest
        }
        return authorization
    }

    func pendingIdentifiers(prefix: String) async -> [String] {
        pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
    }

    func add(_ request: LocalNotificationRequest) async throws {
        if failingIdentifiers.contains(request.identifier) {
            throw AddFailure()
        }
        // 本物と同じく、同じ識別子の予約は置き換える
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
        addedIdentifiers.append(request.identifier)
    }

    func remove(identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}
