/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// cmark's GFM table extension caps a table row at 65534 cells and stops adding body rows once a table has
/// autocompleted too many empty cells.
///
/// CommonMark/GFM have neither limit, so flag-OFF keeps every row.
///
/// The inputs are large, so these assert structure through the `Markdown` API rather than a full
/// `debugDescription`.
class TableAntiDoSLimitTests: XCTestCase {
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

    // MARK: - Row cell limit (`row_from_string`, `UINT16_MAX`)

    private static func bodyRowTable(cells: Int) -> String {
        "a|b\n-|-\n|" + String(repeating: "c|", count: cells) + "\n"
    }

    func testFlagOffBodyRowOf65534CellsStaysInTable() {
        let document = parse(Self.bodyRowTable(cells: 65534))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
        XCTAssertEqual(2, table(document)?.body.child(at: 0)?.childCount)
    }

    /// Flag-OFF has no row cell limit.
    func testFlagOffBodyRowOf65535CellsStaysInTable() {
        let document = parse(Self.bodyRowTable(cells: 65535))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
    }

    /// Flag-OFF has no row cell limit, so the 65535-column header and delimiter open a table.
    func testFlagOffHeaderAndDelimiterOf65535ColumnsAreATable() {
        let markdown = "|" + String(repeating: "a|", count: 65535) + "\n|" + String(repeating: "-|", count: 65535) + "\n"
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(65535, table(document)?.head.childCount)
    }

    /// Flag-OFF agrees: a delimiter row whose cell count differs from the header row's opens no table.
    func testFlagOffDelimiterOf65535ColumnsUnderTwoColumnHeaderIsNotATable() {
        let markdown = "a|b\n|" + String(repeating: "-|", count: 65535) + "\n"
        XCTAssertEqual(["Paragraph"], blockKinds(parse(markdown)))
    }

    private static func tableUnderWideLine(cells: Int) -> String {
        String(repeating: "x|", count: cells) + "\nb\n:-\n"
    }

    func testFlagOffParagraphLineOf65534CellsAboveHeaderAllowsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65534))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    /// Flag-OFF has no row cell limit, so the quoted paragraph's last line heads a table under it.
    func testFlagOffQuotedParagraphLineOf65535CellsAboveHeaderAllowsTable() {
        let markdown = "> " + String(repeating: "x|", count: 65535) + "\n> b\n> :-\n"
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        XCTAssertEqual(["Paragraph", "Table"], document.child(at: 0)?.children.map { String(describing: type(of: $0)) })
    }

    func testFlagOffParagraphLineOf65535CellsAboveHeaderAllowsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65535))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    // MARK: - Autocompleted-cell budget (`try_opening_table_row`, `MAX_AUTOCOMPLETED_CELLS`)

    // With 1025 columns, each one-cell body row autocompletes 1024 cells. After 512 such rows the table
    // has autocompleted exactly 0x80000 cells, which the `>` test still admits, so the 513th row joins;
    // after it the total is 0x80000 + 1024, so the 514th line is refused and becomes a paragraph.
    private static let budgetColumns = 1025
    private static let budgetRowsAdmitted = 513

    private static func wideTable(_ bodyRows: [String]) -> String {
        "|" + String(repeating: "a|", count: budgetColumns) + "\n|"
            + String(repeating: "-|", count: budgetColumns) + "\n"
            + bodyRows.map { $0 + "\n" }.joined()
    }

    func testFlagOffRowAtAutocompletedCellBudgetStaysInTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted)))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted, table(document)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget, so the wide row and every one-cell row stay in the table.
    func testFlagOffKeepsRowsAfterRowWiderThanTable() {
        let wideRow = String(repeating: "y|", count: 3000)
        let rows = [wideRow] + Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)
        let document = parse(Self.wideTable(rows))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 2, table(document)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget, so every quoted line, `:-` and `z` included, is a row of one table.
    func testFlagOffQuotedRowsPastBudgetStayInTable() {
        let markdown = Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1) + [":-", "z"])
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "> " + $0 }
            .joined(separator: "\n")
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        guard let quote = document.child(at: 0) else { return XCTFail("missing block quote") }
        XCTAssertEqual(["Table"], quote.children.map { String(describing: type(of: $0)) })
        XCTAssertEqual(Self.budgetRowsAdmitted + 3, (quote.child(at: 0) as? Table)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget, so `:-` and `z` are rows of the first table.
    func testFlagOffRowsPastBudgetStayInFirstTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1) + [":-", "z"]))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 3, table(document)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget, so a header split off a multi-line paragraph keeps every row.
    func testFlagOffMultiLineHeaderTableKeepsRows() {
        let rows = Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)
        let document = parse("p\n" + Self.wideTable(rows))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 1, table(document)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget, with CRLF line endings too.
    func testFlagOffCRLFTableKeepsRows() {
        let rows = Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)
        let markdown = Self.wideTable(rows).replacingOccurrences(of: "\n", with: "\r\n")
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 1, table(document)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget, so all 600 rows stay in the table.
    func testFlagOffThousandColumnTableKeepsAllRows() {
        let markdown = "|" + String(repeating: "a|", count: 1000) + "\n|" + String(repeating: "-|", count: 1000) + "\n"
            + String(repeating: "x\n", count: 600)
        let document = parse(markdown)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(600, table(document)?.body.childCount)
    }

    /// Flag-OFF has no autocompleted-cell budget.
    func testFlagOffKeepsRowsPastAutocompletedCellBudget() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 1, table(document)?.body.childCount)
    }
}
