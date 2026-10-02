import AVFoundation
import Foundation
import os
import UIKit

/// タイマーを走り切ったときの音と振動。
protocol FeedbackPlayer {
    /// 完了時にすぐ鳴らせるよう、あらかじめ読み込んでおく。タイマーの開始時に呼ぶ。
    func prepare()
    func playCompletion()
}

/// 音と振動を同じ呼び出しで鳴らす。片方が失敗しても、もう片方は鳴らす。
final class SystemFeedbackPlayer: FeedbackPlayer {
    private let sound: CompletionSound
    private let haptics: CompletionHaptics

    init(sound: CompletionSound = BundledCompletionSound(), haptics: CompletionHaptics = SystemCompletionHaptics()) {
        self.sound = sound
        self.haptics = haptics
    }

    func prepare() {
        sound.prepare()
        haptics.prepare()
    }

    func playCompletion() {
        do {
            try sound.play()
        } catch {
            Log.feedback.error("完了音を再生できない: \(error)")
        }
        haptics.play()
    }
}

protocol CompletionSound {
    func prepare()
    func play() throws
}

protocol CompletionHaptics {
    func prepare()
    func play()
}

enum CompletionSoundError: Error {
    case fileNotFound
    case playbackDidNotStart
}

/// アプリに同梱した完了音。
final class BundledCompletionSound: CompletionSound {
    static let resourceName = "completion"
    static let fileExtensions = ["caf", "wav", "m4a"]

    private let bundle: Bundle
    private var player: AVAudioPlayer?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func prepare() {
        do {
            try loadPlayerIfNeeded().prepareToPlay()
        } catch {
            Log.feedback.error("完了音を読み込めない: \(error)")
        }
    }

    func play() throws {
        let player = try loadPlayerIfNeeded()
        // 「着信／消音」スイッチで消音にしていれば鳴らない種類の音として扱う
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient)
        try session.setActive(true)
        player.currentTime = 0
        guard player.play() else { throw CompletionSoundError.playbackDidNotStart }
    }

    private func loadPlayerIfNeeded() throws -> AVAudioPlayer {
        if let player { return player }
        let url = Self.fileExtensions.lazy
            .compactMap { self.bundle.url(forResource: Self.resourceName, withExtension: $0) }
            .first
        guard let url else { throw CompletionSoundError.fileNotFound }
        let loaded = try AVAudioPlayer(contentsOf: url)
        player = loaded
        return loaded
    }
}

/// 成功を表すシステムの振動。端末の振動の設定に従う。
final class SystemCompletionHaptics: CompletionHaptics {
    private let generator = UINotificationFeedbackGenerator()

    func prepare() {
        generator.prepare()
    }

    func play() {
        generator.notificationOccurred(.success)
    }
}
