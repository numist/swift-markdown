/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Tables in containers whose rows are lazy continuation lines.
///
/// Per Block quotes and List items, a line that lacks an open container's continuation prefix can still continue a
/// paragraph in that container as a lazy continuation line, and a footnote definition's paragraph continues the same
/// way. The spec does not say whether a table's header row may be such a line. It may be one here, and the
/// paragraph's earlier lines stay a paragraph before the table in the container. The delimiter row and the data rows
/// cannot be lazy: a lazy delimiter row is paragraph text, and a lazy data row closes the table and its container and
/// starts a paragraph outside them. A row with only an enclosing container's prefix is lazy for the container inside
/// it. A line without a container's prefix that continues no paragraph opens its block outside the container, where
/// it can begin a table.
@Suite("A table's header row may be a lazy continuation line, but its delimiter and data rows may not")
struct TableLazyContinuationRowTests {

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
            "block quote, lazy header row",
            "> x\na|b\n> -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:1-3:6
                  table_header @2:1-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                      text "a" @2:1-2:2
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "b" @2:3-2:4

            """
        ),
        Case(
            "block quote, lazy delimiter row",
            "> a|b\n-|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "a|b" @1:3-1:6
                  softbreak @-
                  text "-|-" @2:1-2:4

            """
        ),
        Case(
            "block quote, lazy data row",
            "> a|b\n> -|-\nc|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "a" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "b" @1:5-1:6
              paragraph @3:1-3:4
                text "c|d" @3:1-3:4

            """
        ),
        Case(
            "block quote, prefixed data row",
            "> a|b\n> -|-\n> c|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:6
                table @1:3-3:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "a" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "b" @1:5-1:6
                  table_row @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "c" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "d" @3:5-3:6

            """
        ),
        Case(
            "block quote, lazy header row and lazy data row",
            "> x\na|b\n> -|-\nc|d\n",
            """
            document @1:1-5:1
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:1-3:6
                  table_header @2:1-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                      text "a" @2:1-2:2
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "b" @2:3-2:4
              paragraph @4:1-4:4
                text "c|d" @4:1-4:4

            """
        ),
        Case(
            "block quote, lazy header row and prefixed data row",
            "> x\na|b\n> -|-\n> c|d\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:6
                paragraph @1:3-1:4
                  text "x" @1:3-1:4
                table @2:1-4:6
                  table_header @2:1-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                      text "a" @2:1-2:2
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "b" @2:3-2:4
                  table_row @4:3-4:6
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "c" @4:3-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                      text "d" @4:5-4:6

            """
        ),
        Case(
            "block quote, lazy header row and lazy delimiter row",
            "> x\na|b\n-|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:4
                paragraph @1:3-3:4
                  text "x" @1:3-1:4
                  softbreak @-
                  text "a|b" @2:1-2:4
                  softbreak @-
                  text "-|-" @3:1-3:4

            """
        ),
        Case(
            "block quote, lazy line before a prefixed header row",
            "> x\ny\n> a|b\n> -|-\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:6
                paragraph @1:3-2:2
                  text "x" @1:3-1:4
                  softbreak @-
                  text "y" @2:1-2:2
                table @3:3-4:6
                  table_header @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "a" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "b" @3:5-3:6

            """
        ),
        Case(
            "bullet item, lazy header row",
            "- x\na|b\n  -|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:1-3:6
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4

            """
        ),
        Case(
            "bullet item, lazy delimiter row",
            "- a|b\n-|-\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  paragraph @1:3-2:4
                    text "a|b" @1:3-1:6
                    softbreak @-
                    text "-|-" @2:1-2:4

            """
        ),
        Case(
            "bullet item, lazy data row",
            "- a|b\n  -|-\nc|d\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  table @1:3-2:6
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "a" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "b" @1:5-1:6
              paragraph @3:1-3:4
                text "c|d" @3:1-3:4

            """
        ),
        Case(
            "bullet item, prefixed data row",
            "- a|b\n  -|-\n  c|d\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  table @1:3-3:6
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "a" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "b" @1:5-1:6
                    table_row @3:3-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                        text "c" @3:3-3:4
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "d" @3:5-3:6

            """
        ),
        Case(
            "bullet item, lazy header row and lazy data row",
            "- x\na|b\n  -|-\nc|d\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:1-3:6
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
              paragraph @4:1-4:4
                text "c|d" @4:1-4:4

            """
        ),
        Case(
            "bullet item, lazy header row and prefixed data row",
            "- x\na|b\n  -|-\n  c|d\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:6
                item @1:1-4:6
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:1-4:6
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
                    table_row @4:3-4:6
                      table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                        text "c" @4:3-4:4
                      table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                        text "d" @4:5-4:6

            """
        ),
        Case(
            "bullet item, lazy header row and lazy delimiter row",
            "- x\na|b\n-|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:4
                item @1:1-3:4
                  paragraph @1:3-3:4
                    text "x" @1:3-1:4
                    softbreak @-
                    text "a|b" @2:1-2:4
                    softbreak @-
                    text "-|-" @3:1-3:4

            """
        ),
        Case(
            "bullet item, lazy line before a prefixed header row",
            "- x\ny\n  a|b\n  -|-\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:6
                item @1:1-4:6
                  paragraph @1:3-2:2
                    text "x" @1:3-1:4
                    softbreak @-
                    text "y" @2:1-2:2
                  table @3:3-4:6
                    table_header @3:3-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                        text "a" @3:3-3:4
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "b" @3:5-3:6

            """
        ),
        Case(
            "ordered item, lazy header row",
            "1. x\na|b\n   -|-\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:7
                item @1:1-3:7
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5
                  table @2:1-3:7
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4

            """
        ),
        Case(
            "ordered item, prefixed header row",
            "1. x\n   a|b\n   -|-\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:7
                item @1:1-3:7
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5
                  table @2:4-3:7
                    table_header @2:4-2:7
                      table_cell align=none colspan=1 rowspan=1 @2:4-2:5
                        text "a" @2:4-2:5
                      table_cell align=none colspan=1 rowspan=1 @2:6-2:7
                        text "b" @2:6-2:7

            """
        ),
        Case(
            "ordered item, lazy delimiter row",
            "1. a|b\n-|-\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:4
                item @1:1-2:4
                  paragraph @1:4-2:4
                    text "a|b" @1:4-1:7
                    softbreak @-
                    text "-|-" @2:1-2:4

            """
        ),
        Case(
            "ordered item, prefixed delimiter row",
            "1. a|b\n   -|-\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:7
                item @1:1-2:7
                  table @1:4-2:7
                    table_header @1:4-1:7
                      table_cell align=none colspan=1 rowspan=1 @1:4-1:5
                        text "a" @1:4-1:5
                      table_cell align=none colspan=1 rowspan=1 @1:6-1:7
                        text "b" @1:6-1:7

            """
        ),
        Case(
            "ordered item, lazy data row",
            "1. a|b\n   -|-\nc|d\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-2:7
                item @1:1-2:7
                  table @1:4-2:7
                    table_header @1:4-1:7
                      table_cell align=none colspan=1 rowspan=1 @1:4-1:5
                        text "a" @1:4-1:5
                      table_cell align=none colspan=1 rowspan=1 @1:6-1:7
                        text "b" @1:6-1:7
              paragraph @3:1-3:4
                text "c|d" @3:1-3:4

            """
        ),
        Case(
            "ordered item, prefixed data row",
            "1. a|b\n   -|-\n   c|d\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:7
                item @1:1-3:7
                  table @1:4-3:7
                    table_header @1:4-1:7
                      table_cell align=none colspan=1 rowspan=1 @1:4-1:5
                        text "a" @1:4-1:5
                      table_cell align=none colspan=1 rowspan=1 @1:6-1:7
                        text "b" @1:6-1:7
                    table_row @3:4-3:7
                      table_cell align=none colspan=1 rowspan=1 @3:4-3:5
                        text "c" @3:4-3:5
                      table_cell align=none colspan=1 rowspan=1 @3:6-3:7
                        text "d" @3:6-3:7

            """
        ),
        Case(
            "ordered item, lazy header row and lazy data row",
            "1. x\na|b\n   -|-\nc|d\n",
            """
            document @1:1-5:1
              list ordered start=1 delim=period tight @1:1-3:7
                item @1:1-3:7
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5
                  table @2:1-3:7
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
              paragraph @4:1-4:4
                text "c|d" @4:1-4:4

            """
        ),
        Case(
            "ordered item, lazy header row and prefixed data row",
            "1. x\na|b\n   -|-\n   c|d\n",
            """
            document @1:1-5:1
              list ordered start=1 delim=period tight @1:1-4:7
                item @1:1-4:7
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5
                  table @2:1-4:7
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
                    table_row @4:4-4:7
                      table_cell align=none colspan=1 rowspan=1 @4:4-4:5
                        text "c" @4:4-4:5
                      table_cell align=none colspan=1 rowspan=1 @4:6-4:7
                        text "d" @4:6-4:7

            """
        ),
        Case(
            "ordered item, lazy header row and lazy delimiter row",
            "1. x\na|b\n-|-\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:4
                item @1:1-3:4
                  paragraph @1:4-3:4
                    text "x" @1:4-1:5
                    softbreak @-
                    text "a|b" @2:1-2:4
                    softbreak @-
                    text "-|-" @3:1-3:4

            """
        ),
        Case(
            "ordered item, lazy line before a prefixed header row",
            "1. x\ny\n   a|b\n   -|-\n",
            """
            document @1:1-5:1
              list ordered start=1 delim=period tight @1:1-4:7
                item @1:1-4:7
                  paragraph @1:4-2:2
                    text "x" @1:4-1:5
                    softbreak @-
                    text "y" @2:1-2:2
                  table @3:4-4:7
                    table_header @3:4-3:7
                      table_cell align=none colspan=1 rowspan=1 @3:4-3:5
                        text "a" @3:4-3:5
                      table_cell align=none colspan=1 rowspan=1 @3:6-3:7
                        text "b" @3:6-3:7

            """
        ),
        Case(
            "footnote definition, lazy header row",
            "[^a]\n\n[^a]: x\na|b\n    -|-\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                table @4:1-5:8
                  table_header @4:1-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                      text "a" @4:1-4:2
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "b" @4:3-4:4

            """
        ),
        Case(
            "footnote definition, prefixed header row",
            "[^a]\n\n[^a]: x\n    a|b\n    -|-\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                table @4:5-5:8
                  table_header @4:5-4:8
                    table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                      text "a" @4:5-4:6
                    table_cell align=none colspan=1 rowspan=1 @4:7-4:8
                      text "b" @4:7-4:8

            """
        ),
        Case(
            "footnote definition, lazy delimiter row",
            "[^a]\n\n[^a]: a|b\n-|-\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-4:4
                paragraph @3:7-4:4
                  text "a|b" @3:7-3:10
                  softbreak @-
                  text "-|-" @4:1-4:4

            """
        ),
        Case(
            "footnote definition, prefixed delimiter row",
            "[^a]\n\n[^a]: a|b\n    -|-\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-4:8
                table @3:7-4:8
                  table_header @3:7-3:10
                    table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                      text "a" @3:7-3:8
                    table_cell align=none colspan=1 rowspan=1 @3:9-3:10
                      text "b" @3:9-3:10

            """
        ),
        Case(
            "footnote definition, lazy data row",
            "[^a]\n\n[^a]: a|b\n    -|-\nc|d\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @5:1-5:4
                text "c|d" @5:1-5:4
              footnote_definition "a" @3:1-4:8
                table @3:7-4:8
                  table_header @3:7-3:10
                    table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                      text "a" @3:7-3:8
                    table_cell align=none colspan=1 rowspan=1 @3:9-3:10
                      text "b" @3:9-3:10

            """
        ),
        Case(
            "footnote definition, prefixed data row",
            "[^a]\n\n[^a]: a|b\n    -|-\n    c|d\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                table @3:7-5:8
                  table_header @3:7-3:10
                    table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                      text "a" @3:7-3:8
                    table_cell align=none colspan=1 rowspan=1 @3:9-3:10
                      text "b" @3:9-3:10
                  table_row @5:5-5:8
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "c" @5:5-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:7-5:8
                      text "d" @5:7-5:8

            """
        ),
        Case(
            "footnote definition, lazy header row and lazy data row",
            "[^a]\n\n[^a]: x\na|b\n    -|-\nc|d\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @6:1-6:4
                text "c|d" @6:1-6:4
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                table @4:1-5:8
                  table_header @4:1-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                      text "a" @4:1-4:2
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "b" @4:3-4:4

            """
        ),
        Case(
            "footnote definition, lazy header row and prefixed data row",
            "[^a]\n\n[^a]: x\na|b\n    -|-\n    c|d\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-6:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                table @4:1-6:8
                  table_header @4:1-4:4
                    table_cell align=none colspan=1 rowspan=1 @4:1-4:2
                      text "a" @4:1-4:2
                    table_cell align=none colspan=1 rowspan=1 @4:3-4:4
                      text "b" @4:3-4:4
                  table_row @6:5-6:8
                    table_cell align=none colspan=1 rowspan=1 @6:5-6:6
                      text "c" @6:5-6:6
                    table_cell align=none colspan=1 rowspan=1 @6:7-6:8
                      text "d" @6:7-6:8

            """
        ),
        Case(
            "footnote definition, lazy header row and lazy delimiter row",
            "[^a]\n\n[^a]: x\na|b\n-|-\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:4
                paragraph @3:7-5:4
                  text "x" @3:7-3:8
                  softbreak @-
                  text "a|b" @4:1-4:4
                  softbreak @-
                  text "-|-" @5:1-5:4

            """
        ),
        Case(
            "footnote definition, lazy line before a prefixed header row",
            "[^a]\n\n[^a]: x\ny\n    a|b\n    -|-\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-6:8
                paragraph @3:7-4:2
                  text "x" @3:7-3:8
                  softbreak @-
                  text "y" @4:1-4:2
                table @5:5-6:8
                  table_header @5:5-5:8
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "a" @5:5-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:7-5:8
                      text "b" @5:7-5:8

            """
        ),
        Case(
            "block quote in a block quote, lazy header row",
            "> > x\na|b\n> > -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                block_quote @1:3-3:8
                  paragraph @1:5-1:6
                    text "x" @1:5-1:6
                  table @2:1-3:8
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4

            """
        ),
        Case(
            "block quote in a block quote, prefixed header row",
            "> > x\n> > a|b\n> > -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                block_quote @1:3-3:8
                  paragraph @1:5-1:6
                    text "x" @1:5-1:6
                  table @2:5-3:8
                    table_header @2:5-2:8
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "a" @2:5-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:7-2:8
                        text "b" @2:7-2:8

            """
        ),
        Case(
            "block quote in a block quote, lazy delimiter row",
            "> > a|b\n-|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                block_quote @1:3-2:4
                  paragraph @1:5-2:4
                    text "a|b" @1:5-1:8
                    softbreak @-
                    text "-|-" @2:1-2:4

            """
        ),
        Case(
            "block quote in a block quote, prefixed delimiter row",
            "> > a|b\n> > -|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:8
                block_quote @1:3-2:8
                  table @1:5-2:8
                    table_header @1:5-1:8
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "a" @1:5-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                        text "b" @1:7-1:8

            """
        ),
        Case(
            "block quote in a block quote, lazy data row",
            "> > a|b\n> > -|-\nc|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-2:8
                block_quote @1:3-2:8
                  table @1:5-2:8
                    table_header @1:5-1:8
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "a" @1:5-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                        text "b" @1:7-1:8
              paragraph @3:1-3:4
                text "c|d" @3:1-3:4

            """
        ),
        Case(
            "block quote in a block quote, prefixed data row",
            "> > a|b\n> > -|-\n> > c|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                block_quote @1:3-3:8
                  table @1:5-3:8
                    table_header @1:5-1:8
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "a" @1:5-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                        text "b" @1:7-1:8
                    table_row @3:5-3:8
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "c" @3:5-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                        text "d" @3:7-3:8

            """
        ),
        Case(
            "block quote in a block quote, lazy header row and lazy data row",
            "> > x\na|b\n> > -|-\nc|d\n",
            """
            document @1:1-5:1
              block_quote @1:1-3:8
                block_quote @1:3-3:8
                  paragraph @1:5-1:6
                    text "x" @1:5-1:6
                  table @2:1-3:8
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
              paragraph @4:1-4:4
                text "c|d" @4:1-4:4

            """
        ),
        Case(
            "block quote in a block quote, lazy header row and prefixed data row",
            "> > x\na|b\n> > -|-\n> > c|d\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:8
                block_quote @1:3-4:8
                  paragraph @1:5-1:6
                    text "x" @1:5-1:6
                  table @2:1-4:8
                    table_header @2:1-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                        text "a" @2:1-2:2
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
                    table_row @4:5-4:8
                      table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                        text "c" @4:5-4:6
                      table_cell align=none colspan=1 rowspan=1 @4:7-4:8
                        text "d" @4:7-4:8

            """
        ),
        Case(
            "block quote in a block quote, lazy header row and lazy delimiter row",
            "> > x\na|b\n-|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:4
                block_quote @1:3-3:4
                  paragraph @1:5-3:4
                    text "x" @1:5-1:6
                    softbreak @-
                    text "a|b" @2:1-2:4
                    softbreak @-
                    text "-|-" @3:1-3:4

            """
        ),
        Case(
            "block quote in a block quote, lazy line before a prefixed header row",
            "> > x\ny\n> > a|b\n> > -|-\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:8
                block_quote @1:3-4:8
                  paragraph @1:5-2:2
                    text "x" @1:5-1:6
                    softbreak @-
                    text "y" @2:1-2:2
                  table @3:5-4:8
                    table_header @3:5-3:8
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "a" @3:5-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                        text "b" @3:7-3:8

            """
        ),
        Case(
            "block quote in a block quote, header row with only the outer prefix",
            "> > x\n> a|b\n> > -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                block_quote @1:3-3:8
                  paragraph @1:5-1:6
                    text "x" @1:5-1:6
                  table @2:3-3:8
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "a" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "b" @2:5-2:6

            """
        ),
        Case(
            "block quote in a block quote, delimiter row with only the outer prefix",
            "> > a|b\n> -|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:6
                block_quote @1:3-2:6
                  paragraph @1:5-2:6
                    text "a|b" @1:5-1:8
                    softbreak @-
                    text "-|-" @2:3-2:6

            """
        ),
        Case(
            "block quote in a block quote, data row with only the outer prefix",
            "> > a|b\n> > -|-\n> c|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:6
                block_quote @1:3-2:8
                  table @1:5-2:8
                    table_header @1:5-1:8
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "a" @1:5-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                        text "b" @1:7-1:8
                paragraph @3:3-3:6
                  text "c|d" @3:3-3:6

            """
        ),
        Case(
            "bullet item in a block quote, lazy header row",
            "> - x\na|b\n>   -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:1-3:8
                      table_header @2:1-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                          text "a" @2:1-2:2
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "b" @2:3-2:4

            """
        ),
        Case(
            "bullet item in a block quote, prefixed header row",
            "> - x\n>   a|b\n>   -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:5-3:8
                      table_header @2:5-2:8
                        table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                          text "a" @2:5-2:6
                        table_cell align=none colspan=1 rowspan=1 @2:7-2:8
                          text "b" @2:7-2:8

            """
        ),
        Case(
            "bullet item in a block quote, lazy delimiter row",
            "> - a|b\n-|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                list bullet '-' tight @1:3-2:4
                  item @1:3-2:4
                    paragraph @1:5-2:4
                      text "a|b" @1:5-1:8
                      softbreak @-
                      text "-|-" @2:1-2:4

            """
        ),
        Case(
            "bullet item in a block quote, prefixed delimiter row",
            "> - a|b\n>   -|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:8
                list bullet '-' tight @1:3-2:8
                  item @1:3-2:8
                    table @1:5-2:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8

            """
        ),
        Case(
            "bullet item in a block quote, lazy data row",
            "> - a|b\n>   -|-\nc|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-2:8
                list bullet '-' tight @1:3-2:8
                  item @1:3-2:8
                    table @1:5-2:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8
              paragraph @3:1-3:4
                text "c|d" @3:1-3:4

            """
        ),
        Case(
            "bullet item in a block quote, prefixed data row",
            "> - a|b\n>   -|-\n>   c|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    table @1:5-3:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8
                      table_row @3:5-3:8
                        table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                          text "c" @3:5-3:6
                        table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                          text "d" @3:7-3:8

            """
        ),
        Case(
            "bullet item in a block quote, lazy header row and lazy data row",
            "> - x\na|b\n>   -|-\nc|d\n",
            """
            document @1:1-5:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:1-3:8
                      table_header @2:1-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                          text "a" @2:1-2:2
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "b" @2:3-2:4
              paragraph @4:1-4:4
                text "c|d" @4:1-4:4

            """
        ),
        Case(
            "bullet item in a block quote, lazy header row and prefixed data row",
            "> - x\na|b\n>   -|-\n>   c|d\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:8
                list bullet '-' tight @1:3-4:8
                  item @1:3-4:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:1-4:8
                      table_header @2:1-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                          text "a" @2:1-2:2
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "b" @2:3-2:4
                      table_row @4:5-4:8
                        table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                          text "c" @4:5-4:6
                        table_cell align=none colspan=1 rowspan=1 @4:7-4:8
                          text "d" @4:7-4:8

            """
        ),
        Case(
            "bullet item in a block quote, lazy header row and lazy delimiter row",
            "> - x\na|b\n-|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:4
                list bullet '-' tight @1:3-3:4
                  item @1:3-3:4
                    paragraph @1:5-3:4
                      text "x" @1:5-1:6
                      softbreak @-
                      text "a|b" @2:1-2:4
                      softbreak @-
                      text "-|-" @3:1-3:4

            """
        ),
        Case(
            "bullet item in a block quote, lazy line before a prefixed header row",
            "> - x\ny\n>   a|b\n>   -|-\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:8
                list bullet '-' tight @1:3-4:8
                  item @1:3-4:8
                    paragraph @1:5-2:2
                      text "x" @1:5-1:6
                      softbreak @-
                      text "y" @2:1-2:2
                    table @3:5-4:8
                      table_header @3:5-3:8
                        table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                          text "a" @3:5-3:6
                        table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                          text "b" @3:7-3:8

            """
        ),
        Case(
            "bullet item in a block quote, header row with only the outer prefix",
            "> - x\n> a|b\n>   -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:3-3:8
                      table_header @2:3-2:6
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "a" @2:3-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                          text "b" @2:5-2:6

            """
        ),
        Case(
            "bullet item in a block quote, delimiter row with only the outer prefix",
            "> - a|b\n> -|-\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:6
                list bullet '-' tight @1:3-2:6
                  item @1:3-2:6
                    paragraph @1:5-2:6
                      text "a|b" @1:5-1:8
                      softbreak @-
                      text "-|-" @2:3-2:6

            """
        ),
        Case(
            "bullet item in a block quote, data row with only the outer prefix",
            "> - a|b\n>   -|-\n> c|d\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:6
                list bullet '-' tight @1:3-2:8
                  item @1:3-2:8
                    table @1:5-2:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8
                paragraph @3:3-3:6
                  text "c|d" @3:3-3:6

            """
        ),
        Case(
            "block quote in a bullet item, lazy header row",
            "- > x\na|b\n  > -|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  block_quote @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:1-3:8
                      table_header @2:1-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                          text "a" @2:1-2:2
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "b" @2:3-2:4

            """
        ),
        Case(
            "block quote in a bullet item, prefixed header row",
            "- > x\n  > a|b\n  > -|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  block_quote @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:5-3:8
                      table_header @2:5-2:8
                        table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                          text "a" @2:5-2:6
                        table_cell align=none colspan=1 rowspan=1 @2:7-2:8
                          text "b" @2:7-2:8

            """
        ),
        Case(
            "block quote in a bullet item, lazy delimiter row",
            "- > a|b\n-|-\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  block_quote @1:3-2:4
                    paragraph @1:5-2:4
                      text "a|b" @1:5-1:8
                      softbreak @-
                      text "-|-" @2:1-2:4

            """
        ),
        Case(
            "block quote in a bullet item, prefixed delimiter row",
            "- > a|b\n  > -|-\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:8
                item @1:1-2:8
                  block_quote @1:3-2:8
                    table @1:5-2:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8

            """
        ),
        Case(
            "block quote in a bullet item, lazy data row",
            "- > a|b\n  > -|-\nc|d\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-2:8
                item @1:1-2:8
                  block_quote @1:3-2:8
                    table @1:5-2:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8
              paragraph @3:1-3:4
                text "c|d" @3:1-3:4

            """
        ),
        Case(
            "block quote in a bullet item, prefixed data row",
            "- > a|b\n  > -|-\n  > c|d\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  block_quote @1:3-3:8
                    table @1:5-3:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8
                      table_row @3:5-3:8
                        table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                          text "c" @3:5-3:6
                        table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                          text "d" @3:7-3:8

            """
        ),
        Case(
            "block quote in a bullet item, lazy header row and lazy data row",
            "- > x\na|b\n  > -|-\nc|d\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  block_quote @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:1-3:8
                      table_header @2:1-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                          text "a" @2:1-2:2
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "b" @2:3-2:4
              paragraph @4:1-4:4
                text "c|d" @4:1-4:4

            """
        ),
        Case(
            "block quote in a bullet item, lazy header row and prefixed data row",
            "- > x\na|b\n  > -|-\n  > c|d\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:8
                item @1:1-4:8
                  block_quote @1:3-4:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:1-4:8
                      table_header @2:1-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                          text "a" @2:1-2:2
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "b" @2:3-2:4
                      table_row @4:5-4:8
                        table_cell align=none colspan=1 rowspan=1 @4:5-4:6
                          text "c" @4:5-4:6
                        table_cell align=none colspan=1 rowspan=1 @4:7-4:8
                          text "d" @4:7-4:8

            """
        ),
        Case(
            "block quote in a bullet item, lazy header row and lazy delimiter row",
            "- > x\na|b\n-|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:4
                item @1:1-3:4
                  block_quote @1:3-3:4
                    paragraph @1:5-3:4
                      text "x" @1:5-1:6
                      softbreak @-
                      text "a|b" @2:1-2:4
                      softbreak @-
                      text "-|-" @3:1-3:4

            """
        ),
        Case(
            "block quote in a bullet item, lazy line before a prefixed header row",
            "- > x\ny\n  > a|b\n  > -|-\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:8
                item @1:1-4:8
                  block_quote @1:3-4:8
                    paragraph @1:5-2:2
                      text "x" @1:5-1:6
                      softbreak @-
                      text "y" @2:1-2:2
                    table @3:5-4:8
                      table_header @3:5-3:8
                        table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                          text "a" @3:5-3:6
                        table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                          text "b" @3:7-3:8

            """
        ),
        Case(
            "block quote in a bullet item, header row with only the outer prefix",
            "- > x\n  a|b\n  > -|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  block_quote @1:3-3:8
                    paragraph @1:5-1:6
                      text "x" @1:5-1:6
                    table @2:3-3:8
                      table_header @2:3-2:6
                        table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                          text "a" @2:3-2:4
                        table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                          text "b" @2:5-2:6

            """
        ),
        Case(
            "block quote in a bullet item, delimiter row with only the outer prefix",
            "- > a|b\n  -|-\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  block_quote @1:3-2:6
                    paragraph @1:5-2:6
                      text "a|b" @1:5-1:8
                      softbreak @-
                      text "-|-" @2:3-2:6

            """
        ),
        Case(
            "block quote in a bullet item, data row with only the outer prefix",
            "- > a|b\n  > -|-\n  c|d\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  block_quote @1:3-2:8
                    table @1:5-2:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "a" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "b" @1:7-1:8
                  paragraph @3:3-3:6
                    text "c|d" @3:3-3:6

            """
        ),
        Case(
            "bullet item, lazy header row indented less than the content column",
            "- x\n a|b\n  -|-\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "x" @1:3-1:4
                  table @2:2-3:6
                    table_header @2:2-2:5
                      table_cell align=none colspan=1 rowspan=1 @2:2-2:3
                        text "a" @2:2-2:3
                      table_cell align=none colspan=1 rowspan=1 @2:4-2:5
                        text "b" @2:4-2:5

            """
        ),
        Case(
            "block quote, a line without its prefix after a heading begins a table outside it",
            "> # h\nc|d\n-|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-1:6
                heading 1 @1:3-1:6
                  text "h" @1:5-1:6
              table @2:1-3:4
                table_header @2:1-2:4
                  table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                    text "c" @2:1-2:2
                  table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                    text "d" @2:3-2:4

            """
        ),
        Case(
            "block quote, a line without its prefix that opens a list item",
            "> a\n- b|c\n  -|-\n",
            """
            document @1:1-4:1
              block_quote @1:1-1:4
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
              list bullet '-' tight @2:1-3:6
                item @2:1-3:6
                  table @2:3-3:6
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "c" @2:5-2:6

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .tables, .footnotes], sourceRanges: true) == c.expected)
    }
}
