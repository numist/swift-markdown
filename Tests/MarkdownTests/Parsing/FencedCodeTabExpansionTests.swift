/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A GFM fenced code block whose OPENING fence is indented, followed by a body line whose leading
/// whitespace contains a TAB that straddles the fence-indent boundary.
///
/// cmark strips the fence's indentation from each body line in COLUMNS, tab-stop-aware (blocks.c
/// `parse_code_block_prefix` advances `fence_offset` columns). When a body-line tab straddles that
/// boundary, cmark's `partially_consumed_tab` (blocks.c `add_line`) drops the tab byte and emits its
/// leftover columns as spaces, then copies the rest of the line verbatim (so any *content* tab stays
/// literal). A tab occupying columns [0,4) therefore contributes `4 - fence_offset` leading spaces to
/// the content. The 0-indent fence consumes nothing, so a body tab stays a literal tab.
class FencedCodeTabExpansionTests: XCTestCase {
    /// Assert the parsed document is a single top-level fenced code block with the expected content
    /// bytes and dump. `contentDisplay` is the code line as `debugDescription` renders it: the raw
    /// code content prefixed by the dumper's 3-space display indent for a top-level code block.
    private func check(
        input: String,
        docRange: String,
        codeBlockRange: String,
        expectedCode: String,
        contentDisplay: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Fixture sanity: the body must actually contain a tab, or the case proves nothing.
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab", file: file, line: line)

        let document = Document(parsing: input)

        // Fixture sanity: the input must parse to exactly one top-level fenced code block.
        let codeBlocks = document.children.compactMap { $0 as? CodeBlock }
        XCTAssertEqual(codeBlocks.count, 1, "expected exactly one top-level code block", file: file, line: line)
        guard let codeBlock = codeBlocks.first else { return }
        XCTAssertNil(codeBlock.language, file: file, line: line)

        // The observable content bytes (this is what the fence-indent strip drops when it is not
        // tab-stop-aware).
        XCTAssertEqual(codeBlock.code, expectedCode, file: file, line: line)

        let expectedDump = "Document \(docRange)\n└─ CodeBlock \(codeBlockRange) language: none\n\(contentDisplay)"
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations), file: file, line: line)
    }

    /// 1-space fence, body is one tab: the tab spans columns [0,4); the 1-column strip consumes one of
    /// them, leaving 3 spaces of content.
    func testOneSpaceFenceSingleTab() {
        check(
            input: " ```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:2-2:2",
            expectedCode: "   \n",
            contentDisplay: String(repeating: " ", count: 6)
        )
    }

    /// 2-space fence, body is one tab: 2 columns stripped, 2 spaces of content remain.
    func testTwoSpaceFenceSingleTab() {
        check(
            input: "  ```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:3-2:2",
            expectedCode: "  \n",
            contentDisplay: String(repeating: " ", count: 5)
        )
    }

    /// 3-space fence, body is one tab: 3 columns stripped, 1 space of content remains.
    func testThreeSpaceFenceSingleTab() {
        check(
            input: "   ```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:4-2:2",
            expectedCode: " \n",
            contentDisplay: String(repeating: " ", count: 4)
        )
    }

    /// 1-space fence, body is a tab followed by `x`: the tab's 3 leftover columns become spaces, then
    /// `x` is copied verbatim.
    func testOneSpaceFenceTabThenChar() {
        check(
            input: " ```\n\tx",
            docRange: "@1:1-2:3",
            codeBlockRange: "@1:2-2:3",
            expectedCode: "   x\n",
            contentDisplay: String(repeating: " ", count: 6) + "x"
        )
    }

    /// Two leading tabs, 1-space fence: the FIRST tab straddles the 1-column strip (3 leftover spaces);
    /// the SECOND tab is entirely past the boundary and stays a literal content tab, copied verbatim.
    func testOneSpaceFenceTwoTabsThenChar() {
        check(
            input: " ```\n\t\tx",
            docRange: "@1:1-2:4",
            codeBlockRange: "@1:2-2:4",
            expectedCode: "   \tx\n",
            contentDisplay: String(repeating: " ", count: 6) + "\tx"
        )
    }

    /// A fence nested in a block quote: the body tab is measured from the container column (2), not the
    /// line start, so its width is 2 and the 1-column strip leaves a single space (NOT three). Exercises
    /// the `startColumn`/`columnWidth` path that a top-level fence never reaches - a broken `columnWidth`
    /// returning 0 would treat the tab as 4 columns wide and emit `   x`.
    func testNestedBlockQuoteFenceStraddlingTab() {
        let input = ">  ```\n> \tx"
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab")

        let document = Document(parsing: input)
        let blockQuotes = document.children.compactMap { $0 as? BlockQuote }
        XCTAssertEqual(blockQuotes.count, 1, "expected exactly one block quote")
        let codeBlocks = blockQuotes.first?.children.compactMap { $0 as? CodeBlock } ?? []
        XCTAssertEqual(codeBlocks.count, 1, "expected exactly one code block inside the block quote")
        guard let codeBlock = codeBlocks.first else { return }
        XCTAssertNil(codeBlock.language)

        // Ground truth (cmark): the tab at column 2 has width 2; the 1-column strip leaves one space, then `x`.
        XCTAssertEqual(codeBlock.code, " x\n")

        let expectedDump =
            "Document @1:1-2:5\n"
            + "└─ BlockQuote @1:1-2:5\n"
            + "   └─ CodeBlock @1:4-2:5 language: none\n"
            + String(repeating: " ", count: 7) + "x"
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Guard: a 0-indent fence consumes nothing, so a body tab stays a literal tab (must NOT expand).
    func testZeroIndentFenceKeepsLiteralTab() {
        check(
            input: "```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:1-2:2",
            expectedCode: "\t\n",
            contentDisplay: String(repeating: " ", count: 3) + "\t"
        )
    }

    /// After a block quote (with an unclosed empty fenced code block) closes, a line whose leading TAB
    /// reaches four columns opens an INDENTED code block, not a second fence. cmark gates the fence
    /// opener on `!indented` (`parser->indent < 4`, blocks.c `open_new_blocks`), an indent measured in
    /// COLUMNS - so the tab (one byte, four columns) is indented code and the `~~~` is its content, not a
    /// fence marker. The tab reaches the opener unexpanded because a fenced-code body line skips
    /// `expandPrefixTabs`; a byte-distance gate would see one byte, admit the fence, and drop the `~~~`.
    func testTabIndentedCodeAfterBlockQuoteCloses() {
        let input = ">~~~\n\t~~~"
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab")

        let document = Document(parsing: input)

        // Top level: a block quote (holding the empty fenced code block) followed by an indented code block.
        let blockQuotes = document.children.compactMap { $0 as? BlockQuote }
        XCTAssertEqual(blockQuotes.count, 1, "expected exactly one top-level block quote")
        let topLevelCodeBlocks = document.children.compactMap { $0 as? CodeBlock }
        XCTAssertEqual(topLevelCodeBlocks.count, 1, "expected exactly one top-level code block")

        // The block quote's fenced code block opened on `>~~~` and never closed, so it is empty.
        let nestedCodeBlocks = blockQuotes.first?.children.compactMap { $0 as? CodeBlock } ?? []
        XCTAssertEqual(nestedCodeBlocks.count, 1, "expected exactly one code block inside the block quote")
        XCTAssertEqual(nestedCodeBlocks.first?.code, "")
        XCTAssertNil(nestedCodeBlocks.first?.language)

        // Ground truth (cmark): the tab-indented `~~~` is the indented code block's content, not a fence.
        guard let topLevelCode = topLevelCodeBlocks.first else { return }
        XCTAssertEqual(topLevelCode.code, "~~~\n")
        XCTAssertNil(topLevelCode.language)
    }
}
