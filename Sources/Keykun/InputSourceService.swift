import Carbon
import Foundation

/// 入力ソースの表示用情報。
struct InputSourceInfo: Identifiable, Hashable {
    /// 入力ソース ID（例: `com.apple.keylayout.ABC`）。設定に保存する値。
    let id: String
    /// ローカライズされた表示名（例: 「ABC」「ひらがな」）。
    let localizedName: String
}

/// macOS の Text Input Source（TIS / Carbon）API のラッパ。
/// 選択可能なキーボード入力ソースの列挙と、ID 指定での切り替えを提供する。
enum InputSourceService {
    /// ユーザーが有効化している、選択可能なキーボード入力ソースの一覧。
    static func selectable() -> [InputSourceInfo] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.compactMap { source in
            guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
            let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
            return InputSourceInfo(id: id, localizedName: name)
        }
    }

    /// 指定 ID の入力ソースに切り替える。
    static func select(id: String) {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: id]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource],
            let source = list.first else {
            return
        }
        TISSelectInputSource(source)
    }

    /// TISInputSource の文字列プロパティを取り出す。
    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
