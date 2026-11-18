/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// A fence indented N columns removes up to N columns of indentation from each content line (Fenced code blocks), and
// removing part of a tab leaves its remaining columns as spaces (Tabs).
class FencedCodeTabExpansionTests: XCTestCase {
    private func check(
        input: String,
        docRange: String,
        codeBlockRange: String,
        expectedCode: String,
        contentDisplay: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab", file: file, line: line)

        let document = Document(parsing: input)

        let codeBlocks = document.children.compactMap { $0 as? CodeBlock }
        XCTAssertEqual(codeBlocks.count, 1, "expected exactly one top-level code block", file: file, line: line)
        guard let codeBlock = codeBlocks.first else { return }
        XCTAssertNil(codeBlock.language, file: file, line: line)

        XCTAssertEqual(codeBlock.code, expectedCode, file: file, line: line)

        let expectedDump = "Document \(docRange)\n└─ CodeBlock \(codeBlockRange) language: none\n\(contentDisplay)"
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations), file: file, line: line)
    }

    func testOneSpaceFenceSingleTab() {
        check(
            input: " ```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:2-2:2",
            expectedCode: "   \n",
            contentDisplay: String(repeating: " ", count: 6)
        )
    }

    func testTwoSpaceFenceSingleTab() {
        check(
            input: "  ```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:3-2:2",
            expectedCode: "  \n",
            contentDisplay: String(repeating: " ", count: 5)
        )
    }

    func testThreeSpaceFenceSingleTab() {
        check(
            input: "   ```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:4-2:2",
            expectedCode: " \n",
            contentDisplay: String(repeating: " ", count: 4)
        )
    }

    func testOneSpaceFenceTabThenChar() {
        check(
            input: " ```\n\tx",
            docRange: "@1:1-2:3",
            codeBlockRange: "@1:2-2:3",
            expectedCode: "   x\n",
            contentDisplay: String(repeating: " ", count: 6) + "x"
        )
    }

    func testOneSpaceFenceTwoTabsThenChar() {
        check(
            input: " ```\n\t\tx",
            docRange: "@1:1-2:4",
            codeBlockRange: "@1:2-2:4",
            expectedCode: "   \tx\n",
            contentDisplay: String(repeating: " ", count: 6) + "\tx"
        )
    }

    // Two columns precede the tab, so it spans two columns, and removing the fence's one column of indentation leaves
    // one space.
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

        XCTAssertEqual(codeBlock.code, " x\n")

        let expectedDump =
            "Document @1:1-2:5\n"
            + "└─ BlockQuote @1:1-2:5\n"
            + "   └─ CodeBlock @1:4-2:5 language: none\n"
            + String(repeating: " ", count: 7) + "x"
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    func testZeroIndentFenceKeepsLiteralTab() {
        check(
            input: "```\n\t",
            docRange: "@1:1-2:2",
            codeBlockRange: "@1:1-2:2",
            expectedCode: "\t\n",
            contentDisplay: String(repeating: " ", count: 3) + "\t"
        )
    }

    // Only paragraph continuation text can be lazy (Block quotes), so this line ends the block quote and its
    // fenced code block and, indented four columns, opens an indented code block.
    func testTabIndentedCodeAfterBlockQuoteCloses() {
        let input = ">~~~\n\t~~~"
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab")

        let document = Document(parsing: input)

        let blockQuotes = document.children.compactMap { $0 as? BlockQuote }
        XCTAssertEqual(blockQuotes.count, 1, "expected exactly one top-level block quote")
        let topLevelCodeBlocks = document.children.compactMap { $0 as? CodeBlock }
        XCTAssertEqual(topLevelCodeBlocks.count, 1, "expected exactly one top-level code block")

        let nestedCodeBlocks = blockQuotes.first?.children.compactMap { $0 as? CodeBlock } ?? []
        XCTAssertEqual(nestedCodeBlocks.count, 1, "expected exactly one code block inside the block quote")
        XCTAssertEqual(nestedCodeBlocks.first?.code, "")
        XCTAssertNil(nestedCodeBlocks.first?.language)

        guard let topLevelCode = topLevelCodeBlocks.first else { return }
        XCTAssertEqual(topLevelCode.code, "~~~\n")
        XCTAssertNil(topLevelCode.language)
    }
}
