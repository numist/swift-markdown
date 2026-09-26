/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// Inline-only parsing consolidates adjacent text nodes, as every other mode does.
///
/// Ground truth is cmark-gfm. `cmark_parser_finish` runs `cmark_consolidate_text_nodes` on the document
/// regardless of `CMARK_OPT_INLINE_ONLY` / `CMARK_OPT_PRESERVE_WHITESPACE`, so a failed delimiter or bracket
/// (`_`, `~`, `[`) merges with the text after it. Position-free compare surface.
class InlineOnlyTextConsolidationTests: XCTestCase {
    private func surface(_ markdown: String, _ options: ParseOptions) -> String {
        Document(parsing: markdown, options: options.union(.cmarkBugCompatibility)).debugDescription(options: [])
    }

    func testFailedDelimiterMergesInlineOnly() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"_f\"", surface("_f", .inlineOnly))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"~x\"", surface("~x", .inlineOnly))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[t\"", surface("[t", .inlineOnly))
    }

    func testFailedDelimiterMergesPreserveWhitespace() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"_f\"", surface("_f", .preserveWhitespace))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[t\"", surface("[t", .preserveWhitespace))
    }

    /// Asserts `markdown` parses to a paragraph holding the single text node `merged`, in both inline-only
    /// modes and both `.cmarkBugCompatibility` states (consolidation is AST shape, not a spec quirk).
    private func assertMerges(_ markdown: String, into merged: String, modes: [ParseOptions] = [.inlineOnly, .preserveWhitespace], file: StaticString = #filePath, line: UInt = #line) {
        let expected = "Document\n└─ Paragraph\n   └─ Text \"\(merged)\""
        for mode in modes {
            XCTAssertEqual(expected, surface(markdown, mode), "\(mode) flag-ON", file: file, line: line)
            XCTAssertEqual(expected, Document(parsing: markdown, options: mode).debugDescription(options: []), "\(mode) flag-OFF", file: file, line: line)
        }
    }

    func testFailedEmphasisRunMerges() {
        assertMerges("*a", into: "*a")
        assertMerges("a*b", into: "a*b")
        assertMerges("a_b_", into: "a_b_")
        assertMerges("**a", into: "**a")
    }

    func testFailedBracketMerges() {
        assertMerges("a ]b", into: "a ]b")
        assertMerges("![x", into: "![x")
    }

    func testEntityMergesWithAdjacentText() {
        assertMerges("a&amp;b", into: "a&b")
        assertMerges("&copy;x", into: "©x")
    }

    func testBackslashEscapeMergesWithAdjacentText() {
        assertMerges("a\\*b", into: "a*b")
        assertMerges("\\_x", into: "_x")
        assertMerges("a\\qb", into: "a\\qb")
    }

    func testPreservedNewlineMergesWithAdjacentText() {
        assertMerges("_\nb", into: "_\nb", modes: [.preserveWhitespace])
        assertMerges("a\n&amp;\nb", into: "a\n&\nb", modes: [.preserveWhitespace])
        assertMerges("a\n[b", into: "a\n[b", modes: [.preserveWhitespace])
    }
}
