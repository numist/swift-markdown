/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Paragraphs whose continuation lines all look like table delimiter rows but are not (Tables (extension)).
///
/// `-:-` is not a delimiter row, since a colon may only begin or end a cell's dashes, so each such line continues the
/// paragraph, while `:-` would open a table under the paragraph's last line. A paragraph of 40,000 lines of `-:-`, in a
/// block quote, after a tab-indented or long line, or with CRLF line endings, parses well within the time limit.
@Suite("Paragraph lines shaped like delimiter rows")
struct DelimiterShapedParagraphLineTests {
    struct Shape: Sendable, CustomTestStringConvertible {
        let prefix: String
        let line: String
        /// `line` with `:-`, a delimiter row, in place of `-:-`.
        let delimiterRow: String
        /// The tree of `prefix` followed by `count` lines.
        let tree: @Sendable (_ count: Int) -> String
        /// The tree of `prefix` followed by `delimiterRow`.
        let table: String
        let testDescription: String

        func source(count: Int) -> String {
            prefix + String(repeating: line, count: count)
        }

        var tableSource: String {
            prefix + delimiterRow
        }
    }

    private static let longLine = String(repeating: "a", count: 4000)

    /// The trees of `count` continuation lines of `-:-`, indented by `indent`.
    private static func continuationLineTrees(_ count: Int, indent: String) -> String {
        String(repeating: "\(indent)softbreak\n\(indent)text \"-:-\"\n", count: count)
    }

    private static func headerTree(_ header: String, indent: String) -> String {
        """
        \(indent)table
        \(indent)  table_header
        \(indent)    table_cell align=left colspan=1 rowspan=1
        \(indent)      text "\(header)"

        """
    }

    static let shapes: [Shape] = [
        Shape(prefix: "> a\n", line: "> -:-\n", delimiterRow: "> :-\n", tree: {
            "document\n  block_quote\n    paragraph\n      text \"a\"\n" + continuationLineTrees($0, indent: "      ")
        }, table: "document\n  block_quote\n" + headerTree("a", indent: "    "), testDescription: "block quote"),
        Shape(prefix: "a\r\n", line: "-:-\r\n", delimiterRow: ":-\r\n", tree: {
            "document\n  paragraph\n    text \"a\"\n" + continuationLineTrees($0, indent: "    ")
        }, table: "document\n" + headerTree("a", indent: "  "), testDescription: "CRLF"),
        Shape(prefix: "> a\n>\t\tb\n", line: "> -:-\n", delimiterRow: "> :-\n", tree: {
            "document\n  block_quote\n    paragraph\n      text \"a\"\n      softbreak\n      text \"b\"\n"
                + continuationLineTrees($0, indent: "      ")
        }, table: "document\n  block_quote\n    paragraph\n      text \"a\"\n" + headerTree("b", indent: "    "),
           testDescription: "block quote after a tab-indented line"),
        Shape(prefix: "> \(longLine)\n", line: "> -:-\n", delimiterRow: "> :-\n", tree: {
            "document\n  block_quote\n    paragraph\n      text \"\(longLine)\"\n" + continuationLineTrees($0, indent: "      ")
        }, table: "document\n  block_quote\n" + headerTree(longLine, indent: "    "), testDescription: "block quote after a long line"),
    ]

    @Test(arguments: shapes)
    func linesContinueParagraph(_ shape: Shape) {
        #expect(TreeDump.dump(shape.source(count: 2), options: .tables) == shape.tree(2))
    }

    @Test(arguments: shapes)
    func delimiterRowOpensTable(_ shape: Shape) {
        #expect(TreeDump.dump(shape.tableSource, options: .tables) == shape.table)
    }

    @Test(.timeLimit(.minutes(1)), arguments: shapes)
    func manyLinesContinueParagraph(_ shape: Shape) {
        #expect(TreeDump.dump(shape.source(count: 40_000), options: .tables) == shape.tree(40_000))
    }
}
