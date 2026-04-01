import Cocoa
import XCTest
@testable import CopyCopy

final class CustomActionTests: XCTestCase {
    var action: CustomAction!

    override func setUp() {
        super.setUp()
        action = CustomAction(
            id: UUID(),
            name: "Test Action",
            actionType: .openURL,
            template: "https://example.com/search?q={text:encoded}",
            contentFilter: .text
        )
    }

    func testProcessTemplateText() {
        let result = action.processTemplate(with: "hello world")
        XCTAssertEqual(result, "https://example.com/search?q=hello%20world")
    }

    func testProcessTemplateTextUppercase() {
        let result = action.processTemplate(with: "test")
        XCTAssertEqual(result, "https://example.com/search?q=test")
    }

    func testProcessTemplateTrimmed() {
        let result = action.processTemplate(with: "  hello  ")
        XCTAssertTrue(result.contains("hello"))
    }

    func testProcessTemplateLineCount() {
        let result = action.processTemplate(with: "line1\nline2\nline3")
        XCTAssertTrue(result.contains("3"))
    }

    func testProcessTemplateCharCount() {
        action.template = "Chars: {charcount}"
        let result = action.processTemplate(with: "hello")
        XCTAssertTrue(result.contains("5"))
    }

    func testContentTypeFilterAny() {
        let filter = ContentTypeFilter.any
        XCTAssertTrue(filter.matches(.plainText))
        XCTAssertTrue(filter.matches(.url))
        XCTAssertTrue(filter.matches(.image))
        XCTAssertTrue(filter.matches(.fileURLs))
    }

    func testContentTypeFilterText() {
        let filter = ContentTypeFilter.text
        XCTAssertTrue(filter.matches(.plainText))
        XCTAssertTrue(filter.matches(.richText))
        XCTAssertFalse(filter.matches(.url))
        XCTAssertFalse(filter.matches(.image))
    }

    func testContentTypeFilterURL() {
        let filter = ContentTypeFilter.url
        XCTAssertTrue(filter.matches(.url))
        XCTAssertFalse(filter.matches(.plainText))
        XCTAssertFalse(filter.matches(.image))
    }

    func testContentTypeFilterImage() {
        let filter = ContentTypeFilter.image
        XCTAssertTrue(filter.matches(.image))
        XCTAssertFalse(filter.matches(.plainText))
        XCTAssertFalse(filter.matches(.url))
    }

    func testContentTypeFilterFiles() {
        let filter = ContentTypeFilter.files
        XCTAssertTrue(filter.matches(.fileURLs))
        XCTAssertFalse(filter.matches(.plainText))
        XCTAssertFalse(filter.matches(.url))
    }

    func testSourceContextFilterAny() {
        let filter = SourceContextFilter.any
        XCTAssertTrue(filter.matches(.other))
        XCTAssertTrue(filter.matches(.browser))
        XCTAssertTrue(filter.matches(.ide))
        XCTAssertTrue(filter.matches(.terminal))
    }

    func testSourceContextFilterBrowser() {
        let filter = SourceContextFilter.browser
        XCTAssertFalse(filter.matches(.other))
        XCTAssertTrue(filter.matches(.browser))
        XCTAssertFalse(filter.matches(.ide))
    }

    func testSourceContextFilterTerminal() {
        let filter = SourceContextFilter.terminal
        XCTAssertFalse(filter.matches(.other))
        XCTAssertTrue(filter.matches(.terminal))
        XCTAssertFalse(filter.matches(.ide))
    }

    func testEntityFilterAny() {
        let filter = EntityFilter.any
        XCTAssertTrue(filter.matches(.none))
        XCTAssertTrue(filter.matches(.email))
        XCTAssertTrue(filter.matches(.phoneNumber))
    }

    func testEntityFilterEmail() {
        let filter = EntityFilter.email
        XCTAssertTrue(filter.matches(.email))
        XCTAssertFalse(filter.matches(.phoneNumber))
        XCTAssertFalse(filter.matches(.none))
    }

    func testEntityFilterMatchesAny() {
        XCTAssertTrue(EntityFilter.codeSnippet.matchesAny([.none, .codeSnippet]))
        XCTAssertTrue(EntityFilter.slackDraft.matchesAny([.emailDraft, .slackDraft]))
        XCTAssertFalse(EntityFilter.emailDraft.matchesAny([.codeSnippet, .markdown]))
    }

    func testActionTypeDisplayName() {
        XCTAssertEqual(ActionType.openURL.displayName, "Open URL")
        XCTAssertEqual(ActionType.shellCommand.displayName, "Run Shell Command")
        XCTAssertEqual(ActionType.openApp.displayName, "Open App")
        XCTAssertEqual(ActionType.revealInFinder.displayName, "Reveal in Finder")
        XCTAssertEqual(ActionType.openFile.displayName, "Open File")
        XCTAssertEqual(ActionType.copyToClipboard.displayName, "Copy to Clipboard")
        XCTAssertEqual(ActionType.saveImage.displayName, "Save Image")
        XCTAssertEqual(ActionType.saveTempFile.displayName, "Save as Temp File")
        XCTAssertEqual(ActionType.stripANSI.displayName, "Strip ANSI Codes")
    }

    func testActionTypeRequiresTemplate() {
        XCTAssertTrue(ActionType.openURL.requiresTemplate)
        XCTAssertTrue(ActionType.shellCommand.requiresTemplate)
        XCTAssertTrue(ActionType.openApp.requiresTemplate)
        XCTAssertTrue(ActionType.copyToClipboard.requiresTemplate)
        XCTAssertFalse(ActionType.revealInFinder.requiresTemplate)
        XCTAssertFalse(ActionType.openFile.requiresTemplate)
        XCTAssertFalse(ActionType.saveImage.requiresTemplate)
        XCTAssertFalse(ActionType.saveTempFile.requiresTemplate)
        XCTAssertFalse(ActionType.stripANSI.requiresTemplate)
    }

    func testDefaultActionsExist() {
        XCTAssertFalse(CustomAction.defaultActions.isEmpty)
    }

    func testDefaultActionsHaveBuiltInFlag() {
        for action in CustomAction.defaultActions {
            XCTAssertTrue(action.isBuiltIn, "Default action \(action.name) should be marked as built-in")
        }
    }

    func testDefaultActionsHaveValidUUIDs() {
        for action in CustomAction.defaultActions {
            XCTAssertNotNil(UUID(uuidString: action.id.uuidString), "Invalid UUID for action \(action.name)")
        }
    }

    func testDefaultActionsHaveValidActionTypes() {
        for action in CustomAction.defaultActions {
            XCTAssertTrue(ActionType.allCases.contains(action.actionType), "Invalid action type for \(action.name)")
        }
    }
}
