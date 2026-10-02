/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// cmark's GFM table extension caps a table row at 65534 cells and stops adding body rows once a table has
/// autocompleted too many empty cells.
///
/// Ground truth is cmark-gfm (flag-ON). `extensions/table.c` `row_from_string` returns no row once a row
/// reaches `UINT16_MAX` cells (the `int_overflow_abort` check after each appended cell), and
/// `try_opening_table_row` refuses a body row while `n_columns * n_rows - n_nonempty_cells` (header
/// included, each row's cells capped at the column count) exceeds `MAX_AUTOCOMPLETED_CELLS` (`0x80000`).
/// CommonMark/GFM have neither limit, so flag-OFF keeps every row.
///
/// The inputs are large, so these assert structure through the `Markdown` API rather than a full
/// `debugDescription`.
class TableAntiDoSLimitTests: XCTestCase {
    private func parse(_ markdown: String, cmarkBugCompatible: Bool = true) -> Document {
        Document(parsing: markdown, options: cmarkBugCompatible ? [.cmarkBugCompatibility] : [])
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

    /// A body row reaching 65535 cells is no row at all, so the table ends with an empty body and the
    /// line becomes a following paragraph.
    func testBodyRowOf65535CellsEndsTable() {
        let document = parse(Self.bodyRowTable(cells: 65535))
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(0, table(document)?.body.childCount)
        XCTAssertEqual("|c|c|c", paragraphPrefix(document, 6))
    }

    /// 65534 cells is still a row: it joins the table, truncated to the table's two columns.
    func testBodyRowOf65534CellsStaysInTable() {
        let document = parse(Self.bodyRowTable(cells: 65534))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
        XCTAssertEqual(2, table(document)?.body.child(at: 0)?.childCount)
    }

    /// Flag-OFF has no row cell limit.
    func testFlagOffBodyRowOf65535CellsStaysInTable() {
        let document = parse(Self.bodyRowTable(cells: 65535), cmarkBugCompatible: false)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(1, table(document)?.body.childCount)
    }

    /// A delimiter row of 65535 columns is no delimiter row, so a matching 65535-column header opens no table.
    func testHeaderAndDelimiterOf65535ColumnsAreNotATable() {
        let markdown = "|" + String(repeating: "a|", count: 65535) + "\n|" + String(repeating: "-|", count: 65535) + "\n"
        let document = parse(markdown)
        XCTAssertEqual(["Paragraph"], blockKinds(document))
        XCTAssertEqual("|a|a|a", paragraphPrefix(document, 6))
    }

    /// Flag-OFF has no row cell limit, so the 65535-column header and delimiter open a table.
    func testFlagOffHeaderAndDelimiterOf65535ColumnsAreATable() {
        let markdown = "|" + String(repeating: "a|", count: 65535) + "\n|" + String(repeating: "-|", count: 65535) + "\n"
        let document = parse(markdown, cmarkBugCompatible: false)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(65535, table(document)?.head.childCount)
    }

    /// A 65535-column delimiter under a narrower header is no table either.
    func testDelimiterOf65535ColumnsUnderTwoColumnHeaderIsNotATable() {
        let markdown = "a|b\n|" + String(repeating: "-|", count: 65535) + "\n"
        XCTAssertEqual(["Paragraph"], blockKinds(parse(markdown)))
    }

    /// cmark scans every line of the paragraph above the delimiter for the header row, discarding each
    /// line before the last; a discarded line that reaches 65535 cells still aborts the scan, so the
    /// header row is missing and the paragraph never becomes a table.
    private static func tableUnderWideLine(cells: Int) -> String {
        String(repeating: "x|", count: cells) + "\nb\n:-\n"
    }

    func testParagraphLineOf65535CellsAboveHeaderPreventsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65535))
        XCTAssertEqual(["Paragraph"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    func testParagraphLineOf65534CellsAboveHeaderAllowsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65534))
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
        XCTAssertEqual("x|x|x|", paragraphPrefix(document, 6))
    }

    /// The same holds for a paragraph inside a block quote.
    func testQuotedParagraphLineOf65535CellsAboveHeaderPreventsTable() {
        let markdown = "> " + String(repeating: "x|", count: 65535) + "\n> b\n> :-\n"
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        XCTAssertEqual(["Paragraph"], document.child(at: 0)?.children.map { String(describing: type(of: $0)) })
    }

    func testFlagOffParagraphLineOf65535CellsAboveHeaderAllowsTable() {
        let document = parse(Self.tableUnderWideLine(cells: 65535), cmarkBugCompatible: false)
        XCTAssertEqual(["Paragraph", "Table"], blockKinds(document))
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

    func testRowPastAutocompletedCellBudgetEndsTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)))
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted, table(document)?.body.childCount)
        XCTAssertEqual("x", paragraphPrefix(document, 6))
    }

    func testRowAtAutocompletedCellBudgetStaysInTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted)))
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted, table(document)?.body.childCount)
    }

    /// A row with more cells than the table has columns is charged only for the table's columns: its
    /// extra cells don't offset later rows' autocompleted cells, so exactly 513 one-cell rows still fit.
    func testRowWiderThanTableIsCappedAtColumnCount() {
        let wideRow = String(repeating: "y|", count: 3000)
        let rows = [wideRow] + Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)
        let document = parse(Self.wideTable(rows))
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 1, table(document)?.body.childCount)
        XCTAssertEqual("x", paragraphPrefix(document, 6))
    }

    /// A refused row inside a block quote starts a paragraph inside the same block quote, and a following
    /// delimiter line can open a fresh table under it.
    func testQuotedRowPastBudgetStartsParagraphInBlockQuote() {
        let markdown = Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1) + [":-", "z"])
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "> " + $0 }
            .joined(separator: "\n")
        let document = parse(markdown)
        XCTAssertEqual(["BlockQuote"], blockKinds(document))
        guard let quote = document.child(at: 0) else { return XCTFail("missing block quote") }
        XCTAssertEqual(["Table", "Table"], quote.children.map { String(describing: type(of: $0)) })
        XCTAssertEqual(Self.budgetRowsAdmitted, (quote.child(at: 0) as? Table)?.body.childCount)
        XCTAssertEqual(1, (quote.child(at: 1) as? Table)?.body.childCount)
    }

    /// The refused line becomes a new paragraph, which a following delimiter line turns into a second table.
    func testRowPastBudgetCanHeadSecondTable() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1) + [":-", "z"]))
        XCTAssertEqual(["Table", "Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted, (document.child(at: 0) as? Table)?.body.childCount)
        XCTAssertEqual(1, (document.child(at: 1) as? Table)?.body.childCount)
    }

    /// A header split off a multi-line paragraph starts the budget at the header, like a lone header.
    func testMultiLineHeaderTableHasSameBudget() {
        let rows = Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)
        let document = parse("p\n" + Self.wideTable(rows))
        XCTAssertEqual(["Paragraph", "Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted, table(document)?.body.childCount)
    }

    /// CRLF line endings don't change the count.
    func testCRLFTableHasSameBudget() {
        let rows = Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)
        let markdown = Self.wideTable(rows).replacingOccurrences(of: "\n", with: "\r\n")
        let document = parse(markdown)
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted, table(document)?.body.childCount)
    }

    /// With 1000 columns each one-cell row autocompletes 999 cells; 525 rows reach 524475 > 0x80000, so the
    /// 526th line and every line after it form a paragraph.
    func testThousandColumnTableKeeps525Rows() {
        let markdown = "|" + String(repeating: "a|", count: 1000) + "\n|" + String(repeating: "-|", count: 1000) + "\n"
            + String(repeating: "x\n", count: 600)
        let document = parse(markdown)
        XCTAssertEqual(["Table", "Paragraph"], blockKinds(document))
        XCTAssertEqual(525, table(document)?.body.childCount)
        let paragraph = document.child(at: 1)
        XCTAssertEqual(75 * 2 - 1, paragraph?.childCount, "75 Text lines joined by SoftBreaks")
    }

    /// Flag-OFF has no autocompleted-cell budget.
    func testFlagOffKeepsRowsPastAutocompletedCellBudget() {
        let document = parse(Self.wideTable(Array(repeating: "x", count: Self.budgetRowsAdmitted + 1)), cmarkBugCompatible: false)
        XCTAssertEqual(["Table"], blockKinds(document))
        XCTAssertEqual(Self.budgetRowsAdmitted + 1, table(document)?.body.childCount)
    }
}
