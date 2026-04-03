import XCTest
@testable import CopyCopy

final class SourceAppContextTests: XCTestCase {
    func testEmailAppsMapToEmailContext() {
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.apple.mail", appName: "Mail"), .email)
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.microsoft.Outlook", appName: "Microsoft Outlook"), .email)
    }

    func testChatAppsMapToChatContext() {
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.tinyspeck.slackmacgap", appName: "Slack"), .chat)
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.microsoft.teams2", appName: "Microsoft Teams"), .chat)
    }

    func testNotesAppsMapToNotesContext() {
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.apple.Notes", appName: "Notes"), .notes)
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "md.obsidian", appName: "Obsidian"), .notes)
    }

    func testIDEAppsStillMapToIDEContext() {
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.apple.dt.Xcode", appName: "Xcode"), .ide)
        XCTAssertEqual(SourceAppContext(bundleIdentifier: "com.cursor.Cursor", appName: "Cursor"), .ide)
    }
}
