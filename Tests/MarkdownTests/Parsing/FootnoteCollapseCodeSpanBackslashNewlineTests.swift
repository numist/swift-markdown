/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A cross-line footnote-shaped bracket whose line ending sits inside a code span after a backslash.
///
/// Ground truth is cmark-gfm (flag-ON). In `[^` + code span containing `\` LF + `]`, cmark's code span
/// swallows the line ending (the backslash is literal code content, not a hard break), and with source
/// positions on `adjust_subj_node_newlines` resets the column there, so the capture collapses to `[^]`.
/// A code span with a bare line ending (`[^` backtick LF backtick `]`) is the control. Position-free
/// compare surface.
class FootnoteCollapseCodeSpanBackslashNewlineTests: XCTestCase {
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var options = ParseOptions(rawValue: UInt(0xec & 0b11011111))
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static let collapsed = "Document\n└─ Paragraph\n   └─ Text \"[^]\""

    func testFuzzedArtifact() {
        XCTAssertEqual(Self.collapsed, surface("[^`\\\n`]"))
    }

    func testContentAroundBackslash() {
        XCTAssertEqual(Self.collapsed, surface("[^`a\\\nb`]"))
    }

    func testTextBeforeCodeSpan() {
        XCTAssertEqual(Self.collapsed, surface("[^a`\\\n`]"))
    }

    func testTrailingText() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^] x\"", surface("[^`\\\n`] x"))
    }

    func testCRLF() {
        XCTAssertEqual(Self.collapsed, surface("[^`\\\r\n`]"))
    }

    /// cmark normalizes a bare CR line ending to `\n` before inline parsing (`S_process_line`).
    func testBareCR() {
        XCTAssertEqual(Self.collapsed, surface("[^`\\\r`]"))
    }

    func testBareNewlineControl() {
        XCTAssertEqual(Self.collapsed, surface("[^`\n`]"))
    }

    func testDoubleBacktickCodeSpan() {
        XCTAssertEqual(Self.collapsed, surface("[^``\\\n``]"))
    }

    func testTrailingSpacesHardBreakShapeInCodeSpan() {
        XCTAssertEqual(Self.collapsed, surface("[^`a  \n`]"))
    }

    /// Raw HTML is the other raw-scan inline whose newline cmark resets via `adjust_subj_node_newlines`.
    func testRawHTMLAttributeValue() {
        XCTAssertEqual(Self.collapsed, surface("[^<a b=\"\\\n\">]"))
    }

    /// A matched image title's scan swallows the newline without any column reset, so the capture spans
    /// the whole bracket verbatim.
    func testImageTitleInCollapse() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"[^![x](/u \"a\\\nb\")]\"",
            surface("[^![x](/u \"a\\\nb\")]"))
    }

    /// With source positions off cmark never resets at a code span's newline, so the backslash shape
    /// keeps the raw capture verbatim, exactly as the bare-newline shape does.
    func testSourcePositionsOffKeepsRawCapture() {
        var options = ParseOptions(rawValue: UInt(0xfc & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        let surface = Document(parsing: "[^`\\\n`]", options: options).debugDescription(options: [])
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^`\\\n`]\"", surface)
    }

    /// Flag-off the bracket's label matches no footnote definition, so the bracket stays literal around the code
    /// span, raw HTML or image it holds, whereas cmark-gfm collapses it to the text captured up to its column reset.
    func testBracketStaysLiteralWithoutBugCompatibility() {
        let cases: [(markdown: String, expected: String)] = [
            ("[^`\\\n`]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `\\ `\n   └─ Text \"]\""),
            ("[^`a\\\nb`]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `a\\ b`\n   └─ Text \"]\""),
            ("[^a`\\\n`]", "Document\n└─ Paragraph\n   ├─ Text \"[^a\"\n   ├─ InlineCode `\\ `\n   └─ Text \"]\""),
            ("[^`\\\n`] x", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `\\ `\n   └─ Text \"] x\""),
            ("[^`\\\r\n`]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `\\ `\n   └─ Text \"]\""),
            ("[^`\\\r`]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `\\ `\n   └─ Text \"]\""),
            ("[^`\n`]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode ` `\n   └─ Text \"]\""),
            ("[^``\\\n``]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `\\ `\n   └─ Text \"]\""),
            ("[^`a  \n`]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `a   `\n   └─ Text \"]\""),
            ("[^<a b=\"\\\n\">]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineHTML <a b=\"\\\n\">\n   └─ Text \"]\""),
            ("[^![x](/u \"a\\\nb\")]", "Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ Image source: \"/u\" title: \"a\\\nb\"\n   │  └─ Text \"x\"\n   └─ Text \"]\""),
        ]
        for (markdown, expected) in cases {
            XCTAssertEqual(expected, surface(markdown, cmarkBugCompatible: false), markdown.debugDescription)
        }
        let positionsOff = Document(parsing: "[^`\\\n`]", options: ParseOptions(rawValue: UInt(0xfc & 0b11011111))).debugDescription(options: [])
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `\\ `\n   └─ Text \"]\"", positionsOff)
    }
}
