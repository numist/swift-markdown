/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// A table row holds at most 65,534 cells, and once a table has inserted more than 524,288 empty cells into body rows
// shorter than its header row, the next row ends the table.
class LargeTableTests: XCTestCase {
    private func parse(_ markdown: String) -> Document {
        Document(parsing: markdown, options: [])
    }

    private func blockKinds(_ document: Document) -> [String] {
        document.children.map { String(describing: type(of: $0)) }
    }

    private func table(_ document: Document) -> Table? {
        document.children.lazy.compactMap { $0 as? Table }.first
    }

    private func paragraphPrefix(_ document: Document, _ count: Int) -> String? {
        guard let paragraph = document.children.lazy.compactMap({ $0 as? Paragraph }).first,
              let text = paragraph.child(at: 0) as? Text else {
            return nil
        }
        return String(text.string.prefix(count))
    }

    func testBodyRowOf100000CellsEndsTable() {
        let document = parse("a|b\n-|-\n|" + String(repeating: "c|", count: 100_000) + "\n")
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(0, table(document)?.body.childCount)
        XCTAssertEqual("|c|c|", paragraphPrefix(document, 5))
    }

    func testHeaderAndDelimiterOf100000ColumnsAreAParagraph() {
        let markdown = "|" + String(repeating: "a|", count: 100_000) + "\n|" + String(repeating: "-|", count: 100_000) + "\n"
        let document = parse(markdown)
        XCTAssertEqual(["Paragraph"], blockKinds(document))
        XCTAssertEqual("|a|a|", paragraphPrefix(document, 5))
    }

    func testDelimiterOf100000ColumnsUnderTwoColumnHeaderIsNotATable() {
        let markdown = "a|b\n|" + String(repeating: "-|", count: 100_000) + "\n"
        XCTAssertEqual(["Paragraph"], blockKinds(parse(markdown)))
    }

    func testParagraphLineOf100000CellsAboveHeaderKeepsTableFromOpening() {
        let document = parse(String(repeating: "x|", count: 100_000) + "\nb\n:-\n")
        XCTAssertEqual(["Paragraph"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
        XCTAssertEqual(5, document.child(at: 0)?.childCount)
    }

    func testQuotedParagraphLineOf100000CellsAboveHeaderKeepsTableFromOpening() {
        let markdown = "> " + String(repeating: "x|", count: 100_000) + "\n> b\n> :-\n"
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        XCTAssertEqual(["Paragraph"], document.child(at: 0)?.children.map { String(describing: type(of: $0)) })
        XCTAssertEqual(5, document.child(at: 0)?.child(at: 0)?.childCount)
    }

    // Each one-cell row gets 999 empty cells, so the first 525 rows insert 524,475, and the other 475 lines are a
    // paragraph.
    func testRowsMissingCellsStopAfterInserting524475EmptyCells() {
        let markdown = "|" + String(repeating: "a|", count: 1000) + "\n|" + String(repeating: "-|", count: 1000) + "\n"
            + String(repeating: "x\n", count: 1000)
        let document = parse(markdown)
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(525, table(document)?.body.childCount)
        XCTAssertEqual(1000, table(document)?.body.child(at: 524)?.childCount)
        XCTAssertEqual(949, document.child(at: 1)?.childCount)
    }

    func testKeepsRowsAfterRowWiderThanTable() {
        XCTAssertEqual("""
            Document
            └─ Table alignments: |-|-|-|
               ├─ Head
               │  ├─ Cell
               │  │  └─ Text "a"
               │  ├─ Cell
               │  │  └─ Text "a"
               │  └─ Cell
               │     └─ Text "a"
               └─ Body
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text "y"
                  │  ├─ Cell
                  │  │  └─ Text "y"
                  │  └─ Cell
                  │     └─ Text "y"
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text "x"
                  │  ├─ Cell
                  │  └─ Cell
                  └─ Row
                     ├─ Cell
                     │  └─ Text "x"
                     ├─ Cell
                     └─ Cell
            """, parse("|a|a|a|\n|-|-|-|\ny|y|y|y|y|\nx\nx\n").debugDescription())
    }

    func testQuotedRowsMissingCellsStayInTable() {
        XCTAssertEqual("""
            Document
            └─ BlockQuote
               └─ Table alignments: |-|-|-|
                  ├─ Head
                  │  ├─ Cell
                  │  │  └─ Text "a"
                  │  ├─ Cell
                  │  │  └─ Text "a"
                  │  └─ Cell
                  │     └─ Text "a"
                  └─ Body
                     ├─ Row
                     │  ├─ Cell
                     │  │  └─ Text "x"
                     │  ├─ Cell
                     │  └─ Cell
                     ├─ Row
                     │  ├─ Cell
                     │  │  └─ Text "x"
                     │  ├─ Cell
                     │  └─ Cell
                     ├─ Row
                     │  ├─ Cell
                     │  │  └─ Text ":-"
                     │  ├─ Cell
                     │  └─ Cell
                     └─ Row
                        ├─ Cell
                        │  └─ Text "z"
                        ├─ Cell
                        └─ Cell
            """, parse("> |a|a|a|\n> |-|-|-|\n> x\n> x\n> :-\n> z\n").debugDescription())
    }

    func testDelimiterShapedRowStaysInTable() {
        XCTAssertEqual("""
            Document
            └─ Table alignments: |-|-|-|
               ├─ Head
               │  ├─ Cell
               │  │  └─ Text "a"
               │  ├─ Cell
               │  │  └─ Text "a"
               │  └─ Cell
               │     └─ Text "a"
               └─ Body
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text "x"
                  │  ├─ Cell
                  │  └─ Cell
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text "x"
                  │  ├─ Cell
                  │  └─ Cell
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text ":-"
                  │  ├─ Cell
                  │  └─ Cell
                  └─ Row
                     ├─ Cell
                     │  └─ Text "z"
                     ├─ Cell
                     └─ Cell
            """, parse("|a|a|a|\n|-|-|-|\nx\nx\n:-\nz\n").debugDescription())
    }

    func testMultiLineHeaderTableKeepsRows() {
        XCTAssertEqual("""
            Document
            ├─ Paragraph
            │  └─ Text "p"
            └─ Table alignments: |-|-|-|
               ├─ Head
               │  ├─ Cell
               │  │  └─ Text "a"
               │  ├─ Cell
               │  │  └─ Text "a"
               │  └─ Cell
               │     └─ Text "a"
               └─ Body
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text "x"
                  │  ├─ Cell
                  │  └─ Cell
                  └─ Row
                     ├─ Cell
                     │  └─ Text "x"
                     ├─ Cell
                     └─ Cell
            """, parse("p\n|a|a|a|\n|-|-|-|\nx\nx\n").debugDescription())
    }

    func testCRLFTableKeepsRows() {
        XCTAssertEqual("""
            Document
            └─ Table alignments: |-|-|-|
               ├─ Head
               │  ├─ Cell
               │  │  └─ Text "a"
               │  ├─ Cell
               │  │  └─ Text "a"
               │  └─ Cell
               │     └─ Text "a"
               └─ Body
                  ├─ Row
                  │  ├─ Cell
                  │  │  └─ Text "x"
                  │  ├─ Cell
                  │  └─ Cell
                  └─ Row
                     ├─ Cell
                     │  └─ Text "x"
                     ├─ Cell
                     └─ Cell
            """, parse("|a|a|a|\r\n|-|-|-|\r\nx\r\nx\r\n").debugDescription())
    }
}
