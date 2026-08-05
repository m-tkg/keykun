import XCTest
@testable import KeykunCore

final class SettingsTests: XCTestCase {
    func testDefaultValues() {
        let s = Settings.default
        XCTAssertTrue(s.safeQuit.isEnabled)
        XCTAssertEqual(s.safeQuit.interval, 1.0, accuracy: 0.0001)
        // 入力切替は既定で無効。対象は Option、割り当ては左=英数・右=かな。
        XCTAssertFalse(s.inputSwitch.isEnabled)
        XCTAssertEqual(s.inputSwitch.targetModifier, .option)
        XCTAssertEqual(s.inputSwitch.leftAction, .eisu)
        XCTAssertEqual(s.inputSwitch.rightAction, .kana)
        XCTAssertEqual(s.inputSwitch.tapThreshold, 0.5, accuracy: 0.0001)
        XCTAssertFalse(s.slackEscape.isEnabled)
    }

    func testInputSwitchCodableRoundTrip() throws {
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.inputSwitch.targetModifier = .command
        s.inputSwitch.leftAction = .kana
        s.inputSwitch.rightAction = .none
        s.inputSwitch.tapThreshold = 0.25

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testActionForSide() {
        var s = InputSwitchSettings()
        s.leftAction = .eisu
        s.rightAction = .kana
        XCTAssertEqual(s.action(for: .left), .eisu)
        XCTAssertEqual(s.action(for: .right), .kana)
    }

    func testDecodingOldJSONWithoutInputSwitchFillsDefaults() throws {
        // inputSwitch キーが無い旧 JSON でも既定値で補完される。
        let json = """
        { "safeQuit": { "isEnabled": true, "interval": 1.5 } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.safeQuit.interval, 1.5, accuracy: 0.0001)
        XCTAssertFalse(decoded.inputSwitch.isEnabled)
        XCTAssertEqual(decoded.inputSwitch.leftAction, .eisu)
        XCTAssertFalse(decoded.slackEscape.isEnabled)
    }

    func testDecodingLegacySourceKeysAreIgnored() throws {
        // 旧方式（leftCommandSourceID 等）の JSON でも、未知キーは無視され既定で補完される。
        let json = """
        { "inputSwitch": { "isEnabled": true, "leftCommandSourceID": "com.apple.keylayout.ABC", "tapThreshold": 0.3 } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.inputSwitch.isEnabled)
        XCTAssertEqual(decoded.inputSwitch.targetModifier, .option)
        XCTAssertEqual(decoded.inputSwitch.leftAction, .eisu)
        XCTAssertEqual(decoded.inputSwitch.rightAction, .kana)
        XCTAssertEqual(decoded.inputSwitch.tapThreshold, 0.3, accuracy: 0.0001)
    }

    func testCodableRoundTrip() throws {
        var s = Settings.default
        s.safeQuit.isEnabled = false
        s.safeQuit.interval = 1.5
        s.slackEscape.isEnabled = true

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(decoded, s)
    }

    func testSlackEscapeCodableRoundTrip() throws {
        var s = Settings.default
        s.slackEscape.isEnabled = true

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(decoded.slackEscape, SlackEscapeSettings(isEnabled: true))
    }

    func testDecodingEmptyObjectFallsBackToDefaults() throws {
        // 旧バージョン等で空の JSON でも既定値で埋まること（前方/後方互換）。
        let data = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, Settings.default)
    }

    func testDecodingPartialSafeQuitFillsMissingKeys() throws {
        // safeQuit に interval だけある JSON → isEnabled は既定値で補完。
        let json = """
        { "safeQuit": { "interval": 2.0 } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.safeQuit.interval, 2.0, accuracy: 0.0001)
        XCTAssertTrue(decoded.safeQuit.isEnabled)
    }
}
