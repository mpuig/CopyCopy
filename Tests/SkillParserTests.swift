import XCTest
@testable import CopyCopy

final class SkillParserTests: XCTestCase {
    func testParseJSONToolsBlock() throws {
        let content = """
        ---
        name: test
        description: Test skill
        metadata:
          copycopy-content-types: "text"
          copycopy-entity-types: "json"
        ---

        # Test

        ## Tools

        ```json
        [
          {
            "id": "pretty-json",
            "name": "Pretty Print JSON",
            "description": "Pretty Print JSON",
            "icon": "curlybraces",
            "execute": "formatJSON",
            "parameters": {
              "type": "object",
              "properties": {
                "json": {"type": "string", "description": "Clipboard JSON", "source": "clipboard"}
              },
              "required": ["json"]
            },
            "entityTypes": ["json"]
          }
        ]
        ```
        """

        let skill = try SkillParser.parse(id: "test", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.tools.count, 1)
        XCTAssertEqual(skill.contentTypes, [.text])
        XCTAssertEqual(skill.tools[0].executeFunction, .formatJSON)
        XCTAssertEqual(skill.tools[0].parameters.properties["json"]?.source, "clipboard")
        XCTAssertEqual(skill.tools[0].parsedEntityTypes, [.json])
    }

    func testParseLegacyActionFallback() throws {
        let content = """
        ---
        name: legacy
        description: Legacy skill
        metadata:
          content_types: [text]
        ---

        # Legacy

        ## Actions

        ### search-web
        type: function
        function: openURL
        template: https://duckduckgo.com/?q={text:encoded}
        icon: magnifyingglass
        description: Search the Web

        ### summarize
        type: prompt
        prompt: Summarize the clipboard text.
        icon: text.redaction
        description: Summarize Content
        """

        let skill = try SkillParser.parse(id: "legacy", content: content, isBuiltIn: false)

        XCTAssertEqual(skill.tools.count, 2)

        let searchTool = try XCTUnwrap(skill.tools.first { $0.id == "search-web" })
        XCTAssertEqual(searchTool.executeFunction, .openURLTemplate)
        XCTAssertEqual(searchTool.parameters.properties["baseURL"]?.value, "https://duckduckgo.com/")
        XCTAssertEqual(searchTool.parameters.properties["q"]?.source, "clipboard")

        let summarizeTool = try XCTUnwrap(skill.tools.first { $0.id == "summarize" })
        XCTAssertEqual(summarizeTool.executeFunction, .llmPrompt)
        XCTAssertEqual(summarizeTool.parameters.properties["systemPrompt"]?.value, "Summarize the clipboard text.")
        XCTAssertEqual(summarizeTool.parameters.properties["prompt"]?.source, "clipboard")
    }

    func testBuiltInSkillExportsReadableActionsMarkdown() throws {
        let skill = try SkillParser.parse(id: "code", content: BuiltInSkills.code, isBuiltIn: true)
        let exported = try SkillMarkdownFormatter.formatForExport(skill: skill, source: BuiltInSkills.code)

        XCTAssertTrue(exported.contains("## Actions"))
        XCTAssertTrue(exported.contains("### pretty-json"))
        XCTAssertTrue(exported.contains("function: shellCommand"))
        XCTAssertFalse(exported.contains("```json"))
    }

    func testTransformBuiltInUsesConciseSummarizePrompt() throws {
        let skill = try SkillParser.parse(id: "transform", content: BuiltInSkills.transform, isBuiltIn: true)
        let summarizeTool = try XCTUnwrap(skill.tools.first { $0.id == "summarize" })

        XCTAssertEqual(
            summarizeTool.parameters.properties["systemPrompt"]?.value,
            "Summarize the clipboard text into a short, clear summary. Preserve the main point and the most important supporting details. Omit repetition, filler, and minor examples. Use a neutral professional tone. Default to 3-5 bullet points. If the source is very short, return a single sentence. Do not add headings, commentary, or information not present in the source."
        )
    }

    func testTransformBuiltInUsesEnglishOnlyTranslatePrompt() throws {
        let skill = try SkillParser.parse(id: "transform", content: BuiltInSkills.transform, isBuiltIn: true)
        let translateTool = try XCTUnwrap(skill.tools.first { $0.id == "translate" })

        XCTAssertEqual(
            translateTool.parameters.properties["systemPrompt"]?.value,
            "Translate the clipboard text to English. Return only the translation with no explanation."
        )
    }

    func testTransformBuiltInUsesEmailRewritePrompt() throws {
        let skill = try SkillParser.parse(id: "transform", content: BuiltInSkills.transform, isBuiltIn: true)
        let rewriteTool = try XCTUnwrap(skill.tools.first { $0.id == "rewrite-email-draft" })

        XCTAssertEqual(rewriteTool.parsedEntityTypes, [.emailDraft])
        XCTAssertEqual(
            rewriteTool.parameters.properties["systemPrompt"]?.value,
            "Rewrite the clipboard text as a polished email reply draft. Preserve the original intent, key facts, commitments, and requested actions. Improve clarity, grammar, tone, and structure. Keep it concise and natural. Return only the rewritten email body with no commentary, subject line, or markdown."
        )
    }

    func testTransformBuiltInUsesSlackRewritePrompt() throws {
        let skill = try SkillParser.parse(id: "transform", content: BuiltInSkills.transform, isBuiltIn: true)
        let rewriteTool = try XCTUnwrap(skill.tools.first { $0.id == "rewrite-slack-message" })

        XCTAssertEqual(rewriteTool.parsedEntityTypes, [.slackDraft])
        XCTAssertEqual(
            rewriteTool.parameters.properties["systemPrompt"]?.value,
            "Rewrite the clipboard text as a polished Slack message. Preserve the original intent, key facts, commitments, and requested actions. Improve clarity, tone, and structure while keeping it concise, natural, and conversational. Return only the rewritten message with no commentary or markdown."
        )
    }

    func testCodeBuiltInIncludesTempFileToolForCodeLikeContent() throws {
        let skill = try SkillParser.parse(id: "code", content: BuiltInSkills.code, isBuiltIn: true)
        let tempFileTool = try XCTUnwrap(skill.tools.first { $0.id == "open-temp-code" })

        XCTAssertEqual(
            tempFileTool.parsedEntityTypes,
            [.markdown, .codeSnippet, .shellCommand, .logOutput, .sql]
        )
    }

    func testTextBuiltInHTMLToMarkdownRequiresHTMLEntity() throws {
        let skill = try SkillParser.parse(id: "text", content: BuiltInSkills.text, isBuiltIn: true)
        let htmlTool = try XCTUnwrap(skill.tools.first { $0.id == "html-to-markdown" })

        XCTAssertEqual(htmlTool.parsedEntityTypes, [.html])
    }

    func testLocalLLMDetectedEntityParsing() {
        let response = """
        ```json
        ["emailDraft", "slackDraft", "emailDraft", "unknown"]
        ```
        """

        XCTAssertEqual(
            LocalLLMService.parseDetectedEntities(from: response),
            [.emailDraft, .slackDraft]
        )
    }
}
