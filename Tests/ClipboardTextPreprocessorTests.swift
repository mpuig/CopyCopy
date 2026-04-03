import XCTest
@testable import CopyCopy

final class ClipboardTextPreprocessorTests: XCTestCase {
    func testSanitizeForLLMRemovesChatChromeLines() {
        let raw = """
        Search Boston Consulting Group
        Home
        1
        DMs
        2

        Messages
        Addison Ulhaq 5:21 PM
        i'm having problems accessing marketplace currently.
        Alexa Canaan 6:37 PM
        Responsible AI is Hiring

        Message x-ai-software
        Shift + Return to add a new line
        """

        let cleaned = ClipboardTextPreprocessor.sanitizeForLLM(raw)

        XCTAssertFalse(cleaned.contains("Search Boston Consulting Group"))
        XCTAssertFalse(cleaned.contains("Shift + Return to add a new line"))
        XCTAssertFalse(cleaned.contains("Message x-ai-software"))
        XCTAssertTrue(cleaned.contains("Addison Ulhaq 5:21 PM"))
        XCTAssertTrue(cleaned.contains("Responsible AI is Hiring"))
    }

    func testSanitizeForLLMDropsDecorativeTrailingTokenLinesInChatTranscript() {
        let raw = """
        Addison Ulhaq 5:21 PM
        i'm having problems accessing marketplace currently.
        Alexa Canaan 6:37 PM
        Responsible AI is Hiring
        Message x-ai-software
        Shift + Return to add a new line
        :palm_tree:
        """

        let cleaned = ClipboardTextPreprocessor.sanitizeForLLM(raw)

        XCTAssertFalse(cleaned.contains(":palm_tree:"))
        XCTAssertFalse(cleaned.contains("Shift + Return to add a new line"))
        XCTAssertTrue(cleaned.contains("Responsible AI is Hiring"))
        XCTAssertTrue(cleaned.contains("i'm having problems accessing marketplace currently."))
    }

    func testBestLLMInputPrefersPlainTextWhenHTMLExtractionLooksLikeFooter() {
        let snapshot = ClipboardSnapshot(
            changeCount: 1,
            kind: .plainText,
            representationKind: .semanticHTML,
            summary: "Test",
            plainText: """
            Addison Ulhaq 5:21 PM
            i'm having problems accessing marketplace currently.
            Alexa Canaan 6:37 PM
            Responsible AI is Hiring
            """,
            htmlText: """
            <html><body><div>Shift + Return to add a new line</div></body></html>
            """
        )

        let best = ClipboardTextPreprocessor.bestLLMInput(from: snapshot)

        XCTAssertEqual(
            best,
            """
            Addison Ulhaq 5:21 PM
            i'm having problems accessing marketplace currently.
            Alexa Canaan 6:37 PM
            Responsible AI is Hiring
            """
        )
    }
}
