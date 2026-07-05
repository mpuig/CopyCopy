import XCTest
@testable import CopyCopy

@MainActor
final class SkillLoaderTests: XCTestCase {

    func testAllBuiltInSkillsParse() throws {
        for (id, content) in BuiltInSkills.all {
            let skills = try SkillParser.parseAll(id: id, content: content, isBuiltIn: true)
            XCTAssertFalse(skills.isEmpty, "Skill '\(id)' produced no actions")
            for skill in skills {
                XCTAssertNotNil(skill.executeFunction, "Skill '\(skill.id)' has invalid execute '\(skill.execute)'")
                XCTAssertFalse(skill.description.isEmpty, "Skill '\(skill.id)' has empty description")
            }
        }
    }

    func testSkillMatchesContentType() throws {
        let skill = try SkillParser.parse(id: "test", content: """
        ---
        name: Test
        description: Test skill
        content-types: url
        ---

        openURL({clipboardURL})
        """, isBuiltIn: true)

        // URL content should match
        XCTAssertTrue(skill.contentTypes.contains(where: { $0.matches(.url) }))
        // Text content should NOT match
        XCTAssertFalse(skill.contentTypes.contains(where: { $0.matches(.plainText) }))
    }

    func testSkillMatchesEntityType() throws {
        let skill = try SkillParser.parse(id: "test", content: """
        ---
        name: Test
        description: Test skill
        content-types: text
        entity-types: json, base64
        ---

        formatJSON({clipboard})
        """, isBuiltIn: true)

        XCTAssertTrue(skill.entityTypes.contains(where: { $0.matchesAny([.json]) }))
        XCTAssertTrue(skill.entityTypes.contains(where: { $0.matchesAny([.base64]) }))
        XCTAssertFalse(skill.entityTypes.contains(where: { $0.matchesAny([.html]) }))
    }

    func testSourceContextFilterMatches() {
        XCTAssertTrue(SourceContextFilter.terminal.matches(.terminal))
        XCTAssertFalse(SourceContextFilter.terminal.matches(.browser))
        XCTAssertTrue(SourceContextFilter.any.matches(.browser))
        XCTAssertTrue(SourceContextFilter.any.matches(.terminal))
    }

    func testContentTypeFilterMatches() {
        XCTAssertTrue(ContentTypeFilter.text.matches(.plainText))
        XCTAssertTrue(ContentTypeFilter.text.matches(.richText))
        XCTAssertFalse(ContentTypeFilter.text.matches(.url))
        XCTAssertTrue(ContentTypeFilter.any.matches(.url))
        XCTAssertTrue(ContentTypeFilter.files.matches(.fileURLs))
    }

    func testEntityFilterMatchesAny() {
        XCTAssertTrue(EntityFilter.json.matchesAny([.json, .html]))
        XCTAssertFalse(EntityFilter.json.matchesAny([.html, .base64]))
        XCTAssertTrue(EntityFilter.any.matchesAny([]))
        XCTAssertTrue(EntityFilter.any.matchesAny([.json]))
    }

    func testMatchingActionsTruncatesToLimit() {
        // A plain-text copy matches several built-in text skills (clean-text, fix-grammar,
        // summarize, extract-action-items, decode-url, …). Without a limit the full ranked
        // list is returned; with a limit the already-ranked list is truncated in place.
        let loader = SkillLoader()
        let executor = ToolExecutor()
        let snapshot = ClipboardSnapshot(
            changeCount: 1,
            kind: .plainText,
            summary: "text",
            plainText: String(repeating: "word ", count: 40)
        )
        let context = ClipboardContext(copyEvent: nil, snapshot: snapshot, capturedAt: 0)

        let uncapped = loader.matchingActions(
            for: .plainText,
            sourceContext: .other,
            entities: [],
            context: context,
            executor: executor
        )
        // Several text skills always match a plain-text copy.
        XCTAssertGreaterThan(uncapped.count, 3)

        let limit = 3
        let capped = loader.matchingActions(
            for: .plainText,
            sourceContext: .other,
            entities: [],
            context: context,
            executor: executor,
            limit: limit
        )
        XCTAssertEqual(capped.count, min(limit, uncapped.count))
        // Truncation preserves the top of the already-ranked list (no reordering).
        XCTAssertEqual(capped.map(\.skillId), Array(uncapped.prefix(limit)).map(\.skillId))
    }

    func testUsageHistoryBoostFormula() {
        // boost = min(50, count * 10)
        // 0 uses → 0 boost
        // 3 uses → 30 boost
        // 5+ uses → 50 boost (capped)
        let history = UsageHistory.shared
        let boost0 = history.boost(for: "nonexistent-skill", contentKind: .plainText, sourceContext: .other)
        XCTAssertEqual(boost0, 0)
    }
}
