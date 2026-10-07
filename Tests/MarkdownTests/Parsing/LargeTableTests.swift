/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Tables (extension) set no limit on the number of cells in a row or on the number of empty cells inserted
/// into rows shorter than the header row.
///
/// The inputs are large, so these assert structure through the `Markdown` API rather than a full
/// `debugDescription`.
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

    private static func bodyRowTable(cells: Int) -> String {
        "a|b\n-|-\n|" + String(repeating: "c|", count: cells) + "\n"
    }

    func testBodyRowOf65534CellsStaysInTable() {
        let document = parse(Self.bodyRowTable(cells: 65534))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
        XCTAssertEqual(2, table(document)?.body.child(at: 0)?.childCount)
    }

    func testBodyRowOf65535CellsStaysInTable() {
        let document = parse(Self.bodyRowTable(cells: 65535))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
    }

    func testHeaderAndDelimiterOf65535ColumnsAreATable() {
        let markdown = "|" + String(repeating: "a|", count: 65535) + "\n|" + String(repeating: "-|", count: 65535) + "\n"
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(65535, table(document)?.head.childCount)
    }

    /// A delimiter row whose cell count differs from the header row's opens no table.
    func testDelimiterOf65535ColumnsUnderTwoColumnHeaderIsNotATable() {
        let markdown = "a|b\n|" + String(repeating: "-|", count: 65535) + "\n"
        XCTAssertEqual(["Paragraph"], blockKinds(parse(markdown)))
    }

    private static func tableUnderWideLine(cells: Int) -> String {
        String(repeating: "x|", count: cells) + "\nb\n:-\n"
    }

    func testParagraphLineOf65534CellsAboveHeaderAllowsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65534))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    /// The block quote's paragraph keeps its wide line, and its last line heads a table.
    func testQuotedParagraphLineOf65535CellsAboveHeaderAllowsTable() {
        let markdown = "> " + String(repeating: "x|", count: 65535) + "\n> b\n> :-\n"
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        XCTAssertEqual(["Paragraph", "Table"], document.child(at: 0)?.children.map { String(describing: type(of: $0)) })
    }

    func testParagraphLineOf65535CellsAboveHeaderAllowsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65535))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    // MARK: - Empty cells inserted into short rows

    // Each one-cell body row of a `wideColumns`-column table gets 1024 empty cells.
    private static let wideColumns = 1025
    private static let shortRowCount = 513

    private static func wideTable(_ bodyRows: [String]) -> String {
        "|" + String(repeating: "a|", count: wideColumns) + "\n|"
            + String(repeating: "-|", count: wideColumns) + "\n"
            + bodyRows.map { $0 + "\n" }.joined()
    }

    func testRowsMissing1024CellsEachStayInTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.shortRowCount)))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.shortRowCount, table(document)?.body.childCount)
    }

    func testKeepsRowsAfterRowWiderThanTable() {
        let wideRow = String(repeating: "y|", count: 3000)
        let rows = [wideRow] + Array(repeating: "x", count: Self.shortRowCount + 1)
        let document = parse(Self.wideTable(rows))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.shortRowCount + 2, table(document)?.body.childCount)
    }

    /// Every quoted line, `:-` and `z` included, is a row of one table.
    func testQuotedRowsMissingCellsStayInTable() {
        let markdown = Self.wideTable(Array(repeating: "x", count: Self.shortRowCount + 1) + [":-", "z"])
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "> " + $0 }
            .joined(separator: "\n")
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        guard let quote = document.child(at: 0) else { return XCTFail("missing block quote") }
        XCTAssertEqual(["Table"], quote.children.map { String(describing: type(of: $0)) })
        XCTAssertEqual(Self.shortRowCount + 3, (quote.child(at: 0) as? Table)?.body.childCount)
    }

    /// `:-` and `z` are rows of the table.
    func testDelimiterShapedRowStaysInTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.shortRowCount + 1) + [":-", "z"]))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.shortRowCount + 3, table(document)?.body.childCount)
    }

    /// A header row that ends a multi-line paragraph heads a table that keeps every row.
    func testMultiLineHeaderTableKeepsRows() {
        let rows = Array(repeating: "x", count: Self.shortRowCount + 1)
        let document = parse("p\n" + Self.wideTable(rows))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual(Self.shortRowCount + 1, table(document)?.body.childCount)
    }

    func testCRLFTableKeepsRows() {
        let rows = Array(repeating: "x", count: Self.shortRowCount + 1)
        let markdown = Self.wideTable(rows).replacingOccurrences(of: "\n", with: "\r\n")
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.shortRowCount + 1, table(document)?.body.childCount)
    }

    func testThousandColumnTableKeepsAllRows() {
        let markdown = "|" + String(repeating: "a|", count: 1000) + "\n|" + String(repeating: "-|", count: 1000) + "\n"
            + String(repeating: "x\n", count: 600)
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(600, table(document)?.body.childCount)
    }

    func testOneMoreRowMissing1024CellsStaysInTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.shortRowCount + 1)))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.shortRowCount + 1, table(document)?.body.childCount)
    }
}
