/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Once a header row and delimiter row form a table, the paragraph is gone, so a following `-` or `=` line
/// is not a setext heading underline (Setext headings): `-` starts a list and `=` is a body row.
@Suite("Table followed by a setext heading underline")
struct TableVsSetextTests {

    private func kinds(_ source: String) -> (hasTable: Bool, hasHeading: Bool, hasList: Bool, bodyCellTexts: [String]) {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> (Bool, Bool, Bool, [String]) in
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

    // MARK: - After a table

    @Test("dash underline after a table delimiter forms a table + a bullet list, not a heading")
    func dashAfterDelimiter() {
        let k = kinds("r\n|-\n-")
        #expect(k.hasTable && k.hasList && !k.hasHeading)
    }

    @Test("equals line after a table delimiter is a table body row, not a heading")
    func equalsAfterDelimiter() {
        let k = kinds("r\n|-\n=")
        #expect(k.hasTable && !k.hasHeading)
        #expect(k.bodyCellTexts == ["="])
    }

    @Test("multi-column table then an equals line keeps a table (body row), not a heading")
    func multiColumnEquals() {
        let k = kinds("a|b\n-|-\n=")
        #expect(k.hasTable && !k.hasHeading)
        #expect(k.bodyCellTexts.first == "=")
    }

    // MARK: - Without a table

    @Test("a dash underline with no delimiter row is a setext heading")
    func plainSetextHeading() {
        let k = kinds("r\n-")
        #expect(k.hasHeading && !k.hasTable)
    }

    @Test("a header + delimiter with no third line is a table")
    func bareTable() {
        let k = kinds("r\n|-")
        #expect(k.hasTable && !k.hasHeading)
    }
}
