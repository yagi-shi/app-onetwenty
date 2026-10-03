import SwiftUI
import UIKit

extension Color {
    /// 補助的な文字の色。標準の `.secondary` は、ライトで背景とのコントラストが 4.5:1 に届かないので使わない。
    static let secondaryText = Color(uiColor: AppColors.secondaryText)
}

/// 色の値。背景とのコントラストは、テストで確かめている。
enum AppColors {
    static let secondaryText = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x98 / 255, green: 0x98 / 255, blue: 0x9F / 255, alpha: 1)
            : UIColor(red: 0x6C / 255, green: 0x6C / 255, blue: 0x70 / 255, alpha: 1)
    }

    /// アクセント色で塗った面に載せる文字の色。ダークのアクセント色は明るいので、白ではなく黒にする。
    static let onAccent = UIColor { $0.userInterfaceStyle == .dark ? .black : .white }
}

extension View {
    /// アクセント色で塗ったボタン（`.borderedProminent`）の文字を、背景とのコントラストが保てる色にする。
    func prominentButtonLabel() -> some View {
        modifier(ProminentButtonLabel())
    }
}

private struct ProminentButtonLabel: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        // 押せないときは、標準の薄い表示に任せる
        if isEnabled {
            content.foregroundStyle(Color(uiColor: AppColors.onAccent))
        } else {
            content
        }
    }
}
