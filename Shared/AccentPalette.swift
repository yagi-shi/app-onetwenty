import SwiftUI
import UIKit

/// アクセント色。ライトとダークで明るさを変え、どちらでも文字として読めるコントラストにしている。
///
/// アプリ本体は Assets の AccentColor を使う。Live Activity の拡張はアセットを持たないので、ここの値を使う。
/// 2 か所の値が同じであることは、テストで確かめている。
nonisolated enum AccentPalette {
    static let light = UIColor(red: 0x47 / 255, green: 0x63 / 255, blue: 0xD4 / 255, alpha: 1)
    static let dark = UIColor(red: 0x7F / 255, green: 0x93 / 255, blue: 0xE1 / 255, alpha: 1)

    /// 表示モードに合わせて切り替わる色。
    static let adaptive = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    /// 表示モードによらず黒い背景に載る場所（Dynamic Island）で使う色。
    static let onBlack = Color(uiColor: dark)
}
