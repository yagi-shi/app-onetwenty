import Testing
import UIKit
@testable import OneTwenty

/// 文字と背景のコントラスト比（WCAG 2.x）が 4.5:1 以上あることを、ライトとダークの両方で確かめる。
@MainActor
struct AppColorsTests {
    private static let minimumRatio = 4.5

    private func traits(_ style: UIUserInterfaceStyle) -> UITraitCollection {
        UITraitCollection(userInterfaceStyle: style)
    }

    private func components(_ color: UIColor, _ style: UIUserInterfaceStyle) -> [CGFloat] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: traits(style)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue]
    }

    private func luminance(_ color: UIColor, _ style: UIUserInterfaceStyle) -> Double {
        let linear = components(color, style).map { component -> Double in
            let value = Double(component)
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private func contrast(_ first: UIColor, _ second: UIColor, _ style: UIUserInterfaceStyle) -> Double {
        let lighter = max(luminance(first, style), luminance(second, style))
        let darker = min(luminance(first, style), luminance(second, style))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var accent: UIColor {
        get throws { try #require(UIColor(named: "AccentColor")) }
    }

    /// 文字が載りうる背景。画面の地、設定の一覧の地、その上のセル。
    private static let backgrounds: [UIColor] = [
        .systemBackground,
        .systemGroupedBackground,
        .secondarySystemGroupedBackground,
    ]

    @Test("アクセント色の文字は、どの背景の上でも読める", arguments: [UIUserInterfaceStyle.light, .dark])
    func accentTextIsReadable(style: UIUserInterfaceStyle) throws {
        for background in Self.backgrounds {
            #expect(contrast(try accent, background, style) >= Self.minimumRatio, "\(background)")
        }
    }

    @Test("アクセント色で塗ったボタンの上の文字は読める", arguments: [UIUserInterfaceStyle.light, .dark])
    func textOnAccentIsReadable(style: UIUserInterfaceStyle) throws {
        #expect(contrast(AppColors.onAccent, try accent, style) >= Self.minimumRatio)
    }

    @Test("補助的な文字は、どの背景の上でも読める", arguments: [UIUserInterfaceStyle.light, .dark])
    func secondaryTextIsReadable(style: UIUserInterfaceStyle) {
        for background in Self.backgrounds {
            #expect(contrast(AppColors.secondaryText, background, style) >= Self.minimumRatio, "\(background)")
        }
    }

    @Test("Live Activity が使うアクセント色は、アプリ本体のアクセント色と同じ値", arguments: [
        UIUserInterfaceStyle.light, .dark,
    ])
    func liveActivityAccentMatchesAsset(style: UIUserInterfaceStyle) throws {
        let shared = style == .dark ? AccentPalette.dark : AccentPalette.light

        let asset = components(try accent, style)
        let palette = components(shared, style)

        for (assetValue, paletteValue) in zip(asset, palette) {
            #expect(abs(assetValue - paletteValue) < 0.002)
        }
    }

    @Test("Dynamic Island の黒い背景に載せるアクセント色は読める")
    func accentOnBlackIsReadable() {
        #expect(contrast(AccentPalette.dark, .black, .dark) >= Self.minimumRatio)
    }
}
