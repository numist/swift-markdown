/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Paragraph lines after a header row and delimiter row whose cell counts differ.
///
/// The header row must match the delimiter row in the number of cells, or a table is not recognized there (Tables
/// (extension)), and both lines continue the paragraph. A later line pair that is a valid header row and delimiter row
/// still opens a table, taking the line before the delimiter row as its header row, and the lines before it stay a
/// paragraph. A later pair whose cell counts also differ, a later line that is not a delimiter row, and a delimiter row
/// that is a lazy continuation line or is indented four or more columns open no table. Each case is tried at the top
/// level, in a block quote and in a list item.
@Suite("A table after a header row and delimiter row that differ in cell count")
struct TableAfterHeaderCellCountMismatchTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let expected: String

        init(_ name: String, _ source: String, _ expected: String) {
            self.name = name
            self.source = source
            self.expected = expected
        }

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            "top level, two mismatched pairs before a valid pair",
            "a|b|c\n-|-\np|q\n-|-|-\nd|e\n-|-\n",
            """
            document @1:1-6:4
              paragraph @1:1-4:6
                text "a|b|c" @1:1-1:6
                softbreak @-
                text "-|-" @2:1-2:4
                softbreak @-
                text "p|q" @3:1-3:4
                softbreak @-
                text "-|-|-" @4:1-4:6
              table @5:1-6:4
                table_header @5:1-5:4
                  table_cell align=none colspan=1 rowspan=1 @5:1-5:2
                    text "d" @5:1-5:2
                  table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                    text "e" @5:3-5:4

            """
        ),
        Case(
            "block quote, two mismatched pairs before a valid pair",
            "> a|b|c\n> -|-\n> p|q\n> -|-|-\n> d|e\n> -|-\n",
            """
            document @1:1-6:6
              block_quote @1:1-6:6
                paragraph @1:3-4:8
                  text "a|b|c" @1:3-1:8
                  softbreak @-
                  text "-|-" @2:3-2:6
                  softbreak @-
                  text "p|q" @3:3-3:6
                  softbreak @-
                  text "-|-|-" @4:3-4:8
                table @5:3-6:6
                  table_header @5:3-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                      text "d" @5:3-5:4
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "e" @5:5-5:6

            """
        ),
        Case(
            "list item, two mismatched pairs before a valid pair",
            "- a|b|c\n  -|-\n  p|q\n  -|-|-\n  d|e\n  -|-\n",
            """
            document @1:1-6:6
              list bullet '-' tight @1:1-6:6
                item @1:1-6:6
                  paragraph @1:3-4:8
                    text "a|b|c" @1:3-1:8
                    softbreak @-
                    text "-|-" @2:3-2:6
                    softbreak @-
                    text "p|q" @3:3-3:6
                    softbreak @-
                    text "-|-|-" @4:3-4:8
                  table @5:3-6:6
                    table_header @5:3-5:6
                      table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                        text "d" @5:3-5:4
                      table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                        text "e" @5:5-5:6

            """
        ),
        Case(
            "top level, the mismatched delimiter row is the header row of a valid pair",
            "a|b\n-|-|-\n-|-|-\n",
            """
            document @1:1-3:6
              paragraph @1:1-1:4
                text "a|b" @1:1-1:4
              table @2:1-3:6
                table_header @2:1-2:6
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "-" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "-" @2:3-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                    text "-" @2:5-2:6

            """
        ),
        Case(
            "block quote, the mismatched delimiter row is the header row of a valid pair",
            "> a|b\n> -|-|-\n> -|-|-\n",
            """
            document @1:1-3:8
              block_quote @1:1-3:8
                paragraph @1:3-1:6
                  text "a|b" @1:3-1:6
                table @2:3-3:8
                  table_header @2:3-2:8
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "-" @2:3-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                      text "-" @2:5-2:6
                    table_cell align=none colspan=1 rowspan=1 @2:7-2:8
                      text "-" @2:7-2:8

            """
        ),
        Case(
            "list item, the mismatched delimiter row is the header row of a valid pair",
            "- a|b\n  -|-|-\n  -|-|-\n",
            """
            document @1:1-3:8
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:6
                    text "a|b" @1:3-1:6
                  table @2:3-3:8
                    table_header @2:3-2:8
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "-" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "-" @2:5-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:7-2:8
                        text "-" @2:7-2:8

            """
        ),
        Case(
            "top level, a valid pair after a mismatched pair, with data rows",
            "x\na|b|c\n-|-\nd|e\n-|-\nf|g\nh\n",
            """
            document @1:1-7:2
              paragraph @1:1-3:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
              table @4:1-7:2
                table_header @4:1-4:4
                  table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                    text "d" @4:1-4:2
                  table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                    text "e" @4:3-4:4
                table_row @6:1-6:4
                  table_cell align=none colspan=1 rowspan=1 @6:1-6:2
                    text "f" @6:1-6:2
                  table_cell align=none colspan=1 rowspan=1 @6:3-6:4
                    text "g" @6:3-6:4
                table_row @7:1-7:2
                  table_cell align=none colspan=1 rowspan=1 @7:1-7:2
                    text "h" @7:1-7:2
                  table_cell align=none colspan=1 rowspan=1 @-

            """
        ),
        Case(
            "block quote, a valid pair after a mismatched pair, with data rows",
            "> x\n> a|b|c\n> -|-\n> d|e\n> -|-\n> f|g\n> h\n",
            """
            document @1:1-7:4
              block_quote @1:1-7:4
                paragraph @1:3-3:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                table @4:3-7:4
                  table_header @4:3-4:6
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "d" @4:3-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                      text "e" @4:5-4:6
                  table_row @6:3-6:6
                    table_cell align=none colspan=1 rowspan=1 @6:3-6:4
                      text "f" @6:3-6:4
                    table_cell align=none colspan=1 rowspan=1 @6:5-6:6
                      text "g" @6:5-6:6
                  table_row @7:3-7:4
                    table_cell align=none colspan=1 rowspan=1 @7:3-7:4
                      text "h" @7:3-7:4
                    table_cell align=none colspan=1 rowspan=1 @-

            """
        ),
        Case(
            "list item, a valid pair after a mismatched pair, with data rows",
            "- x\n  a|b|c\n  -|-\n  d|e\n  -|-\n  f|g\n  h\n",
            """
            document @1:1-7:4
              list bullet '-' tight @1:1-7:4
                item @1:1-7:4
                  paragraph @1:3-3:6
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b|c" @2:3-2:8
                    softbreak @-
                    text "-|-" @3:3-3:6
                  table @4:3-7:4
                    table_header @4:3-4:6
                      table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                        text "d" @4:3-4:4
                      table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                        text "e" @4:5-4:6
                    table_row @6:3-6:6
                      table_cell align=none colspan=1 rowspan=1 @6:3-6:4
                        text "f" @6:3-6:4
                      table_cell align=none colspan=1 rowspan=1 @6:5-6:6
                        text "g" @6:5-6:6
                    table_row @7:3-7:4
                      table_cell align=none colspan=1 rowspan=1 @7:3-7:4
                        text "h" @7:3-7:4
                      table_cell align=none colspan=1 rowspan=1 @-

            """
        ),
        Case(
            "top level, the later pair also differs in cell count",
            "x\na|b|c\n-|-\nd|e|f|g\n-|-\n",
            """
            document @1:1-5:4
              paragraph @1:1-5:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
                softbreak @-
                text "d|e|f|g" @4:1-4:8
                softbreak @-
                text "-|-" @5:1-5:4

            """
        ),
        Case(
            "block quote, the later pair also differs in cell count",
            "> x\n> a|b|c\n> -|-\n> d|e|f|g\n> -|-\n",
            """
            document @1:1-5:6
              block_quote @1:1-5:6
                paragraph @1:3-5:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                  softbreak @-
                  text "d|e|f|g" @4:3-4:10
                  softbreak @-
                  text "-|-" @5:3-5:6

            """
        ),
        Case(
            "list item, the later pair also differs in cell count",
            "- x\n  a|b|c\n  -|-\n  d|e|f|g\n  -|-\n",
            """
            document @1:1-5:6
              list bullet '-' tight @1:1-5:6
                item @1:1-5:6
                  paragraph @1:3-5:6
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b|c" @2:3-2:8
                    softbreak @-
                    text "-|-" @3:3-3:6
                    softbreak @-
                    text "d|e|f|g" @4:3-4:10
                    softbreak @-
                    text "-|-" @5:3-5:6

            """
        ),
        Case(
            "top level, the later line is not a delimiter row",
            "x\na|b|c\n-|-\nd|e\nf|g\n",
            """
            document @1:1-5:4
              paragraph @1:1-5:4
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
                softbreak @-
                text "d|e" @4:1-4:4
                softbreak @-
                text "f|g" @5:1-5:4

            """
        ),
        Case(
            "block quote, the later line is not a delimiter row",
            "> x\n> a|b|c\n> -|-\n> d|e\n> f|g\n",
            """
            document @1:1-5:6
              block_quote @1:1-5:6
                paragraph @1:3-5:6
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                  softbreak @-
                  text "d|e" @4:3-4:6
                  softbreak @-
                  text "f|g" @5:3-5:6

            """
        ),
        Case(
            "list item, the later line is not a delimiter row",
            "- x\n  a|b|c\n  -|-\n  d|e\n  f|g\n",
            """
            document @1:1-5:6
              list bullet '-' tight @1:1-5:6
                item @1:1-5:6
                  paragraph @1:3-5:6
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b|c" @2:3-2:8
                    softbreak @-
                    text "-|-" @3:3-3:6
                    softbreak @-
                    text "d|e" @4:3-4:6
                    softbreak @-
                    text "f|g" @5:3-5:6

            """
        ),
        Case(
            "top level, the later delimiter row is indented four columns",
            "x\na|b|c\n-|-\nd|e\n    -|-\n",
            """
            document @1:1-5:8
              paragraph @1:1-5:8
                text "x" @1:1-1:2
                softbreak @-
                text "a|b|c" @2:1-2:6
                softbreak @-
                text "-|-" @3:1-3:4
                softbreak @-
                text "d|e" @4:1-4:4
                softbreak @-
                text "-|-" @5:5-5:8

            """
        ),
        Case(
            "block quote, the later delimiter row is indented four columns",
            "> x\n> a|b|c\n> -|-\n> d|e\n>     -|-\n",
            """
            document @1:1-5:10
              block_quote @1:1-5:10
                paragraph @1:3-5:10
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b|c" @2:3-2:8
                  softbreak @-
                  text "-|-" @3:3-3:6
                  softbreak @-
                  text "d|e" @4:3-4:6
                  softbreak @-
                  text "-|-" @5:7-5:10

            """
        ),
        Case(
            "list item, the later delimiter row is indented four columns",
            "- x\n  a|b|c\n  -|-\n  d|e\n      -|-\n",
            """
            document @1:1-5:10
              list bullet '-' tight @1:1-5:10
                item @1:1-5:10
                  paragraph @1:3-5:10
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b|c" @2:3-2:8
                    softbreak @-
                    text "-|-" @3:3-3:6
                    softbreak @-
                    text "d|e" @4:3-4:6
                    softbreak @-
                    text "-|-" @5:7-5:10

            """
        ),
        Case(
            "block quote, the later delimiter row is a lazy continuation line",
            "> a|b|c\n> -|-\n> d|e\n-|-\n",
            """
            document @1:1-4:4
              block_quote @1:1-4:4
                paragraph @1:3-4:4
                  text "a|b|c" @1:3-1:8
                  softbreak @-
                  text "-|-" @2:3-2:6
                  softbreak @-
                  text "d|e" @3:3-3:6
                  softbreak @-
                  text "-|-" @4:1-4:4

            """
        ),
        Case(
            "list item, the later delimiter row is a lazy continuation line",
            "- a|b|c\n  -|-\n  d|e\n-|-\n",
            """
            document @1:1-4:4
              list bullet '-' tight @1:1-4:4
                item @1:1-4:4
                  paragraph @1:3-4:4
                    text "a|b|c" @1:3-1:8
                    softbreak @-
                    text "-|-" @2:3-2:6
                    softbreak @-
                    text "d|e" @3:3-3:6
                    softbreak @-
                    text "-|-" @4:1-4:4

            """
        ),
        Case(
            "a header row with more cells than its delimiter row, then a body-like row",
            "| abc | def |\n| --- |\n| bar |\n",
            """
            document @1:1-3:8
              paragraph @1:1-3:8
                text "| abc | def |" @1:1-1:14
                softbreak @-
                text "| --- |" @2:1-2:8
                softbreak @-
                text "| bar |" @3:1-3:8

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.tables, .sourcePosition], sourceRanges: true) == c.expected)
    }
}
