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
/// paragraph, while `:-` would open a table under the paragraph's last line. A paragraph of 40,000 lines of `-:-`
/// parses well within the time limit.
@Suite("Paragraph lines shaped like delimiter rows")
struct DelimiterShapedParagraphLineTests {
    struct Shape: Sendable, CustomTestStringConvertible {
        let prefix: String
        let line: String
        /// `line` with `:-`, a delimiter row, in place of `-:-`.
        let delimiterRow: String
        /// The tree of `prefix` followed by two lines.
        let twoLines: String
        /// The tree of `prefix` followed by `delimiterRow`.
        let table: String
        /// The tree of `prefix` alone, which each line extends by `continuation`.
        let paragraph: String
        let continuation: String
        let testDescription: String
    }

    private static let longLine = String(repeating: "a", count: 4000)

    static let shapes: [Shape] = [
        Shape(
            prefix: "> a\n",
            line: "> -:-\n",
            delimiterRow: "> :-\n",
            twoLines: """
                document
                  block_quote
                    paragraph
                      text "a"
                      softbreak
                      text "-:-"
                      softbreak
                      text "-:-"

                """,
            table: """
                document
                  block_quote
                    table
                      table_header
                        table_cell align=left colspan=1 rowspan=1
                          text "a"

                """,
            paragraph: """
                document
                  block_quote
                    paragraph
                      text "a"

                """,
            continuation: """
                      softbreak
                      text "-:-"

                """,
            testDescription: "block quote"
        ),
        Shape(
            prefix: "a\r\n",
            line: "-:-\r\n",
            delimiterRow: ":-\r\n",
            twoLines: """
                document
                  paragraph
                    text "a"
                    softbreak
                    text "-:-"
                    softbreak
                    text "-:-"

                """,
            table: """
                document
                  table
                    table_header
                      table_cell align=left colspan=1 rowspan=1
                        text "a"

                """,
            paragraph: """
                document
                  paragraph
                    text "a"

                """,
            continuation: """
                    softbreak
                    text "-:-"

                """,
            testDescription: "CRLF"
        ),
        Shape(
            prefix: "> a\n>\t\tb\n",
            line: "> -:-\n",
            delimiterRow: "> :-\n",
            twoLines: """
                document
                  block_quote
                    paragraph
                      text "a"
                      softbreak
                      text "b"
                      softbreak
                      text "-:-"
                      softbreak
                      text "-:-"

                """,
            table: """
                document
                  block_quote
                    paragraph
                      text "a"
                    table
                      table_header
                        table_cell align=left colspan=1 rowspan=1
                          text "b"

                """,
            paragraph: """
                document
                  block_quote
                    paragraph
                      text "a"
                      softbreak
                      text "b"

                """,
            continuation: """
                      softbreak
                      text "-:-"

                """,
            testDescription: "block quote after a tab-indented line"
        ),
        Shape(
            prefix: "> \(longLine)\n",
            line: "> -:-\n",
            delimiterRow: "> :-\n",
            twoLines: """
                document
                  block_quote
                    paragraph
                      text "\(longLine)"
                      softbreak
                      text "-:-"
                      softbreak
                      text "-:-"

                """,
            table: """
                document
                  block_quote
                    table
                      table_header
                        table_cell align=left colspan=1 rowspan=1
                          text "\(longLine)"

                """,
            paragraph: """
                document
                  block_quote
                    paragraph
                      text "\(longLine)"

                """,
            continuation: """
                      softbreak
                      text "-:-"

                """,
            testDescription: "block quote after a long line"
        ),
    ]

    @Test(arguments: shapes)
    func linesContinueParagraph(_ shape: Shape) {
        #expect(TreeDump.dump(shape.prefix + shape.line + shape.line, options: .tables) == shape.twoLines)
    }

    @Test(arguments: shapes)
    func delimiterRowOpensTable(_ shape: Shape) {
        #expect(TreeDump.dump(shape.prefix + shape.delimiterRow, options: .tables) == shape.table)
    }

    @Test(.timeLimit(.minutes(1)), arguments: shapes)
    func manyLinesContinueParagraph(_ shape: Shape) {
        let source = shape.prefix + String(repeating: shape.line, count: 40_000)
        let tree = shape.paragraph + String(repeating: shape.continuation, count: 40_000)
        #expect(TreeDump.dump(source, options: .tables) == tree)
    }
}
