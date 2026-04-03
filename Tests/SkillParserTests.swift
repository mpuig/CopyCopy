import XCTest
@testable import CopyCopy

final class SkillParserTests: XCTestCase {

    // MARK: - Body-Based Format: Tool Calls

    func testParseToolCallBody() throws {
        let content = """
        ---
        name: Pretty Print JSON
        description: Format and indent JSON
        icon: curlybraces
        content-types: text
        entity-types: json
        ---

        formatJSON({clipboard})
        """

        let skill = try SkillParser.parse(id: "pretty-json", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .formatJSON)
        XCTAssertEqual(skill.parameters.properties["json"]?.source, "clipboard")
        XCTAssertEqual(skill.contentTypes, [.text])
        XCTAssertEqual(skill.entityTypes, [.json])
        XCTAssertEqual(skill.description, "Format and indent JSON")
    }

    func testParseNoArgToolCall() throws {
        let content = """
        ---
        name: Save Image
        description: Save clipboard image to file
        icon: square.and.arrow.down
        content-types: image
        ---

        saveImage()
        """

        let skill = try SkillParser.parse(id: "save-image", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .saveImage)
        XCTAssertEqual(skill.parameters.properties.count, 0)
    }

    func testParseURLTemplateToolCall() throws {
        let content = """
        ---
        name: Search the Web
        description: Search DuckDuckGo
        icon: magnifyingglass
        content-types: text
        ---

        openURL(https://duckduckgo.com/?q={clipboard})
        """

        let skill = try SkillParser.parse(id: "search-web", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .openURLTemplate)
        XCTAssertEqual(skill.parameters.properties["baseURL"]?.value, "https://duckduckgo.com/")
        XCTAssertEqual(skill.parameters.properties["q"]?.source, "clipboard")
    }

    func testParseSimpleOpenURLToolCall() throws {
        let content = """
        ---
        name: Open URL
        description: Open in default browser
        icon: link
        content-types: url
        ---

        openURL({clipboardURL})
        """

        let skill = try SkillParser.parse(id: "open-url", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .openURL)
        XCTAssertEqual(skill.parameters.properties["url"]?.source, "clipboardURL")
    }

    func testParseCopyToClipboardToolCall() throws {
        let content = """
        ---
        name: UPPERCASE
        description: Convert to UPPERCASE
        icon: textformat.size.larger
        content-types: text
        ---

        copyToClipboard({clipboardUppercase})
        """

        let skill = try SkillParser.parse(id: "uppercase", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .copyToClipboard)
        XCTAssertEqual(skill.parameters.properties["text"]?.source, "clipboardUppercase")
    }

    // MARK: - Body-Based Format: LLM Prompts

    func testParseLLMPromptBody() throws {
        let content = """
        ---
        name: Explain Code
        description: Explain what this code does
        icon: text.bubble
        content-types: text
        entity-types: codeSnippet, shellCommand
        text-source: clipboardLLM
        source-boosts:
          ide: 130
        ---

        Explain this code. Key logic, inputs/outputs, risks. Bullet points.
        """

        let skill = try SkillParser.parse(id: "explain-code", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.parameters.properties["systemPrompt"]?.value, "Explain this code. Key logic, inputs/outputs, risks. Bullet points.")
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardLLM")
        XCTAssertEqual(skill.entityTypes, [.codeSnippet, .shellCommand])
        XCTAssertEqual(skill.sourceBoosts?["ide"], 130)
    }

    func testParseLLMPromptDefaultTextSource() throws {
        let content = """
        ---
        name: Fix Grammar
        description: Fix grammar and spelling
        icon: checkmark.bubble
        content-types: text
        ---

        Fix grammar and spelling. Return only the corrected text.
        """

        let skill = try SkillParser.parse(id: "fix-grammar", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboard")
    }

    // MARK: - Backward Compat: Explicit execute in frontmatter

    func testParseFlatFormatWithExecuteKey() throws {
        let content = """
        ---
        name: Pretty Print JSON
        description: Format JSON
        icon: curlybraces
        execute: formatJSON
        content-types: text
        entity-types: json
        parameters:
          json:
            source: clipboard
        ---

        Pretty Print JSON
        """

        let skill = try SkillParser.parse(id: "pretty-json", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .formatJSON)
        XCTAssertEqual(skill.parameters.properties["json"]?.source, "clipboard")
    }

    func testParseSummarizeWithExplicitExecute() throws {
        let skill = try SkillParser.parse(id: "summarize", content: BuiltInSkills.summarize, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .summarize)
        XCTAssertEqual(skill.parameters.properties["text"]?.source, "clipboardChatCleaned")
    }

    // MARK: - Backward Compat: Old JSON Format

    func testParseJSONToolsBlockExplodesIntoMultipleSkills() throws {
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

        let skills = try SkillParser.parseAll(id: "test", content: content, isBuiltIn: true)

        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].executeFunction, .formatJSON)
    }

    // MARK: - Backward Compat: Legacy Format

    func testParseLegacyActionFallback() throws {
        let content = """
        ---
        name: legacy
        description: Legacy skill
        metadata:
          content_types: [text]
        ---

        # Legacy

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

        let skills = try SkillParser.parseAll(id: "legacy", content: content, isBuiltIn: false)
        XCTAssertEqual(skills.count, 2)
    }

    // MARK: - Built-in Skills

    func testAllBuiltInSkillsParse() throws {
        for (id, content) in BuiltInSkills.all {
            let skills = try SkillParser.parseAll(id: id, content: content, isBuiltIn: true)
            XCTAssertFalse(skills.isEmpty, "Skill '\(id)' produced no actions")
            for skill in skills {
                XCTAssertNotNil(skill.executeFunction, "Skill '\(skill.id)' has invalid execute function '\(skill.execute)'")
                XCTAssertFalse(skill.description.isEmpty, "Skill '\(skill.id)' has empty description")
            }
        }
    }

    func testBuiltInExplainCodeSkill() throws {
        let skill = try SkillParser.parse(id: "explain-code", content: BuiltInSkills.explainCode, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardLLM")
        XCTAssertEqual(skill.description, "Explain what this code does")
    }

    func testBuiltInSearchWebSkill() throws {
        let skill = try SkillParser.parse(id: "search-web", content: BuiltInSkills.searchWeb, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .openURLTemplate)
        XCTAssertEqual(skill.parameters.properties["baseURL"]?.value, "https://duckduckgo.com/")
    }

    func testBuiltInCleanTextSkill() throws {
        let skill = try SkillParser.parse(id: "clean-text", content: BuiltInSkills.cleanText, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .copyToClipboard)
        XCTAssertEqual(skill.parameters.properties["text"]?.source, "clipboardClean")
    }

    func testBuiltInHTMLToMarkdownSkill() throws {
        let skill = try SkillParser.parse(id: "html-to-markdown", content: BuiltInSkills.htmlToMarkdown, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .htmlToMarkdown)
        XCTAssertEqual(skill.entityTypes, [.html])
    }

    func testBuiltInDraftChatReplySkill() throws {
        let skill = try SkillParser.parse(id: "draft-chat-reply", content: BuiltInSkills.draftChatReply, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.sourceContexts, [.chat])
    }

    func testBuiltInFixGrammarSkill() throws {
        let skill = try SkillParser.parse(id: "fix-grammar", content: BuiltInSkills.fixGrammar, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.sourceBoosts?["notes"], 80)
    }

    func testBuiltInExtractDataSkill() throws {
        let skill = try SkillParser.parse(id: "extract-data", content: BuiltInSkills.extractData, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertTrue(skill.tools.isEmpty)
    }

    // MARK: - Agent Skills (LLM with tools)

    func testParseAgentSkillWithTools() throws {
        let content = """
        ---
        name: Smart Helper
        description: Analyze text and pick the best action
        icon: wand.and.stars
        content-types: text
        text-source: clipboardLLM
        tools: formatJSON, decodeBase64, copyToClipboard
        ---

        Analyze the text and pick the best action.
        """

        let skill = try SkillParser.parse(id: "smart", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmAgent)
        XCTAssertEqual(skill.tools, ["formatJSON", "decodeBase64", "copyToClipboard"])
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardLLM")
    }

    func testParseSkillWithoutToolsIsLLMPrompt() throws {
        let content = """
        ---
        name: Explain
        description: Explain this code
        icon: text.bubble
        content-types: text
        ---

        Explain this code.
        """

        let skill = try SkillParser.parse(id: "explain", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertTrue(skill.tools.isEmpty)
    }

    // MARK: - Round-trip

    func testRoundTripFunctionSkill() throws {
        let skill = try SkillParser.parse(id: "clean-text", content: BuiltInSkills.cleanText, isBuiltIn: true)
        let exported = SkillMarkdownFormatter.formatFlat(skill: skill)
        let reparsed = try SkillParser.parse(id: "clean-text", content: exported, isBuiltIn: false)

        XCTAssertEqual(reparsed.executeFunction, .copyToClipboard)
        XCTAssertEqual(reparsed.parameters.properties["text"]?.source, "clipboardClean")
        XCTAssertEqual(reparsed.description, skill.description)
    }

    func testRoundTripLLMSkill() throws {
        let skill = try SkillParser.parse(id: "explain-code", content: BuiltInSkills.explainCode, isBuiltIn: true)
        let exported = SkillMarkdownFormatter.formatFlat(skill: skill)
        let reparsed = try SkillParser.parse(id: "explain-code", content: exported, isBuiltIn: false)

        XCTAssertEqual(reparsed.executeFunction, .llmPrompt)
        XCTAssertEqual(reparsed.parameters.properties["prompt"]?.source, "clipboardLLM")
        XCTAssertEqual(reparsed.description, skill.description)
    }

    func testRoundTripURLTemplateSkill() throws {
        let skill = try SkillParser.parse(id: "search-web", content: BuiltInSkills.searchWeb, isBuiltIn: true)
        let exported = SkillMarkdownFormatter.formatFlat(skill: skill)
        let reparsed = try SkillParser.parse(id: "search-web", content: exported, isBuiltIn: false)

        XCTAssertEqual(reparsed.executeFunction, .openURLTemplate)
        XCTAssertEqual(reparsed.parameters.properties["baseURL"]?.value, "https://duckduckgo.com/")
    }

    func testRoundTripAgentSkill() throws {
        let content = """
        ---
        name: Smart Helper
        description: Analyze and act
        icon: wand.and.stars
        content-types: text
        text-source: clipboardLLM
        tools: formatJSON, copyToClipboard
        ---

        Analyze the text and pick the best action.
        """

        let skill = try SkillParser.parse(id: "smart", content: content, isBuiltIn: true)
        let exported = SkillMarkdownFormatter.formatFlat(skill: skill)
        let reparsed = try SkillParser.parse(id: "smart", content: exported, isBuiltIn: false)

        XCTAssertEqual(reparsed.executeFunction, .llmAgent)
        XCTAssertEqual(reparsed.tools, skill.tools)
    }

    // MARK: - LLM Entity Parsing

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
