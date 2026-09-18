/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// The block-opener branches in `dispatchNewBlocks` (`BlockParser`) each gate on cmark's `!indented`
/// (`parser->indent < 4`, a COLUMN measure; blocks.c `open_new_blocks`): a line whose indent reaches
/// four columns is indented code, not a new block. A raw prefix TAB (one byte, four columns) reaches an
/// opener unexpanded only on a line processed while an open fenced code block is `current` (the one case
/// `expandPrefixTabs` is skipped), so `>~~~` then a tab-indented construct closes the quote's fence and
/// makes the construct indented-code CONTENT rather than a new block. A byte-distance gate would see one
/// byte, admit the opener, and consume the construct as a marker. These tests cover the ATX-heading,
/// thematic-break, and HTML-block openers; the fenced-code opener is covered by
/// `FencedCodeTabExpansionTests`.
class OpenerColumnIndentGateTests: XCTestCase {
    /// Assert `>~~~` followed by a TAB-indented `construct` parses to a block quote holding the empty
    /// fenced code block, followed by a top-level INDENTED code block whose content is `construct` (plus
    /// the code block's trailing newline). The construct did NOT open a new block.
    private func checkTabAfterFenceIsIndentedCode(
        construct: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let input = ">~~~\n\t\(construct)"
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab", file: file, line: line)

        let document = Document(parsing: input)

        // Exactly two top-level children: the block quote and the indented code block - nothing the
        // tab-indented construct opened.
        XCTAssertEqual(document.childCount, 2, "expected exactly two top-level children", file: file, line: line)

        // The block quote's fenced code block opened on `>~~~` and never closed, so it is empty.
        let blockQuotes = document.children.compactMap { $0 as? BlockQuote }
        XCTAssertEqual(blockQuotes.count, 1, "expected exactly one top-level block quote", file: file, line: line)
        let nestedCodeBlocks = blockQuotes.first?.children.compactMap { $0 as? CodeBlock } ?? []
        XCTAssertEqual(nestedCodeBlocks.count, 1, "expected exactly one code block inside the block quote", file: file, line: line)
        XCTAssertEqual(nestedCodeBlocks.first?.code, "", file: file, line: line)

        // Ground truth (cmark): the tab-indented construct is the indented code block's content.
        let topLevelCodeBlocks = document.children.compactMap { $0 as? CodeBlock }
        XCTAssertEqual(topLevelCodeBlocks.count, 1, "expected exactly one top-level code block", file: file, line: line)
        XCTAssertEqual(topLevelCodeBlocks.first?.code, "\(construct)\n", file: file, line: line)
        XCTAssertNil(topLevelCodeBlocks.first?.language, file: file, line: line)
    }

    // MARK: ATX heading

    /// A 3-space-indented ATX marker (indent < 4 columns) still opens a heading.
    func testThreeSpaceIndentedATXOpensHeading() {
        let document = Document(parsing: "   # x")
        let headings = document.children.compactMap { $0 as? Heading }
        XCTAssertEqual(headings.count, 1, "3-space indent must still open an ATX heading")
        XCTAssertEqual(headings.first?.level, 1)
        XCTAssertEqual(headings.first?.plainText, "x")
        XCTAssertTrue(document.children.compactMap { $0 as? CodeBlock }.isEmpty, "must not be indented code")
    }

    /// A TAB (four columns) reaching the ATX opener after a fence closes yields indented code, not a heading.
    func testTabIndentedATXBecomesIndentedCode() {
        checkTabAfterFenceIsIndentedCode(construct: "# x")
    }

    // MARK: Thematic break

    /// A 3-space-indented thematic break (indent < 4 columns) still opens a thematic break.
    func testThreeSpaceIndentedThematicBreakOpens() {
        let document = Document(parsing: "   ***")
        XCTAssertEqual(document.children.compactMap { $0 as? ThematicBreak }.count, 1, "3-space indent must still open a thematic break")
        XCTAssertTrue(document.children.compactMap { $0 as? CodeBlock }.isEmpty, "must not be indented code")
    }

    /// A TAB (four columns) reaching the thematic-break opener after a fence closes yields indented code.
    func testTabIndentedThematicBreakBecomesIndentedCode() {
        checkTabAfterFenceIsIndentedCode(construct: "***")
    }

    // MARK: HTML block

    /// A 3-space-indented HTML block start (indent < 4 columns) still opens an HTML block.
    func testThreeSpaceIndentedHTMLBlockOpens() {
        let document = Document(parsing: "   <pre>")
        XCTAssertEqual(document.children.compactMap { $0 as? HTMLBlock }.count, 1, "3-space indent must still open an HTML block")
        XCTAssertTrue(document.children.compactMap { $0 as? CodeBlock }.isEmpty, "must not be indented code")
    }

    /// A TAB (four columns) reaching the HTML-block opener after a fence closes yields indented code.
    func testTabIndentedHTMLBlockBecomesIndentedCode() {
        checkTabAfterFenceIsIndentedCode(construct: "<pre>")
    }
}
