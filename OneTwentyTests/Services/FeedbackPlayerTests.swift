import AVFoundation
import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct FeedbackPlayerTests {

    private final class SpySound: CompletionSound {
        struct Failure: Error {}
        var fails = false
        private(set) var prepareCount = 0
        private(set) var playCount = 0

        func prepare() { prepareCount += 1 }

        func play() throws {
            playCount += 1
            if fails { throw Failure() }
        }
    }

    private final class SpyHaptics: CompletionHaptics {
        private(set) var prepareCount = 0
        private(set) var playCount = 0

        func prepare() { prepareCount += 1 }
        func play() { playCount += 1 }
    }

    /// 無音の、ごく短い WAV ファイル。
    private func silentWAV() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 400
        let dataSize = sampleCount * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + dataSize)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))          // fmt チャンクの長さ
        append(UInt16(1))           // PCM
        append(UInt16(1))           // モノラル
        append(sampleRate)
        append(sampleRate * 2)      // 1 秒あたりのバイト数
        append(UInt16(2))           // 1 サンプルのバイト数
        append(UInt16(16))          // 量子化ビット数
        data.append(contentsOf: Array("data".utf8))
        append(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    // MARK: 音と振動を同じ呼び出しで鳴らす

    @Test("完了時に、音と振動を 1 回ずつ鳴らす")
    func playsSoundAndHapticsOnce() {
        let sound = SpySound()
        let haptics = SpyHaptics()

        SystemFeedbackPlayer(sound: sound, haptics: haptics).playCompletion()

        #expect(sound.playCount == 1)
        #expect(haptics.playCount == 1)
    }

    @Test("音の再生に失敗しても、振動は鳴らす")
    func hapticsPlayEvenWhenSoundFails() {
        let sound = SpySound()
        sound.fails = true
        let haptics = SpyHaptics()

        SystemFeedbackPlayer(sound: sound, haptics: haptics).playCompletion()

        #expect(haptics.playCount == 1)
    }

    @Test("事前の読み込みは、音と振動の両方に対して行う")
    func preparesBoth() {
        let sound = SpySound()
        let haptics = SpyHaptics()

        SystemFeedbackPlayer(sound: sound, haptics: haptics).prepare()

        #expect(sound.prepareCount == 1)
        #expect(haptics.prepareCount == 1)
        #expect(sound.playCount == 0)
        #expect(haptics.playCount == 0)
    }

    // MARK: 同梱した完了音

    @Test("完了音のファイルがなければ再生は失敗するが、振動は鳴り、アプリは止まらない")
    func missingSoundFile() throws {
        let empty = try TemporaryBundle()
        let sound = BundledCompletionSound(bundle: empty.bundle)
        let haptics = SpyHaptics()

        #expect(throws: CompletionSoundError.self) { try sound.play() }

        let player = SystemFeedbackPlayer(sound: sound, haptics: haptics)
        player.prepare()
        player.playCompletion()
        #expect(haptics.playCount == 1)
    }

    @Test("完了音のファイルが壊れていても、振動は鳴る")
    func brokenSoundFile() throws {
        let broken = try TemporaryBundle(files: ["completion.caf": "音声ではない"])
        let haptics = SpyHaptics()

        SystemFeedbackPlayer(sound: BundledCompletionSound(bundle: broken.bundle), haptics: haptics).playCompletion()

        #expect(haptics.playCount == 1)
    }

    @Test("完了音は、消音スイッチで鳴らなくなる種類の音として再生する")
    func playsWithAmbientCategory() throws {
        let files = try TemporaryBundle(dataFiles: ["completion.wav": silentWAV()])
        let sound = BundledCompletionSound(bundle: files.bundle)

        sound.prepare()
        try sound.play()

        #expect(AVAudioSession.sharedInstance().category == .ambient)
    }

    @Test("アプリ本体のバンドルで鳴らしても止まらず、振動は鳴る")
    func worksWithAppBundle() {
        let haptics = SpyHaptics()
        let player = SystemFeedbackPlayer(sound: BundledCompletionSound(), haptics: haptics)

        player.prepare()
        player.playCompletion()

        #expect(haptics.playCount == 1)
    }
}
