/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// An attribute definition's value is cleaned like a link destination (cmark's `cmark_clean_attributes`):
/// trimmed even when more paragraph content follows it, with escapes and entities decoded. Flag-ON surfaces
/// are the cmark-gfm reference's; inputs are `[markdown …][option byte]`, split as the fuzzer does.
class AttributeDefinitionTrailingWhitespaceTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool = true) -> String {
        var (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testListItemThenNULLine() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72], cmarkBugCompatible: false))
    }

    func testListItemThenText() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"x\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 10, 120, 72]))
    }

    func testTopLevelAfterBlankThenNULLine() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ Paragraph\n   └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 10, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ Paragraph\n   └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 10, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72], cmarkBugCompatible: false))
    }

    func testTrailingTab() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 9, 10, 0, 72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 9, 10, 0, 72], cmarkBugCompatible: false))
    }

    func testBlockQuote() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 62, 32, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 62, 32, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72], cmarkBugCompatible: false))
    }

    func testTwoTrailingSpaces() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 32, 10, 0, 72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 32, 10, 0, 72], cmarkBugCompatible: false))
    }

    func testFuzzedArtifact() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"\u{fffd}\"", surface([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 10, 0, 72], cmarkBugCompatible: false))
    }

    func testInteriorSpacesKept() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `a b`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:a b \nx".utf8) + [72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `a b`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:a b \nx".utf8) + [72], cmarkBugCompatible: false))
    }

    func testFollowedByAnotherDefinition() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  ├─ InlineAttributes attributes: `l`\n│  └─ InlineAttributes attributes: `m`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]^[][y]\n\n^[$]:l \n^[y]:m \nx".utf8) + [72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  ├─ InlineAttributes attributes: `l`\n│  └─ InlineAttributes attributes: `m`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]^[][y]\n\n^[$]:l \n^[y]:m \nx".utf8) + [72], cmarkBugCompatible: false))
    }

    func testCRLF() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:l \r\nx".utf8) + [72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:l \r\nx".utf8) + [72], cmarkBugCompatible: false))
    }

    /// A whitespace-only value line can't form an empty value: the separator skip crosses one line end, so
    /// the value is the next line's content.
    func testWhitespaceOnlyValueLineTakesNextLine() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `x`\n└─ Paragraph\n   └─ Text \"z\"", surface(Array("^[][$]\n\n^[$]: \t \nx \nz".utf8) + [72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `x`\n└─ Paragraph\n   └─ Text \"z\"", surface(Array("^[][$]\n\n^[$]: \t \nx \nz".utf8) + [72], cmarkBugCompatible: false))
    }

    func testLeadingSpaceAfterColon() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]: l \nx".utf8) + [72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]: l \nx".utf8) + [72], cmarkBugCompatible: false))
    }

    func testEscapesAndEntitiesDecoded() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `a*&b`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:a\\*&amp;b\nx".utf8) + [72]))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `a*&b`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:a\\*&amp;b\nx".utf8) + [72], cmarkBugCompatible: false))
    }

    /// cmark decodes entities before backslash escapes, so `\&amp;` becomes `&`.
    func testEntityDecodedBeforeEscape() {
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `&`\n└─ Paragraph\n   └─ Text \"x\"", surface(Array("^[][$]\n\n^[$]:\\&amp; \nx".utf8) + [72]))
    }

    /// Flag-OFF shares the link destination's spec-correct single pass: `\&` escapes the `&`, so `amp;` stays literal.
    func testEscapeBeforeEntityWithoutBugCompatibility() {
        let (markdown, options) = FuzzRegressionTests.splitInput(Array("^[][$]\n\n^[$]:\\&amp; \nx".utf8) + [72])!
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `&amp;`\n└─ Paragraph\n   └─ Text \"x\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }

    /// The trim is not a cmark quirk, so the flag-OFF deliverable trims too.
    func testTrimmedWithoutBugCompatibility() {
        let (markdown, options) = FuzzRegressionTests.splitInput([94, 91, 93, 91, 36, 93, 10, 45, 32, 94, 91, 36, 93, 58, 108, 32, 10, 120, 72])!
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ InlineAttributes attributes: `l`\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"x\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }

    /// Control: a definition that isn't at the start of a paragraph is never formed, so its line stays literal.
    func testLastLineControl() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"^[]\"\n   ├─ SoftBreak\n   └─ Text \"^[$]:l\"", surface([94, 91, 93, 91, 36, 93, 10, 94, 91, 36, 93, 58, 108, 32, 10, 72]))
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"^[][$]\"\n   ├─ SoftBreak\n   └─ Text \"^[$]:l\"", surface([94, 91, 93, 91, 36, 93, 10, 94, 91, 36, 93, 58, 108, 32, 10, 72], cmarkBugCompatible: false))
    }

}
