import Foundation

/// 任意のファイルを置いた一時フォルダを、バンドルとして読ませるためのテスト用の入れ物。
final class TemporaryBundle {
    let bundle: Bundle
    private let directory: URL

    /// - Parameter files: ファイル名と中身（文字列）の対応。
    /// - Parameter dataFiles: ファイル名と中身（バイト列）の対応。
    init(files: [String: String] = [:], dataFiles: [String: Data] = [:]) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("onetwenty.tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
        }
        for (name, data) in dataFiles {
            try data.write(to: directory.appendingPathComponent(name))
        }
        guard let bundle = Bundle(url: directory) else {
            throw CocoaError(.fileReadUnknown)
        }
        self.bundle = bundle
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
