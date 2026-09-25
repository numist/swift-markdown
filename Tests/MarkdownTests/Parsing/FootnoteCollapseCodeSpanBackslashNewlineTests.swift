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
    private func surface(_ markdown: String) -> String {
        var options = ParseOptions(rawValue: UInt(0xec & 0b11011111))
        options.insert(.cmarkBugCompatibility)
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
}
