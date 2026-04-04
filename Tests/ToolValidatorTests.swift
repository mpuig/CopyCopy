import XCTest
@testable import CopyCopy

final class ToolValidatorTests: XCTestCase {

    // MARK: - Execute Function Validation

    func testValidExecuteFunction() throws {
        let result = try ToolValidator.validateExecuteFunction("formatJSON")
        XCTAssertEqual(result, .formatJSON)
    }

    func testInvalidExecuteFunction() {
        XCTAssertThrowsError(try ToolValidator.validateExecuteFunction("deleteEverything"))
    }

    // MARK: - URL Validation

    func testValidHTTPURL() throws {
        let url = try ToolValidator.validateOpenableURL("https://example.com")
        XCTAssertEqual(url.absoluteString, "https://example.com")
    }

    func testValidMapsURL() throws {
        let url = try ToolValidator.validateOpenableURL("maps://?q=Paris")
        XCTAssertEqual(url.scheme, "maps")
    }

    func testDisallowedScheme() {
        XCTAssertThrowsError(try ToolValidator.validateOpenableURL("file:///etc/passwd"))
    }

    func testJavascriptSchemeBlocked() {
        XCTAssertThrowsError(try ToolValidator.validateOpenableURL("javascript:alert(1)"))
    }

    func testInvalidURL() {
        XCTAssertThrowsError(try ToolValidator.validateOpenableURL(""))
    }

    // MARK: - Hostname Validation

    func testValidHostname() throws {
        let host = try ToolValidator.validateHostname("example.com")
        XCTAssertEqual(host, "example.com")
    }

    func testValidIPv4() throws {
        let host = try ToolValidator.validateHostname("192.168.1.1")
        XCTAssertEqual(host, "192.168.1.1")
    }

    func testLocalhost() throws {
        let host = try ToolValidator.validateHostname("localhost")
        XCTAssertEqual(host, "localhost")
    }

    func testInvalidHostname() {
        XCTAssertThrowsError(try ToolValidator.validateHostname(""))
        XCTAssertThrowsError(try ToolValidator.validateHostname("single"))
        XCTAssertThrowsError(try ToolValidator.validateHostname("-bad.com"))
    }

    func testHostnameTrimsWhitespace() throws {
        let host = try ToolValidator.validateHostname("  example.com  ")
        XCTAssertEqual(host, "example.com")
    }

    // MARK: - JSON Validation

    func testValidJSON() throws {
        try ToolValidator.validateJSON("{\"key\": \"value\"}")
    }

    func testInvalidJSON() {
        XCTAssertThrowsError(try ToolValidator.validateJSON("not json"))
    }

    // MARK: - App Allowlist

    func testAllowlistedApp() throws {
        let bundle = try ToolValidator.allowlistedBundleIdentifier(for: "Claude")
        XCTAssertEqual(bundle, "com.anthropic.claudefordesktop")
    }

    func testAllowlistCaseInsensitive() throws {
        let bundle = try ToolValidator.allowlistedBundleIdentifier(for: "CHATGPT")
        XCTAssertEqual(bundle, "com.openai.chat")
    }

    func testDisallowedApp() {
        XCTAssertThrowsError(try ToolValidator.allowlistedBundleIdentifier(for: "Terminal"))
    }

    // MARK: - Parameters Validation

    func testValidParameters() throws {
        let params = ToolParameters(
            type: "object",
            properties: ["text": ToolProperty(type: "string", description: "t", source: "clipboard", value: nil, prefix: nil, suffix: nil)],
            required: ["text"]
        )
        try ToolValidator.validateJSONObjectParameters(params)
    }

    func testMissingRequiredProperty() {
        let params = ToolParameters(type: "object", properties: [:], required: ["text"])
        XCTAssertThrowsError(try ToolValidator.validateJSONObjectParameters(params))
    }

    func testWrongParameterType() {
        let params = ToolParameters(type: "array", properties: [:], required: [])
        XCTAssertThrowsError(try ToolValidator.validateJSONObjectParameters(params))
    }
}
