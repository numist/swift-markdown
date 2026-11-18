/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

// A table row holds at most 65,534 cells, counting every cell its line splits into, empty cells and span fillers
// included, before a body row is cut to the header's width. Once the body rows before a row have had more than 524,288
// empty cells inserted, that row ends the table.
struct TableLimitTests {

    private func row(_ cells: Int, _ text: String) -> String {
        "|" + Array(repeating: text, count: cells).joined(separator: "|") + "|"
    }

    private func header(_ columns: Int) -> String {
        row(columns, "a") + "\n" + row(columns, "-") + "\n"
    }

    private func tree(_ markdown: String) -> String {
        tableSummary(Document(parsing: markdown))
    }

    @Test("a header and delimiter row of 65,534 cells open a table")
    func headerOf65534Cells() {
        #expect(tree(row(65_534, "a") + "\n" + row(65_534, "-")) == """
            Document
              Table alignments: - ×65534 @1:1-2:131070
                Head
                  Cell ×65534
                    Text "a"
                Body
            """)
    }

    @Test("a header and delimiter row of 65,535 cells are a paragraph")
    func headerOf65535Cells() {
        #expect(tree(row(65_535, "a") + "\n" + row(65_535, "-")) == """
            Document
              Paragraph @1:1-2:131072
                Text "|a|a|a|a|a…" 131071 bytes
                SoftBreak
                Text "|-|-|-|-|-…" 131071 bytes
            """)
    }

    @Test("a body row of 65,534 cells is a row")
    func bodyRowOf65534Cells() {
        #expect(tree("|a|\n|-|\n" + row(65_534, "b") + "\n|c|") == """
            Document
              Table alignments: |-| @1:1-4:4
                Head
                  Cell
                    Text "a"
                Body
                  Row
                    Cell
                      Text "b"
                  Row
                    Cell
                      Text "c"
            """)
    }

    @Test("a body row of 65,535 cells ends the table and starts a paragraph")
    func bodyRowOf65535Cells() {
        #expect(tree("|a|\n|-|\n" + row(65_535, "b") + "\n|c|") == """
            Document
              Table alignments: |-| @1:1-2:4
                Head
                  Cell
                    Text "a"
                Body
              Paragraph @3:1-4:4
                Text "|b|b|b|b|b…" 131071 bytes
                SoftBreak
                Text "|c|"
            """)
    }

    @Test("a body row of 65,534 empty cells is a row")
    func bodyRowOf65534EmptyCells() {
        #expect(tree("a\n|-\n" + String(repeating: "|", count: 65_535) + "\nc") == """
            Document
              Table alignments: |-| @1:1-4:2
                Head
                  Cell
                    Text "a"
                Body
                  Row
                    Cell colspan: 0
                  Row
                    Cell
                      Text "c"
            """)
    }

    @Test("a body row of 65,535 empty cells ends the table")
    func bodyRowOf65535EmptyCells() {
        #expect(tree("a\n|-\n" + String(repeating: "|", count: 65_536) + "\nc") == """
            Document
              Table alignments: |-| @1:1-2:3
                Head
                  Cell
                    Text "a"
                Body
              Paragraph @3:1-4:2
                Text "||||||||||…" 65536 bytes
                SoftBreak
                Text "c"
            """)
    }

    @Test("a body row of a cell and 65,533 rowspan fillers is a row")
    func bodyRowOf65534RowspanCells() {
        #expect(tree("a\n|-\nc" + String(repeating: "|^", count: 65_533) + "\nd") == """
            Document
              Table alignments: |-| @1:1-4:2
                Head
                  Cell
                    Text "a"
                Body
                  Row
                    Cell
                      Text "c"
                  Row
                    Cell
                      Text "d"
            """)
    }

    @Test("a body row of a cell and 65,534 rowspan fillers ends the table")
    func bodyRowOf65535RowspanCells() {
        #expect(tree("a\n|-\nc" + String(repeating: "|^", count: 65_534) + "\nd") == """
            Document
              Table alignments: |-| @1:1-2:3
                Head
                  Cell
                    Text "a"
                Body
              Paragraph @3:1-4:2
                Text "c|^|^|^|^|…" 131069 bytes
                SoftBreak
                Text "d"
            """)
    }

    @Test("a quoted body row of 65,534 cells is a row")
    func quotedBodyRowOf65534Cells() {
        #expect(tree("> a\n> |-\n> " + row(65_534, "b") + "\n> c") == """
            Document
              BlockQuote @1:1-4:4
                Table alignments: |-|
                  Head
                    Cell
                      Text "a"
                  Body
                    Row
                      Cell
                        Text "b"
                    Row
                      Cell
                        Text "c"
            """)
    }

    @Test("a quoted body row of 65,535 cells ends the table")
    func quotedBodyRowOf65535Cells() {
        #expect(tree("> a\n> |-\n> " + row(65_535, "b") + "\n> c") == """
            Document
              BlockQuote @1:1-4:4
                Table alignments: |-|
                  Head
                    Cell
                      Text "a"
                  Body
                Paragraph
                  Text "|b|b|b|b|b…" 131071 bytes
                  SoftBreak
                  Text "c"
            """)
    }

    @Test("a paragraph line of 65,534 cells above the header leaves the table")
    func precedingLineOf65534Cells() {
        #expect(tree(row(65_534, "w") + "\na|b\n-|-") == """
            Document
              Paragraph @1:1-1:131070
                Text "|w|w|w|w|w…" 131069 bytes
              Table alignments: |-|-| @2:1-3:4
                Head
                  Cell
                    Text "a"
                  Cell
                    Text "b"
                Body
            """)
    }

    @Test("a paragraph line of 65,535 cells above the header leaves a paragraph")
    func precedingLineOf65535Cells() {
        #expect(tree(row(65_535, "w") + "\na|b\n-|-") == """
            Document
              Paragraph @1:1-3:4
                Text "|w|w|w|w|w…" 131071 bytes
                SoftBreak
                Text "a|b"
                SoftBreak
                Text "-|-"
            """)
    }

    @Test("a paragraph line of 65,534 cells two lines above the header leaves the table")
    func farPrecedingLineOf65534Cells() {
        #expect(tree(row(65_534, "w") + "\nx\na|b\n-|-\nc\n-|-") == """
            Document
              Paragraph @1:1-2:2
                Text "|w|w|w|w|w…" 131069 bytes
                SoftBreak
                Text "x"
              Table alignments: |-|-| @3:1-6:4
                Head
                  Cell
                    Text "a"
                  Cell
                    Text "b"
                Body
                  Row
                    Cell
                      Text "c"
                    Cell
                  Row
                    Cell ×2
                      Text "-"
            """)
    }

    @Test("a paragraph line of 65,535 cells keeps every later delimiter row of the paragraph from opening a table")
    func farPrecedingLineOf65535Cells() {
        #expect(tree(row(65_535, "w") + "\nx\na|b\n-|-\nc\n-|-") == """
            Document
              Paragraph @1:1-6:4
                Text "|w|w|w|w|w…" 131071 bytes
                SoftBreak
                Text "x"
                SoftBreak
                Text "a|b"
                SoftBreak
                Text "-|-"
                SoftBreak
                Text "c"
                SoftBreak
                Text "-|-"
            """)
    }

    @Test("a lazy paragraph line of 65,534 cells above a quoted header leaves the table")
    func lazyPrecedingLineOf65534Cells() {
        #expect(tree("> x\n" + row(65_534, "w") + "\n> a|b\n> -|-") == """
            Document
              BlockQuote @1:1-4:6
                Paragraph
                  Text "x"
                  SoftBreak
                  Text "|w|w|w|w|w…" 131069 bytes
                Table alignments: |-|-|
                  Head
                    Cell
                      Text "a"
                    Cell
                      Text "b"
                  Body
            """)
    }

    @Test("a lazy paragraph line of 65,535 cells above a quoted header leaves a paragraph")
    func lazyPrecedingLineOf65535Cells() {
        #expect(tree("> x\n" + row(65_535, "w") + "\n> a|b\n> -|-") == """
            Document
              BlockQuote @1:1-4:6
                Paragraph
                  Text "x"
                  SoftBreak
                  Text "|w|w|w|w|w…" 131071 bytes
                  SoftBreak
                  Text "a|b"
                  SoftBreak
                  Text "-|-"
            """)
    }

    @Test("a delimiter-shaped paragraph line of 65,535 cells keeps a later delimiter row from opening a table")
    func delimiterShapedLineOf65535Cells() {
        #expect(tree("a|b\n" + row(65_535, "-") + "\nc|d\n-|-") == """
            Document
              Paragraph @1:1-4:4
                Text "a|b"
                SoftBreak
                Text "|-|-|-|-|-…" 131071 bytes
                SoftBreak
                Text "c|d"
                SoftBreak
                Text "-|-"
            """)
    }

    @Test("a line of 65,535 cells in an earlier paragraph leaves the table")
    func lineOf65535CellsInEarlierParagraph() {
        #expect(tree(row(65_535, "w") + "\n\na|b\n-|-") == """
            Document
              Paragraph @1:1-1:131072
                Text "|w|w|w|w|w…" 131071 bytes
              Table alignments: |-|-| @3:1-4:4
                Head
                  Cell
                    Text "a"
                  Cell
                    Text "b"
                Body
            """)
    }

    @Test("525 one-cell body rows of a 1000-column table insert 524,475 cells, so the next row ends the table")
    func rowAfter524475InsertedCells() {
        #expect(tree(header(1000) + String(repeating: "x\n", count: 525) + "y") == """
            Document
              Table alignments: - ×1000 @1:1-527:2
                Head
                  Cell ×1000
                    Text "a"
                Body
                  Row ×525
                    Cell
                      Text "x"
                    Cell ×999
              Paragraph @528:1-528:2
                Text "y"
            """)
    }

    @Test("a 526th one-cell body row of a 1000-column table ends the table")
    func rowAfter525OneCellRows() {
        #expect(tree(header(1000) + String(repeating: "x\n", count: 526) + "y") == """
            Document
              Table alignments: - ×1000 @1:1-527:2
                Head
                  Cell ×1000
                    Text "a"
                Body
                  Row ×525
                    Cell
                      Text "x"
                    Cell ×999
              Paragraph @528:1-529:2
                Text "x"
                SoftBreak
                Text "y"
            """)
    }

    @Test("the paragraph a refused body row starts can be a setext heading")
    func refusedRowUnderlined() {
        #expect(tree(header(1000) + String(repeating: "x\n", count: 526) + "-") == """
            Document
              Table alignments: - ×1000 @1:1-527:2
                Head
                  Cell ×1000
                    Text "a"
                Body
                  Row ×525
                    Cell
                      Text "x"
                    Cell ×999
              Heading level: 2 @528:1-529:2
                Text "x"
            """)
    }

    @Test("a row wider than the table inserts no cells and takes none away")
    func widerRowAddsNone() {
        #expect(tree(header(1000) + row(2000, "v") + "\n" + String(repeating: "x\n", count: 526) + "y") == """
            Document
              Table alignments: - ×1000 @1:1-528:2
                Head
                  Cell ×1000
                    Text "a"
                Body
                  Row
                    Cell ×1000
                      Text "v"
                  Row ×525
                    Cell
                      Text "x"
                    Cell ×999
              Paragraph @529:1-530:2
                Text "x"
                SoftBreak
                Text "y"
            """)
    }

    @Test("a body row after rows that inserted 524,288 cells is a row")
    func rowAfter524288InsertedCells() {
        #expect(tree(header(1025) + String(repeating: "x\n", count: 512) + row(1025, "z") + "\ny\nw") == """
            Document
              Table alignments: - ×1025 @1:1-516:2
                Head
                  Cell ×1025
                    Text "a"
                Body
                  Row ×512
                    Cell
                      Text "x"
                    Cell ×1024
                  Row
                    Cell ×1025
                      Text "z"
                  Row
                    Cell
                      Text "y"
                    Cell ×1024
              Paragraph @517:1-517:2
                Text "w"
            """)
    }

    @Test("a body row after rows that inserted 524,289 cells ends the table")
    func rowAfter524289InsertedCells() {
        #expect(tree(header(1025) + String(repeating: "x\n", count: 512) + row(1024, "z") + "\ny\nw") == """
            Document
              Table alignments: - ×1025 @1:1-515:2050
                Head
                  Cell ×1025
                    Text "a"
                Body
                  Row ×512
                    Cell
                      Text "x"
                    Cell ×1024
                  Row
                    Cell ×1024
                      Text "z"
                    Cell
              Paragraph @516:1-517:2
                Text "y"
                SoftBreak
                Text "w"
            """)
    }

}

private func tableSummary(_ markup: Markup) -> String {
    var lines: [String] = []
    appendSummary(of: markup, depth: 0, into: &lines)
    return lines.joined(separator: "\n")
}

private func appendSummary(of markup: Markup, depth: Int, into lines: inout [String]) {
    var line = String(repeating: "  ", count: depth) + nodeLine(markup)
    if depth == 1, let range = markup.range {
        line += " @\(range.lowerBound.line):\(range.lowerBound.column)-\(range.upperBound.line):\(range.upperBound.column)"
    }
    lines.append(line)
    var previous: [String]? = nil
    var count = 0
    func flush() {
        guard var run = previous else { return }
        if count > 1 {
            run[0] += " ×\(count)"
        }
        lines += run
    }
    for child in markup.children {
        var childLines: [String] = []
        appendSummary(of: child, depth: depth + 1, into: &childLines)
        if childLines == previous {
            count += 1
        } else {
            flush()
            previous = childLines
            count = 1
        }
    }
    flush()
}

private func nodeLine(_ markup: Markup) -> String {
    switch markup {
    case let text as Text:
        let string = text.string
        guard string.count > 20 else {
            return "Text \"\(string)\""
        }
        return "Text \"\(string.prefix(10))…\" \(string.utf8.count) bytes"
    case is SoftBreak: return "SoftBreak"
    case is Paragraph: return "Paragraph"
    case is Document: return "Document"
    case is BlockQuote: return "BlockQuote"
    case let heading as Heading: return "Heading level: \(heading.level)"
    case let table as Table:
        let alignments = table.columnAlignments.map { alignment -> String in
            switch alignment {
            case .left: "l"
            case .right: "r"
            case .center: "c"
            case nil: "-"
            }
        }
        guard alignments.count > 8 else {
            return "Table alignments: |" + alignments.joined(separator: "|") + "|"
        }
        var runs: [(alignment: String, count: Int)] = []
        for alignment in alignments {
            if runs.last?.alignment == alignment {
                runs[runs.count - 1].count += 1
            } else {
                runs.append((alignment, 1))
            }
        }
        return "Table alignments: " + runs.map { "\($0.alignment) ×\($0.count)" }.joined(separator: ", ")
    case is Table.Head: return "Head"
    case is Table.Body: return "Body"
    case is Table.Row: return "Row"
    case let cell as Table.Cell:
        var line = "Cell"
        if cell.colspan != 1 { line += " colspan: \(cell.colspan)" }
        if cell.rowspan != 1 { line += " rowspan: \(cell.rowspan)" }
        return line
    default: return String(describing: type(of: markup))
    }
}
