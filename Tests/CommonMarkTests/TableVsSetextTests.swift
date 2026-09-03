/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A table-pending paragraph (first two lines form a header + delimiter) is NOT a setext-heading
/// candidate. cmark opens the table while processing the delimiter line, so a `-`/`=` on the NEXT line
/// can't underline it: `r\n|-\n-` → Table + a bullet list; `r\n|-\n=` → Table with a `=` body row. The
/// rewrite detected tables at finalize, so its during-parse setext-underline handling fired first and
/// turned `r\n|-` into a level-2 heading. Fixed by skipping the setext transform when the paragraph is
/// table-pending. Spec-aligned `[fix]`, asserted WITHOUT `.cmarkBugCompatibility`.
@Suite("Table-pending paragraph vs setext underline")
struct TableVsSetextTests {

    private func kinds(_ source: String) throws -> (hasTable: Bool, hasHeading: Bool, hasList: Bool, bodyCellTexts: [String]) {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> (Bool, Bool, Bool, [String]) in
            var hasTable = false, hasHeading = false, hasList = false
            var bodyCells: [String] = []
            func walk(_ n: borrowing MarkdownNode) {
                switch n.kind {
                case .table: hasTable = true
                case .heading: hasHeading = true
                case .list: hasList = true
                case .tableRow(let isHeader) where !isHeader:
                    n.children.forEach { cell in
                        guard case .tableCell = cell.kind else { return }
                        var t = ""
                        cell.children.forEach { if let lit = $0.literal() { t += lit } }
                        bodyCells.append(t)
                    }
                default: break
                }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (hasTable, hasHeading, hasList, bodyCells)
        }
    }

    // MARK: - FIX: a table-pending paragraph is not underlined into a heading

    @Test("dash underline after a table delimiter forms a table + a bullet list, not a heading")
    func dashAfterDelimiter() throws {
        // `r\n|-\n-` : `r`+`|-` open a table; `-` is a bullet list, not a setext underline.
        let k = try kinds("r\n|-\n-")
        #expect(k.hasTable && k.hasList && !k.hasHeading)
    }

    @Test("equals line after a table delimiter is a table body row, not a heading")
    func equalsAfterDelimiter() throws {
        // `r\n|-\n=` : `=` isn't a block start, so it's absorbed as a body row "=" of the table.
        let k = try kinds("r\n|-\n=")
        #expect(k.hasTable && !k.hasHeading)
        #expect(k.bodyCellTexts == ["="])
    }

    @Test("multi-column table then an equals line keeps a table (body row), not a heading")
    func multiColumnEquals() throws {
        let k = try kinds("a|b\n-|-\n=")
        #expect(k.hasTable && !k.hasHeading)
        #expect(k.bodyCellTexts.first == "=")
    }

    // MARK: - LEAVE: real setext headings and bare tables unaffected

    @Test("a dash underline with no delimiter row is still a setext heading")
    func plainSetextUnchanged() throws {
        let k = try kinds("r\n-")
        #expect(k.hasHeading && !k.hasTable)
    }

    @Test("a header + delimiter with no third line is still just a table")
    func bareTableUnchanged() throws {
        let k = try kinds("r\n|-")
        #expect(k.hasTable && !k.hasHeading)
    }
}
