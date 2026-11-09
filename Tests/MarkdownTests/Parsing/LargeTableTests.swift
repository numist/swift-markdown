/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Tables (extension) set no limit on the number of cells in a row or on the number of empty cells inserted
/// into rows shorter than the header row.
///
/// The large inputs assert structure through the `Markdown` API rather than a full `debugDescription`.
class LargeTableTests: XCTestCase {
    private func parse(_ markdown: String) -> Document {
        Document(parsing: markdown, options: [])
    }

    /// The kinds of the document's top-level blocks, e.g. `["Table", "Paragraph"]`.
    private func blockKinds(_ document: Document) -> [String] {
        document.children.map { String(describing: type(of: $0)) }
    }

    private func table(_ document: Document) -> Table? {
        document.children.lazy.compactMap { $0 as? Table }.first
    }

    /// The text of the first `Text` child of the document's first top-level paragraph, truncated to `count` characters.
    private func paragraphPrefix(_ document: Document, _ count: Int) -> String? {
        guard let paragraph = document.children.lazy.compactMap({ $0 as? Paragraph }).first,
              let text = paragraph.child(at: 0) as? Text else {
            return nil
        }
        return String(text.string.prefix(count))
    }

    // MARK: - Cells per row

    func testBodyRowOf100000CellsStaysInTable() {
        let document = parse("a|b\n-|-\n|" + String(repeating: "c|", count: 100_000) + "\n")
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
        XCTAssertEqual(2, table(document)?.body.child(at: 0)?.childCount)
    }

    func testHeaderAndDelimiterOf100000ColumnsAreATable() {
        let markdown = "|" + String(repeating: "a|", count: 100_000) + "\n|" + String(repeating: "-|", count: 100_000) + "\n"
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(100_000, table(document)?.head.childCount)
    }

    /// A delimiter row whose cell count differs from the header row's opens no table.
    func testDelimiterOf100000ColumnsUnderTwoColumnHeaderIsNotATable() {
        let markdown = "a|b\n|" + String(repeating: "-|", count: 100_000) + "\n"
        XCTAssertEqual(["Paragraph"], blockKinds(parse(markdown)))
    }

    func testParagraphLineOf100000CellsAboveHeaderAllowsTable() {
        let document = parse(String(repeating: "x|", count: 100_000) + "\nb\n:-\n")
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    /// The block quote's paragraph keeps its wide line, and its last line heads a table.
    func testQuotedParagraphLineOf100000CellsAboveHeaderAllowsTable() {
        let markdown = "> " + String(repeating: "x|", count: 100_000) + "\n> b\n> :-\n"
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        XCTAssertEqual(["Paragraph", "Table"], document.child(at: 0)?.children.map { String(describing: type(of: $0)) })
    }

    // MARK: - Empty cells inserted into short rows

    /// Each of the thousand one-cell body rows of a thousand-column table gets 999 empty cells.
    func testRowsMissingCellsInsertAMillionEmptyCells() {
        let markdown = "|" + String(repeating: "a|", count: 1000) + "\n|" + String(repeating: "-|", count: 1000) + "\n"
            + String(repeating: "x\n", count: 1000)
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1000, table(document)?.body.childCount)
        XCTAssertEqual(1000, table(document)?.body.child(at: 999)?.childCount)
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

    /// Every quoted line, `:-` and `z` included, is a row of one table.
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

    /// `:-` and `z` are rows of the table.
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

    /// A header row that ends a multi-line paragraph heads a table that keeps every row.
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
