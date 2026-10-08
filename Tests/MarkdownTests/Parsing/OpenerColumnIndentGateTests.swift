/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// An ATX heading, thematic break or HTML block start may be indented by up to three spaces; a line indented
/// by four or more columns is an indented code block. A tab advances to the next tab stop of 4 columns (Tabs),
/// so a tab-indented line after a block quote's fenced code block is indented code.
class OpenerColumnIndentGateTests: XCTestCase {
    /// Asserts that `>~~~` followed by a tab-indented `construct` is a block quote holding an empty fenced code
    /// block, followed by an indented code block whose content is `construct`.
    private func checkTabAfterFenceIsIndentedCode(
        construct: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let input = ">~~~\n\t\(construct)"
        XCTAssertTrue(input.utf8.contains(0x09), "fixture must contain a tab", file: file, line: line)

        let document = Document(parsing: input)

        XCTAssertEqual(document.childCount, 2, "expected exactly two top-level children", file: file, line: line)

        let blockQuotes = document.children.compactMap { $0 as? BlockQuote }
        XCTAssertEqual(blockQuotes.count, 1, "expected exactly one top-level block quote", file: file, line: line)
        let nestedCodeBlocks = blockQuotes.first?.children.compactMap { $0 as? CodeBlock } ?? []
        XCTAssertEqual(nestedCodeBlocks.count, 1, "expected exactly one code block inside the block quote", file: file, line: line)
        XCTAssertEqual(nestedCodeBlocks.first?.code, "", file: file, line: line)

        let topLevelCodeBlocks = document.children.compactMap { $0 as? CodeBlock }
        XCTAssertEqual(topLevelCodeBlocks.count, 1, "expected exactly one top-level code block", file: file, line: line)
        XCTAssertEqual(topLevelCodeBlocks.first?.code, "\(construct)\n", file: file, line: line)
        XCTAssertNil(topLevelCodeBlocks.first?.language, file: file, line: line)
    }

    // MARK: ATX heading

    func testThreeSpaceIndentedATXOpensHeading() {
        let document = Document(parsing: "   # x")
        let headings = document.children.compactMap { $0 as? Heading }
        XCTAssertEqual(headings.count, 1, "3-space indent must open an ATX heading")
        XCTAssertEqual(headings.first?.level, 1)
        XCTAssertEqual(headings.first?.plainText, "x")
        XCTAssertTrue(document.children.compactMap { $0 as? CodeBlock }.isEmpty, "must not be indented code")
    }

    func testTabIndentedATXBecomesIndentedCode() {
        checkTabAfterFenceIsIndentedCode(construct: "# x")
    }

    // MARK: Thematic break

    func testThreeSpaceIndentedThematicBreakOpens() {
        let document = Document(parsing: "   ***")
        XCTAssertEqual(document.children.compactMap { $0 as? ThematicBreak }.count, 1, "3-space indent must open a thematic break")
        XCTAssertTrue(document.children.compactMap { $0 as? CodeBlock }.isEmpty, "must not be indented code")
    }

    func testTabIndentedThematicBreakBecomesIndentedCode() {
        checkTabAfterFenceIsIndentedCode(construct: "***")
    }

    // MARK: HTML block

    func testThreeSpaceIndentedHTMLBlockOpens() {
        let document = Document(parsing: "   <pre>")
        XCTAssertEqual(document.children.compactMap { $0 as? HTMLBlock }.count, 1, "3-space indent must open an HTML block")
        XCTAssertTrue(document.children.compactMap { $0 as? CodeBlock }.isEmpty, "must not be indented code")
    }

    func testTabIndentedHTMLBlockBecomesIndentedCode() {
        checkTabAfterFenceIsIndentedCode(construct: "<pre>")
    }
}
