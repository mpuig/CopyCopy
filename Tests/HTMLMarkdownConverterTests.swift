import XCTest
@testable import CopyCopy

final class HTMLMarkdownConverterTests: XCTestCase {
    func testConvertNormalizesNonBreakingSpaces() throws {
        let html = """
        <html>
          <body>
            <article>
              <p>The&nbsp;options&nbsp;object accepts a number of properties.</p>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("The options object accepts a number of properties."))
        XCTAssertFalse(markdown.contains("\u{00A0}"))
        XCTAssertFalse(markdown.contains("NBSP"))
    }

    func testConvertSupportsTaskListsAndTables() throws {
        let html = """
        <html>
          <body>
            <article>
              <ul>
                <li><input type="checkbox" checked>Done</li>
                <li><input type="checkbox">Todo</li>
              </ul>
              <table>
                <thead>
                  <tr><th>Name</th><th>Value</th></tr>
                </thead>
                <tbody>
                  <tr><td>Mode</td><td>Fast</td></tr>
                </tbody>
              </table>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("- [x] Done"))
        XCTAssertTrue(markdown.contains("- [ ] Todo"))
        XCTAssertTrue(markdown.contains("| Name"))
        XCTAssertTrue(markdown.contains("| Mode"))
    }

    func testConvertInfersCodeFenceLanguage() throws {
        let html = """
        <html>
          <body>
            <article>
              <pre data-lang="swift"><code>print("Hello")</code></pre>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("```swift"))
        XCTAssertTrue(markdown.contains("print(\"Hello\")"))
    }

    func testConvertNormalizesCalloutsToBlockquoteSyntax() throws {
        let html = """
        <html>
          <body>
            <article>
              <div class="markdown-alert markdown-alert-warning">
                <p class="markdown-alert-title">Warning</p>
                <p>Production access is restricted.</p>
              </div>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("> [!WARNING]"))
        XCTAssertTrue(markdown.contains("> Production access is restricted."))
    }

    func testConvertDoesNotInferLanguageFromArbitraryClassToken() throws {
        let html = """
        <html>
          <body>
            <article>
              <pre class="copy"><code>print("Hello")</code></pre>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("```"))
        XCTAssertFalse(markdown.contains("```copy"))
    }

    func testConvertNormalizesFootnotes() throws {
        let html = """
        <html>
          <body>
            <article>
              <p>Text with a note<sup><a href="#fn1">1</a></sup>.</p>
              <section class="footnotes">
                <ol>
                  <li id="fn1">Footnote body</li>
                </ol>
              </section>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("[^1]"))
        XCTAssertTrue(markdown.contains("[^1]: Footnote body"))
    }

    func testConvertNormalizesKatexMath() throws {
        let html = """
        <html>
          <body>
            <article>
              <span class="katex">
                <span class="katex-mathml">
                  <math><semantics><annotation encoding="application/x-tex">E=mc^2</annotation></semantics></math>
                </span>
              </span>
            </article>
          </body>
        </html>
        """

        let markdown = try HTMLMarkdownConverter.convert(html)

        XCTAssertTrue(markdown.contains("$E=mc^2$"))
    }
}
