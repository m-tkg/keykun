import XCTest
@testable import KeykunCore

final class SettingsTests: XCTestCase {
    func testDefaultValues() {
        let s = Settings.default
        XCTAssertTrue(s.safeQuit.isEnabled)
        XCTAssertEqual(s.safeQuit.interval, 1.0, accuracy: 0.0001)
        // 入力切替は既定で無効・未割り当て（グローバル挙動を変えるため）。
        XCTAssertFalse(s.inputSwitch.isEnabled)
        XCTAssertNil(s.inputSwitch.leftCommandSourceID)
        XCTAssertNil(s.inputSwitch.rightCommandSourceID)
        XCTAssertEqual(s.inputSwitch.tapThreshold, 0.3, accuracy: 0.0001)
    }

    func testInputSwitchCodableRoundTrip() throws {
        var s = Settings.default
        s.inputSwitch.isEnabled = true
        s.inputSwitch.leftCommandSourceID = "com.apple.keylayout.ABC"
        s.inputSwitch.rightCommandSourceID = "com.apple.inputmethod.Kotoeri.Japanese"
        s.inputSwitch.tapThreshold = 0.25

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testDecodingOldJSONWithoutInputSwitchFillsDefaults() throws {
        // inputSwitch キーが無い旧 JSON でも既定値で補完される。
        let json = """
        { "safeQuit": { "isEnabled": true, "interval": 1.5 } }
        """
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.safeQuit.interval, 1.5, accuracy: 0.0001)
        XCTAssertFalse(decoded.inputSwitch.isEnabled)
        XCTAssertNil(decoded.inputSwitch.leftCommandSourceID)
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
