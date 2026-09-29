/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// The Markdown layer's SPI `.inlineOnly` / `.preserveWhitespace` options reach the CommonMark parser's
/// inline-only modes, so block markers stay literal and the whole input becomes one paragraph.
class InlineOnlyParseOptionTests: XCTestCase {
    private func surface(_ markdown: String, options: ParseOptions) -> String {
        Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testInlineOnlySuppressesBlockStructure() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"# heading\n\n* item\"", surface("# heading\n\n* item", options: .inlineOnly))
    }

    func testPreserveWhitespaceSuppressesBlockStructure() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"# heading\n\n* item\"", surface("# heading\n\n* item", options: .preserveWhitespace))
    }

    func testPreserveWhitespaceImpliesInlineOnly() {
        XCTAssertTrue(ParseOptions.preserveWhitespace.contains(.inlineOnly))
    }

    /// cmark opens the paragraph for any input line, even a blank or BOM-only one, and keeps it empty; only input with no bytes at all has no line and so no paragraph. Both flag states follow cmark, since inline-only mode has no spec and its shipped clients relied on cmark.
    func testEmptyAndBlankInputs() {
        for mode: ParseOptions in [.inlineOnly, .preserveWhitespace] {
            for options in [mode, mode.union(.cmarkBugCompatibility)] {
                XCTAssertEqual("Document", surface("", options: options))
                XCTAssertEqual("Document\n└─ Paragraph", surface("\u{FEFF}", options: options))
                XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"\n\"", surface("\u{FEFF}\n", options: options))
                XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"  \"", surface("\u{FEFF}  ", options: options))
                XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"\n\"", surface("\n", options: options))
            }
        }
    }

    func testDefaultStillParsesBlocks() {
        XCTAssertEqual("Document\n├─ Heading level: 1\n│  └─ Text \"heading\"\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"item\"", surface("# heading\n\n* item", options: []))
    }
}
