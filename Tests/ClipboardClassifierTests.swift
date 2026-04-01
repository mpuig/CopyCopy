import Cocoa
import XCTest
@testable import CopyCopy

final class ClipboardClassifierTests: XCTestCase {
    var classifier: ClipboardClassifier!

    override func setUp() {
        super.setUp()
        classifier = ClipboardClassifier()
    }

    func testDetectURL() {
        let url = "https://www.example.com/path"
        let detected = classifier.detectURL(from: url)
        XCTAssertEqual(detected?.absoluteString, url)
    }

    func testDetectEmailEntity() {
        let email = "test@example.com"
        XCTAssertNil(classifier.detectURL(from: email), "Email should not be classified as a web URL")
        XCTAssertEqual(classifier.detectEntity(from: email), .email)
    }

    func testDetectHexColorEntity() {
        let colors = ["#123", "#123456", "#12345678"]
        for color in colors {
            XCTAssertEqual(classifier.detectEntity(from: color), .hexColor, "Failed for color: \(color)")
        }
    }

    func testDetectRGBColorEntity() {
        let colors = ["rgb(255, 0, 0)", "rgba(255, 0, 0, 0.5)"]
        for color in colors {
            XCTAssertEqual(classifier.detectEntity(from: color), .hexColor, "Failed for color: \(color)")
        }
    }

    func testDetectUUIDEntity() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        XCTAssertEqual(classifier.detectEntity(from: uuid), .uuid)
    }

    func testDetectIPAddressEntity() {
        let ips = ["192.168.1.1", "10.0.0.1"]
        for ip in ips {
            XCTAssertEqual(classifier.detectEntity(from: ip), .ipAddress, "Failed for IP: \(ip)")
        }
    }

    func testDetectGitSHAEntity() {
        let shas = [
            "a1b2c3d",
            "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
        ]
        for sha in shas {
            XCTAssertEqual(classifier.detectEntity(from: sha), .gitSha, "Failed for SHA: \(sha)")
        }
    }

    func testDetectCoordinatesEntity() {
        let coords = ["37.7749,-122.4194", "-33.8688,151.2093"]
        for coord in coords {
            XCTAssertEqual(classifier.detectEntity(from: coord), .coordinates, "Failed for coord: \(coord)")
        }
    }

    func testDetectHashtagEntity() {
        let hashtags = ["#swift", "#OpenAI2024"]
        for tag in hashtags {
            XCTAssertEqual(classifier.detectEntity(from: tag), .hashtag, "Failed for hashtag: \(tag)")
        }
    }

    func testDetectMentionEntity() {
        let mentions = ["@user", "@swiftlang"]
        for mention in mentions {
            XCTAssertEqual(classifier.detectEntity(from: mention), .mention, "Failed for mention: \(mention)")
        }
    }

    func testDetectCurrencyEntity() {
        let currencies = ["$100", "€50.99", "£30", "¥1000"]
        for currency in currencies {
            XCTAssertEqual(classifier.detectEntity(from: currency), .currency, "Failed for currency: \(currency)")
        }
    }

    func testDetectFilePathEntity() {
        let paths = ["/Users/test/file.txt", "~/Documents"]
        for path in paths {
            XCTAssertEqual(classifier.detectEntity(from: path), .filePath, "Failed for path: \(path)")
        }
    }

    func testDetectTrackingNumberEntity() {
        let tracking = "1Z1234567890123456"
        XCTAssertEqual(classifier.detectEntity(from: tracking), .trackingNumber)
    }

    func testDetectJSONEntity() {
        let jsonValues = ["{\"key\":\"value\"}", "[1, 2, 3]"]
        for json in jsonValues {
            XCTAssertEqual(classifier.detectEntity(from: json), .json, "Failed for JSON: \(json)")
        }
    }

    func testDetectBase64Entity() {
        let base64 = "VGhpcyBpcyBhIHRlc3Qgc3RyaW5n"
        XCTAssertEqual(classifier.detectEntity(from: base64), .base64)
    }

    func testDetectMarkdownEntity() {
        let markdown = "# Title\n\nThis is **bold** text."
        XCTAssertEqual(classifier.detectEntity(from: markdown), .markdown)
    }

    func testDetectHTMLEntity() {
        let html = "<div><p>Hello <strong>world</strong></p></div>"
        XCTAssertEqual(classifier.detectEntity(from: html), .html)
    }

    func testDetectCodeSnippetEntity() {
        let codeSnippets = ["func test() {}", "const x = 1;", "import Foundation"]
        for code in codeSnippets {
            XCTAssertEqual(classifier.detectEntity(from: code), .codeSnippet, "Failed for code: \(code)")
        }
    }

    func testDetectNoneEntity() {
        let plainText = "Just some plain text"
        XCTAssertEqual(classifier.detectEntity(from: plainText), .none)
    }
}
