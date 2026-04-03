import XCTest
@testable import CopyCopy

final class SkillParserTests: XCTestCase {

    // MARK: - New Flat Format

    func testParseFlatFormat() throws {
        let content = """
        ---
        name: Pretty Print JSON
        icon: curlybraces
        execute: formatJSON
        content-types: text
        entity-types: json
        source-boosts:
          ide: 120
          other: 25
        parameters:
          json:
            source: clipboard
            description: Clipboard JSON
        ---

        Pretty Print JSON
        """

        let skill = try SkillParser.parse(id: "pretty-json", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.id, "pretty-json")
        XCTAssertEqual(skill.name, "Pretty Print JSON")
        XCTAssertEqual(skill.icon, "curlybraces")
        XCTAssertEqual(skill.executeFunction, .formatJSON)
        XCTAssertEqual(skill.contentTypes, [.text])
        XCTAssertEqual(skill.entityTypes, [.json])
        XCTAssertEqual(skill.parameters.properties["json"]?.source, "clipboard")
        XCTAssertEqual(skill.sourceBoosts?["ide"], 120)
        XCTAssertEqual(skill.sourceBoosts?["other"], 25)
    }

    func testParseFlatFormatWithMinChars() throws {
        let content = """
        ---
        name: Summarize Content
        icon: text.redaction
        execute: summarize
        content-types: text
        minimum-chars: 300
        parameters:
          text:
            source: clipboardChatCleaned
        ---

        Summarize Content
        """

        let skill = try SkillParser.parse(id: "summarize", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .summarize)
        XCTAssertEqual(skill.minimumCharacterCount, 300)
        XCTAssertEqual(skill.parameters.properties["text"]?.source, "clipboardChatCleaned")
    }

    func testParseFlatFormatWithLLMPrompt() throws {
        let content = """
        ---
        name: Explain Code
        icon: text.bubble
        execute: llmPrompt
        content-types: text
        entity-types: codeSnippet, shellCommand
        source-boosts:
          ide: 130
        parameters:
          prompt:
            source: clipboardLLM
            description: Clipboard code
          systemPrompt:
            source: literal
            value: Explain the code.
            description: Code explanation instruction
        ---

        Explain what this code does
        """

        let skill = try SkillParser.parse(id: "explain-code", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.entityTypes, [.codeSnippet, .shellCommand])
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardLLM")
        XCTAssertEqual(skill.parameters.properties["systemPrompt"]?.value, "Explain the code.")
        XCTAssertEqual(skill.sourceBoosts?["ide"], 130)
    }

    func testParseFlatFormatWithSourceContexts() throws {
        let content = """
        ---
        name: Strip ANSI
        icon: textformat
        execute: stripANSI
        content-types: text
        entity-types: logOutput, shellCommand
        source-contexts: terminal
        source-boosts:
          terminal: 130
        parameters:
          text:
            source: clipboard
        ---

        Strip ANSI escape codes
        """

        let skill = try SkillParser.parse(id: "strip-ansi", content: content, isBuiltIn: true)

        XCTAssertEqual(skill.sourceContexts, [.terminal])
        XCTAssertEqual(skill.entityTypes, [.logOutput, .shellCommand])
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
        XCTAssertEqual(skills[0].id, "pretty-json")
        XCTAssertEqual(skills[0].contentTypes, [.text])
        XCTAssertEqual(skills[0].executeFunction, .formatJSON)
        XCTAssertEqual(skills[0].parameters.properties["json"]?.source, "clipboard")
        XCTAssertEqual(skills[0].entityTypes, [.json])
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

        let skills = try SkillParser.parseAll(id: "legacy", content: content, isBuiltIn: false)

        XCTAssertEqual(skills.count, 2)

        let searchSkill = try XCTUnwrap(skills.first { $0.id == "search-web" })
        XCTAssertEqual(searchSkill.executeFunction, .openURLTemplate)
        XCTAssertEqual(searchSkill.parameters.properties["baseURL"]?.value, "https://duckduckgo.com/")
        XCTAssertEqual(searchSkill.parameters.properties["q"]?.source, "clipboard")
        XCTAssertEqual(searchSkill.contentTypes, [.text])

        let summarizeSkill = try XCTUnwrap(skills.first { $0.id == "summarize" })
        XCTAssertEqual(summarizeSkill.executeFunction, .llmPrompt)
        XCTAssertEqual(summarizeSkill.parameters.properties["systemPrompt"]?.value, "Summarize the clipboard text.")
        XCTAssertEqual(summarizeSkill.parameters.properties["prompt"]?.source, "clipboardChatCleaned")
    }

    func testLegacyActionParsesSourceBoostsAndMinimumCharacters() throws {
        let content = """
        ---
        name: legacy
        description: Legacy skill
        metadata:
          content_types: [text]
        ---

        # Legacy

        ## Actions

        ### extract-action-items
        type: prompt
        prompt: Extract action items.
        icon: checklist
        description: Extract Action Items
        source_boosts: "chat:110,email:90"
        minimum_characters: 500
        """

        let skills = try SkillParser.parseAll(id: "legacy", content: content, isBuiltIn: false)
        let skill = try XCTUnwrap(skills.first)

        XCTAssertEqual(skill.sourceBoosts?["chat"], 110)
        XCTAssertEqual(skill.minimumCharacterCount, 500)
    }

    // MARK: - Built-in Skills

    func testBuiltInSummarizeSkill() throws {
        let skill = try SkillParser.parse(id: "summarize", content: BuiltInSkills.summarize, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .summarize)
        XCTAssertEqual(skill.parameters.properties["text"]?.source, "clipboardChatCleaned")
        XCTAssertEqual(skill.minimumCharacterCount, 300)
        XCTAssertEqual(skill.sourceBoosts?["chat"], 110)
    }

    func testBuiltInTranslateSkill() throws {
        let skill = try SkillParser.parse(id: "translate", content: BuiltInSkills.translate, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(
            skill.parameters.properties["systemPrompt"]?.value,
            "Translate the clipboard text to English. Return only the translation with no explanation."
        )
    }

    func testBuiltInFixGrammarSkill() throws {
        let skill = try SkillParser.parse(id: "fix-grammar", content: BuiltInSkills.fixGrammar, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardChatCleaned")
        XCTAssertEqual(skill.sourceBoosts?["notes"], 80)
    }

    func testBuiltInMakeConciseAndExtractActionItems() throws {
        let concise = try SkillParser.parse(id: "make-concise", content: BuiltInSkills.makeConcise, isBuiltIn: true)
        let actions = try SkillParser.parse(id: "extract-action-items", content: BuiltInSkills.extractActionItems, isBuiltIn: true)

        XCTAssertEqual(concise.sourceBoosts?["chat"], 85)
        XCTAssertEqual(actions.minimumCharacterCount, 500)
        XCTAssertEqual(actions.sourceBoosts?["email"], 90)
    }

    func testBuiltInDraftChatReplySkill() throws {
        let skill = try SkillParser.parse(id: "draft-chat-reply", content: BuiltInSkills.draftChatReply, isBuiltIn: true)

        XCTAssertEqual(skill.sourceContexts, [.chat])
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardChatCleaned")
        XCTAssertEqual(skill.sourceBoosts?["chat"], 150)
    }

    func testBuiltInEmailRewriteSkill() throws {
        let skill = try SkillParser.parse(id: "rewrite-email-draft", content: BuiltInSkills.rewriteEmailDraft, isBuiltIn: true)

        XCTAssertEqual(skill.entityTypes, [.emailDraft])
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardLLM")
    }

    func testBuiltInSlackRewriteSkill() throws {
        let skill = try SkillParser.parse(id: "rewrite-slack-message", content: BuiltInSkills.rewriteSlackMessage, isBuiltIn: true)

        XCTAssertEqual(skill.entityTypes, [.slackDraft])
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardChatCleaned")
    }

    func testBuiltInExplainCodeSkill() throws {
        let skill = try SkillParser.parse(id: "explain-code", content: BuiltInSkills.explainCode, isBuiltIn: true)

        XCTAssertEqual(skill.executeFunction, .llmPrompt)
        XCTAssertEqual(skill.parameters.properties["prompt"]?.source, "clipboardLLM")
        XCTAssertEqual(skill.entityTypes, [.codeSnippet, .shellCommand, .sql, .logOutput])
        XCTAssertNil(skill.sourceBoosts?["chat"])
    }

    func testBuiltInHTMLToMarkdownSkill() throws {
        let skill = try SkillParser.parse(id: "html-to-markdown", content: BuiltInSkills.htmlToMarkdown, isBuiltIn: true)

        XCTAssertEqual(skill.entityTypes, [.html])
        XCTAssertEqual(skill.parameters.properties["html"]?.source, "clipboardHTML")
    }

    func testBuiltInOpenTempCodeSkill() throws {
        let skill = try SkillParser.parse(id: "open-temp-code", content: BuiltInSkills.openTempCode, isBuiltIn: true)

        XCTAssertEqual(
            skill.entityTypes,
            [.markdown, .codeSnippet, .shellCommand, .logOutput, .sql]
        )
    }

    func testBuiltInStripANSISkill() throws {
        let skill = try SkillParser.parse(id: "strip-ansi", content: BuiltInSkills.stripANSI, isBuiltIn: true)

        XCTAssertEqual(skill.sourceContexts, [.terminal])
        XCTAssertEqual(skill.sourceBoosts?["terminal"], 130)
    }

    // MARK: - Round-trip

    func testFlatFormatRoundTrip() throws {
        let skill = try SkillParser.parse(id: "summarize", content: BuiltInSkills.summarize, isBuiltIn: true)
        let exported = SkillMarkdownFormatter.formatFlat(skill: skill)
        let reparsed = try SkillParser.parse(id: "summarize", content: exported, isBuiltIn: false)

        XCTAssertEqual(reparsed.name, skill.name)
        XCTAssertEqual(reparsed.icon, skill.icon)
        XCTAssertEqual(reparsed.execute, skill.execute)
        XCTAssertEqual(reparsed.contentTypes, skill.contentTypes)
        XCTAssertEqual(reparsed.minimumCharacterCount, skill.minimumCharacterCount)
        XCTAssertEqual(reparsed.parameters.properties["text"]?.source, "clipboardChatCleaned")
    }

    func testFlatFormatRoundTripWithLLMPrompt() throws {
        let skill = try SkillParser.parse(id: "explain-code", content: BuiltInSkills.explainCode, isBuiltIn: true)
        let exported = SkillMarkdownFormatter.formatFlat(skill: skill)
        let reparsed = try SkillParser.parse(id: "explain-code", content: exported, isBuiltIn: false)

        XCTAssertEqual(reparsed.executeFunction, .llmPrompt)
        XCTAssertEqual(reparsed.entityTypes, skill.entityTypes)
        XCTAssertEqual(reparsed.parameters.properties["systemPrompt"]?.source, "literal")
        XCTAssertEqual(reparsed.parameters.properties["prompt"]?.source, "clipboardLLM")
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
