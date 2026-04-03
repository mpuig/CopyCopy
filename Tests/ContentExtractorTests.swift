import XCTest
@testable import CopyCopy

final class ContentExtractorTests: XCTestCase {
    func testExtractPrefersArticleOverNavigation() throws {
        let html = """
        <html>
          <head>
            <title>Example Article</title>
            <meta name="author" content="Marc Puig">
          </head>
          <body>
            <header><nav><a href="/a">Home</a><a href="/b">Docs</a></nav></header>
            <article class="post-content">
              <h1>Title</h1>
              <p>This is the main article content with enough text to be meaningful.</p>
              <p>It has multiple paragraphs, punctuation, and structure.</p>
            </article>
            <aside class="sidebar"><a href="/c">Related</a><a href="/d">More</a></aside>
          </body>
        </html>
        """

        let extracted = try ContentExtractor.extractMainContent(from: html)

        XCTAssertTrue(extracted.html.contains("<h1>Title</h1>"))
        XCTAssertTrue(extracted.text.contains("main article content"))
        XCTAssertFalse(extracted.html.contains("Related"))
        XCTAssertEqual(extracted.metadata.title, "Example Article")
        XCTAssertEqual(extracted.metadata.author, "Marc Puig")
    }

    func testExtractPrefersStructuredDocumentationOverResourcesSidebar() throws {
        let html = """
        <html>
          <body>
            <section class="page-sidebar">
              <h2>Resources</h2>
              <a href="/install">Install</a>
              <a href="/api">API</a>
              <a href="/security">Security</a>
            </section>
            <main class="article-content">
              <h1>Readability.js</h1>
              <p>A standalone version of the readability library used for Firefox Reader View.</p>
              <h2>Installation</h2>
              <pre><code>npm install @mozilla/readability</code></pre>
              <h2>Basic usage</h2>
              <p>To parse a document, create a new Readability object and call parse().</p>
            </main>
          </body>
        </html>
        """

        let extracted = try ContentExtractor.extractMainContent(from: html)

        XCTAssertTrue(extracted.text.contains("Readability.js"))
        XCTAssertTrue(extracted.text.contains("npm install @mozilla/readability"))
        XCTAssertTrue(extracted.text.contains("Basic usage"))
        XCTAssertFalse(extracted.text.contains("Resources"))
    }

    func testExtractRemovesHiddenAndNewsletterNoise() throws {
        let html = """
        <html>
          <body>
            <main id="content">
              <div style="display: none">Internal hidden analytics text</div>
              <article class="entry-content">
                <h1>Shipping updates</h1>
                <p>The product now supports a richer content extraction pipeline.</p>
                <p>It keeps paragraphs, lists, and code snippets that are part of the real document.</p>
              </article>
              <section class="newsletter-signup">
                <h2>Subscribe to our newsletter</h2>
                <p>Get updates every week.</p>
              </section>
            </main>
          </body>
        </html>
        """

        let extracted = try ContentExtractor.extractMainContent(from: html)

        XCTAssertTrue(extracted.text.contains("Shipping updates"))
        XCTAssertFalse(extracted.text.contains("Internal hidden analytics text"))
        XCTAssertFalse(extracted.text.contains("Subscribe to our newsletter"))
    }

    func testExtractMetadataReadsJSONLDFromRawHTML() throws {
        let html = """
        <html>
          <head>
            <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Article",
              "headline": "Structured Title",
              "author": {
                "@type": "Person",
                "name": "Marc Puig"
              },
              "datePublished": "2026-04-02"
            }
            </script>
          </head>
          <body>
            <article>
              <p>Main content body for the article.</p>
            </article>
          </body>
        </html>
        """

        let extracted = try ContentExtractor.extractMainContent(from: html)

        XCTAssertEqual(extracted.metadata.title, "Structured Title")
        XCTAssertEqual(extracted.metadata.author, "Marc Puig")
        XCTAssertEqual(extracted.metadata.published, "2026-04-02")
    }

    func testExtractDropsLeadingRepositoryListingBeforeMainReadme() throws {
        let html = """
        <html>
          <body>
            <main class="repository-content">
              <section>
                <div><a href="/org/repo/commit/1">Merge pull request</a></div>
                <div><a href="/org/repo/tree/main/src">src</a></div>
                <div>3 days ago</div>
                <div><a href="/org/repo/blob/main/README.md">README.md</a></div>
                <div>yesterday</div>
              </section>
              <article class="markdown-body">
                <h1>Tome</h1>
                <p>Local meeting capture to Obsidian vault to AI agent pipeline.</p>
                <h2>Why Tome?</h2>
                <p>Tome is a macOS app that captures meetings and writes Markdown files.</p>
              </article>
            </main>
          </body>
        </html>
        """

        let extracted = try ContentExtractor.extractMainContent(from: html)

        XCTAssertTrue(extracted.text.contains("Tome"))
        XCTAssertTrue(extracted.text.contains("Why Tome?"))
        XCTAssertFalse(extracted.text.contains("Merge pull request"))
        XCTAssertFalse(extracted.text.contains("3 days ago"))
        XCTAssertFalse(extracted.text.contains("README.md"))
    }
}
