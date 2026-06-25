import XCTest
@testable import KeykunCore

final class ModifierDoublePressSettingsTests: XCTestCase {
    // MARK: - TargetModifier の device 依存ビット（IOLLEvent.h）

    func testTargetModifierDeviceBits() {
        XCTAssertEqual(TargetModifier.command.leftBit, 0x0000_0008)
        XCTAssertEqual(TargetModifier.command.rightBit, 0x0000_0010)
        XCTAssertEqual(TargetModifier.option.leftBit, 0x0000_0020)
        XCTAssertEqual(TargetModifier.option.rightBit, 0x0000_0040)
        XCTAssertEqual(TargetModifier.control.leftBit, 0x0000_0001)
        XCTAssertEqual(TargetModifier.control.rightBit, 0x0000_2000)
        XCTAssertEqual(TargetModifier.shift.leftBit, 0x0000_0002)
        XCTAssertEqual(TargetModifier.shift.rightBit, 0x0000_0004)
    }

    func testTargetModifierCaseIterable() {
        XCTAssertEqual(TargetModifier.allCases, [.command, .option, .control, .shift])
    }

    func testModifierKeyDeviceBit() {
        XCTAssertEqual(ModifierKey(modifier: .command, side: .left).deviceBit, 0x0000_0008)
        XCTAssertEqual(ModifierKey(modifier: .option, side: .right).deviceBit, 0x0000_0040)
    }

    // MARK: - 既定値

    func testDefaultValues() {
        let s = Settings.default
        XCTAssertFalse(s.modifierDoublePress.isEnabled)
        XCTAssertTrue(s.modifierDoublePress.bindings.isEmpty)
    }

    func testTimingIsFixed() {
        // 単押し判定時間・二度押し猶予時間は UI から外し 0.3 固定。
        XCTAssertEqual(ModifierDoublePressTiming.tapThreshold, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ModifierDoublePressTiming.interval, 0.3, accuracy: 0.0001)
    }

    // MARK: - AppTarget

    func testAppTargetIsAssigned() {
        XCTAssertFalse(AppTarget().isAssigned)
        XCTAssertFalse(AppTarget(bundleIdentifier: "", displayName: "X").isAssigned)
        XCTAssertTrue(AppTarget(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal").isAssigned)
    }

    // MARK: - LaunchSide

    func testLaunchSideRawValuesMatchModifierSide() {
        // 旧 JSON 互換のため raw value は "left"/"right" を維持する。
        XCTAssertEqual(LaunchSide.left.rawValue, "left")
        XCTAssertEqual(LaunchSide.right.rawValue, "right")
        XCTAssertEqual(LaunchSide.both.rawValue, "both")
        XCTAssertEqual(LaunchSide.allCases, [.left, .right, .both])
    }

    func testLaunchSideCodableRoundTrip() throws {
        for side in LaunchSide.allCases {
            let data = try JSONEncoder().encode(side)
            let decoded = try JSONDecoder().decode(LaunchSide.self, from: data)
            XCTAssertEqual(decoded, side)
        }
    }

    func testBindingDecodesOldSideValues() throws {
        // 旧 JSON（"left"/"right"）が LaunchSide にデコードできる。
        let json = """
        { "modifier": "command", "side": "right", "app": { "bundleIdentifier": "com.apple.Safari", "displayName": "Safari" } }
        """
        let decoded = try JSONDecoder().decode(ModifierLaunchBinding.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.side, .right)
    }

    func testBindingDecodesBothSide() throws {
        let json = """
        { "modifier": "command", "side": "both", "app": { "bundleIdentifier": "com.apple.Safari", "displayName": "Safari" } }
        """
        let decoded = try JSONDecoder().decode(ModifierLaunchBinding.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.side, .both)
    }

    func testBindingDefaultsSideToLeftWhenMissing() throws {
        let json = """
        { "modifier": "command", "app": { "bundleIdentifier": "com.apple.Safari", "displayName": "Safari" } }
        """
        let decoded = try JSONDecoder().decode(ModifierLaunchBinding.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.side, .left)
    }

    // MARK: - matches

    func testMatchesLeftBindingOnlyMatchesLeftKey() {
        let b = ModifierLaunchBinding(modifier: .command, side: .left)
        XCTAssertTrue(b.matches(ModifierKey(modifier: .command, side: .left)))
        XCTAssertFalse(b.matches(ModifierKey(modifier: .command, side: .right)))
        XCTAssertFalse(b.matches(ModifierKey(modifier: .option, side: .left)))
    }

    func testMatchesRightBindingOnlyMatchesRightKey() {
        let b = ModifierLaunchBinding(modifier: .option, side: .right)
        XCTAssertTrue(b.matches(ModifierKey(modifier: .option, side: .right)))
        XCTAssertFalse(b.matches(ModifierKey(modifier: .option, side: .left)))
    }

    func testMatchesBothBindingMatchesEitherSide() {
        let b = ModifierLaunchBinding(modifier: .command, side: .both)
        XCTAssertTrue(b.matches(ModifierKey(modifier: .command, side: .left)))
        XCTAssertTrue(b.matches(ModifierKey(modifier: .command, side: .right)))
        XCTAssertFalse(b.matches(ModifierKey(modifier: .option, side: .left)))
    }

    // MARK: - watchedKeys

    func testWatchedKeysExpandsBothToBothSides() {
        var s = ModifierDoublePressSettings()
        s.bindings = [
            ModifierLaunchBinding(modifier: .command, side: .both,
                                  app: AppTarget(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")),
        ]
        XCTAssertEqual(Set(s.watchedKeys), [
            ModifierKey(modifier: .command, side: .left),
            ModifierKey(modifier: .command, side: .right),
        ])
    }

    func testWatchedKeysDeduplicatesOverlappingBindings() {
        var s = ModifierDoublePressSettings()
        s.bindings = [
            ModifierLaunchBinding(modifier: .command, side: .both,
                                  app: AppTarget(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")),
            ModifierLaunchBinding(modifier: .command, side: .left,
                                  app: AppTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari")),
        ]
        // .both の左右 2 件と .left が重なり、重複は除去されて 2 キー。
        XCTAssertEqual(Set(s.watchedKeys), [
            ModifierKey(modifier: .command, side: .left),
            ModifierKey(modifier: .command, side: .right),
        ])
        XCTAssertEqual(s.watchedKeys.count, 2)
    }

    func testWatchedKeysExcludesUnassignedBindings() {
        var s = ModifierDoublePressSettings()
        s.bindings = [
            ModifierLaunchBinding(modifier: .command, side: .both, app: AppTarget()),
            ModifierLaunchBinding(modifier: .option, side: .left,
                                  app: AppTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari")),
        ]
        XCTAssertEqual(s.watchedKeys, [ModifierKey(modifier: .option, side: .left)])
    }

    // MARK: - app(for:)

    func testAppForBothBindingReturnsSameAppForEitherSide() {
        var s = ModifierDoublePressSettings()
        s.bindings = [
            ModifierLaunchBinding(modifier: .command, side: .both,
                                  app: AppTarget(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")),
        ]
        XCTAssertEqual(s.app(for: ModifierKey(modifier: .command, side: .left))?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(s.app(for: ModifierKey(modifier: .command, side: .right))?.bundleIdentifier, "com.apple.Terminal")
    }

    func testAppForKeyReturnsAssignedBinding() {
        var s = ModifierDoublePressSettings()
        s.bindings = [
            ModifierLaunchBinding(modifier: .command, side: .left,
                                  app: AppTarget(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")),
            ModifierLaunchBinding(modifier: .option, side: .right,
                                  app: AppTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari")),
        ]
        XCTAssertEqual(s.app(for: ModifierKey(modifier: .command, side: .left))?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(s.app(for: ModifierKey(modifier: .option, side: .right))?.bundleIdentifier, "com.apple.Safari")
    }

    func testAppForKeyReturnsNilWhenUnassignedOrMissing() {
        var s = ModifierDoublePressSettings()
        s.bindings = [ModifierLaunchBinding(modifier: .command, side: .left, app: AppTarget())]
        // 割り当て未設定 → nil。
        XCTAssertNil(s.app(for: ModifierKey(modifier: .command, side: .left)))
        // そもそも該当バインディングなし → nil。
        XCTAssertNil(s.app(for: ModifierKey(modifier: .shift, side: .right)))
    }

    // MARK: - Codable 互換

    func testCodableRoundTrip() throws {
        var s = Settings.default
        s.modifierDoublePress.isEnabled = true
        s.modifierDoublePress.bindings = [
            ModifierLaunchBinding(modifier: .option, side: .left,
                                  app: AppTarget(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")),
            ModifierLaunchBinding(modifier: .control, side: .right,
                                  app: AppTarget(bundleIdentifier: "com.apple.Safari", displayName: "Safari")),
        ]

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testDecodingOldJSONWithoutModifierDoublePressFillsDefaults() throws {
        let json = """
        { "safeQuit": { "isEnabled": true, "interval": 1.5 } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.modifierDoublePress.isEnabled)
        XCTAssertTrue(decoded.modifierDoublePress.bindings.isEmpty)
    }

    func testDecodingEmptyObjectFallsBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, Settings.default)
    }

    // MARK: - 入力切替との衝突判定

    func testNoConflictWhenModifierDoublePressDisabled() {
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.modifierDoublePress.isEnabled = false
        s.modifierDoublePress.bindings = [ModifierLaunchBinding(modifier: .command, side: .left)]
        XCTAssertFalse(s.hasModifierConflict)
    }

    func testNoConflictWhenInputSwitchDisabled() {
        var s = Settings.default
        s.inputSwitch.isEnabled = false
        s.modifierDoublePress.isEnabled = true
        s.modifierDoublePress.bindings = [ModifierLaunchBinding(modifier: .command, side: .left)]
        XCTAssertFalse(s.hasModifierConflict)
    }

    func testConflictWhenBothEnabledAndSomeBindingUsesCommand() {
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.modifierDoublePress.isEnabled = true
        s.modifierDoublePress.bindings = [
            ModifierLaunchBinding(modifier: .option, side: .left),
            ModifierLaunchBinding(modifier: .command, side: .right),
        ]
        XCTAssertTrue(s.hasModifierConflict)
    }

    func testConflictWhenBothSideBindingUsesCommand() {
        // side が .both（⌘）でも入力切替と衝突検知する。
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.modifierDoublePress.isEnabled = true
        s.modifierDoublePress.bindings = [
            ModifierLaunchBinding(modifier: .command, side: .both),
        ]
        XCTAssertTrue(s.hasModifierConflict)
    }

    func testNoConflictWhenNoBindingUsesCommand() {
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.modifierDoublePress.isEnabled = true
        s.modifierDoublePress.bindings = [
            ModifierLaunchBinding(modifier: .option, side: .left),
            ModifierLaunchBinding(modifier: .control, side: .right),
        ]
        XCTAssertFalse(s.hasModifierConflict)
    }
}
