// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Keykun",
    // ローカライズ済みリソース（en/ja）を持つため既定言語を指定する。
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit/CGEventTap に依存しない判定ロジック・設定モデル
        .target(
            name: "KeykunCore"
        ),
        // 実行ファイル本体: メニューバー常駐・CGEventTap・HUD・設定UI・AX 連携
        .executableTarget(
            name: "Keykun",
            dependencies: ["KeykunCore"],
            // en.lproj / ja.lproj の Localizable.strings をリソースバンドルに含める。
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KeykunCoreTests",
            dependencies: ["KeykunCore"]
        ),
    ]
)
