import XCTest
@testable import KeykunCore

final class SettingsStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("keykun-test-\(UUID().uuidString)")
            .appendingPathComponent("settings.json")
    }

    func testLoadReturnsDefaultWhenFileMissing() {
        let store = SettingsStore(url: tempURL())
        XCTAssertEqual(store.load(), Settings.default)
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = tempURL()
        let store = SettingsStore(url: url)

        var s = Settings.default
        s.safeQuit.isEnabled = false
        s.safeQuit.interval = 0.5
        try store.save(s)

        XCTAssertEqual(store.load(), s)
    }

    func testLoadReturnsDefaultWhenFileCorrupted() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = SettingsStore(url: url)
        XCTAssertEqual(store.load(), Settings.default)
    }
}
