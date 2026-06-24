import XCTest
@testable import KeykunCore

final class SettingsTests: XCTestCase {
    func testDefaultValues() {
        let s = Settings.default
        XCTAssertTrue(s.safeQuit.isEnabled)
        XCTAssertEqual(s.safeQuit.interval, 1.0, accuracy: 0.0001)
        // 入力切替は既定で無効。割り当ては左=英数・右=かな（Karabiner 同様の既定）。
        XCTAssertFalse(s.inputSwitch.isEnabled)
        XCTAssertEqual(s.inputSwitch.leftCommandAction, .eisu)
        XCTAssertEqual(s.inputSwitch.rightCommandAction, .kana)
        XCTAssertEqual(s.inputSwitch.tapThreshold, 0.5, accuracy: 0.0001)
    }

    func testInputSwitchCodableRoundTrip() throws {
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.inputSwitch.leftCommandAction = .kana
        s.inputSwitch.rightCommandAction = .none
        s.inputSwitch.tapThreshold = 0.25

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testActionForSide() {
        var s = InputSwitchSettings()
        s.leftCommandAction = .eisu
        s.rightCommandAction = .kana
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
        XCTAssertEqual(decoded.inputSwitch.leftCommandAction, .eisu)
    }

    func testDecodingLegacySourceKeysAreIgnored() throws {
        // 旧方式（leftCommandSourceID 等）の JSON でも、未知キーは無視され既定で補完される。
        let json = """
        { "inputSwitch": { "isEnabled": true, "leftCommandSourceID": "com.apple.keylayout.ABC", "tapThreshold": 0.3 } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.inputSwitch.isEnabled)
        XCTAssertEqual(decoded.inputSwitch.leftCommandAction, .eisu)
        XCTAssertEqual(decoded.inputSwitch.rightCommandAction, .kana)
        XCTAssertEqual(decoded.inputSwitch.tapThreshold, 0.3, accuracy: 0.0001)
    }

    func testCodableRoundTrip() throws {
        var s = Settings.default
        s.safeQuit.isEnabled = false
        s.safeQuit.interval = 1.5

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)

        XCTAssertEqual(decoded, s)
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
