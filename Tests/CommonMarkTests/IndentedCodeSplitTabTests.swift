/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Indented code blocks whose four columns of indentation end inside a tab, across containers, positions of the split
/// tab, and preceding lines.
///
/// Per Tabs, a tab advances to the next multiple of four columns, and when a block's indentation consumes only part of
/// a tab, the tab's remaining columns become spaces in the content: `>→→foo` and `-→→foo` both give `  foo`. Those
/// spaces stand for the split tab, so the block starts at that tab's byte.
///
/// Case names label the split: `A`, the tab holding a block quote or list marker's optional space is partly consumed
/// and the next tab split; `B`, a tab after the marker's space is split; `C`, a tab after spaces is split; `D`, the
/// indentation takes the rest of the marker's tab and ends among spaces, so no tab straddles its end. An indented code
/// block cannot interrupt a paragraph, so after a paragraph in the same container the line continues it. Continuation
/// lines of one block split their tabs by the same rule.
///
/// A two-digit ordered list marker followed by five or more columns of whitespace has its content at column four, a tab
/// stop, so a split arises only on its continuation lines, here an item with two spaces of padding. A footnote
/// definition consumes all whitespace after its label on its first line, so a split arises only on its continuation
/// lines, here in a block quote. At the top level the four-column strip always ends on a tab stop, so no tab is split.
@Suite("Indented code after a split tab")
struct IndentedCodeSplitTabTests {

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
            "block quote, A, first line",
            ">\t\tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:7
                code_block "" "  foo\\n" @1:3-1:7

            """
        ),
        Case(
            "block quote, A, after a blank line",
            "\n>\t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:7
                code_block "" "  foo\\n" @2:3-2:7

            """
        ),
        Case(
            "block quote, A, after a paragraph in the same container",
            "> a\n>\t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:7
                paragraph @1:3-2:7
                  text "a" @1:3-1:4
                  softbreak @-
                  text "foo" @2:4-2:7

            """
        ),
        Case(
            "block quote, A, after a lazy continuation line",
            "> a\nb\n>\t\tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:7
                paragraph @1:3-3:7
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2
                  softbreak @-
                  text "foo" @3:4-3:7

            """
        ),
        Case(
            "block quote, A, ending an open fenced code block's container",
            "- ```\n>\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:7
                code_block "" "  foo\\n" @2:3-2:7

            """
        ),
        Case(
            "block quote, A, after a closed fenced code block",
            "```\nx\n```\n>\t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:7
                code_block "" "  foo\\n" @4:3-4:7

            """
        ),
        Case(
            "block quote, A, after an indented code block",
            "    code\n>\t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:7
                code_block "" "  foo\\n" @2:3-2:7

            """
        ),
        Case(
            "block quote, B, first line",
            "> \t\tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                code_block "" "  foo\\n" @1:4-1:8

            """
        ),
        Case(
            "block quote, B, after a blank line",
            "\n> \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:8
                code_block "" "  foo\\n" @2:4-2:8

            """
        ),
        Case(
            "block quote, B, after a paragraph in the same container",
            "> a\n> \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:8
                paragraph @1:3-2:8
                  text "a" @1:3-1:4
                  softbreak @-
                  text "foo" @2:5-2:8

            """
        ),
        Case(
            "block quote, B, after a lazy continuation line",
            "> a\nb\n> \t\tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                paragraph @1:3-3:8
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2
                  softbreak @-
                  text "foo" @3:5-3:8

            """
        ),
        Case(
            "block quote, B, ending an open fenced code block's container",
            "- ```\n> \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:8
                code_block "" "  foo\\n" @2:4-2:8

            """
        ),
        Case(
            "block quote, B, after a closed fenced code block",
            "```\nx\n```\n> \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:8
                code_block "" "  foo\\n" @4:4-4:8

            """
        ),
        Case(
            "block quote, B, after an indented code block",
            "    code\n> \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:8
                code_block "" "  foo\\n" @2:4-2:8

            """
        ),
        Case(
            "block quote, C, first line",
            ">   \tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                code_block "" "  foo\\n" @1:5-1:9

            """
        ),
        Case(
            "block quote, C, after a blank line",
            "\n>   \tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:9
                code_block "" "  foo\\n" @2:5-2:9

            """
        ),
        Case(
            "block quote, C, after a paragraph in the same container",
            "> a\n>   \tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:9
                paragraph @1:3-2:9
                  text "a" @1:3-1:4
                  softbreak @-
                  text "foo" @2:6-2:9

            """
        ),
        Case(
            "block quote, C, after a lazy continuation line",
            "> a\nb\n>   \tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:9
                paragraph @1:3-3:9
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2
                  softbreak @-
                  text "foo" @3:6-3:9

            """
        ),
        Case(
            "block quote, C, ending an open fenced code block's container",
            "- ```\n>   \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:9
                code_block "" "  foo\\n" @2:5-2:9

            """
        ),
        Case(
            "block quote, C, after a closed fenced code block",
            "```\nx\n```\n>   \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:9
                code_block "" "  foo\\n" @4:5-4:9

            """
        ),
        Case(
            "block quote, C, after an indented code block",
            "    code\n>   \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:9
                code_block "" "  foo\\n" @2:5-2:9

            """
        ),
        Case(
            "block quote, D, first line",
            ">\t  foo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                code_block "" "foo\\n" @1:5-1:8

            """
        ),
        Case(
            "block quote, D, after a blank line",
            "\n>\t  foo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:8
                code_block "" "foo\\n" @2:5-2:8

            """
        ),
        Case(
            "block quote, D, after a paragraph in the same container",
            "> a\n>\t  foo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:8
                paragraph @1:3-2:8
                  text "a" @1:3-1:4
                  softbreak @-
                  text "foo" @2:5-2:8

            """
        ),
        Case(
            "block quote, D, after a lazy continuation line",
            "> a\nb\n>\t  foo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                paragraph @1:3-3:8
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2
                  softbreak @-
                  text "foo" @3:5-3:8

            """
        ),
        Case(
            "block quote, D, ending an open fenced code block's container",
            "- ```\n>\t  foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:8
                code_block "" "foo\\n" @2:5-2:8

            """
        ),
        Case(
            "block quote, D, after a closed fenced code block",
            "```\nx\n```\n>\t  foo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:8
                code_block "" "foo\\n" @4:5-4:8

            """
        ),
        Case(
            "block quote, D, after an indented code block",
            "    code\n>\t  foo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:8
                code_block "" "foo\\n" @2:5-2:8

            """
        ),
        Case(
            "block quote, continuation lines",
            ">\t\tfoo\n> \t\tfoo\n>   \tfoo\n>\t  foo\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:8
                code_block "" "  foo\\n  foo\\n  foo\\nfoo\\n" @1:3-4:8

            """
        ),
        Case(
            "bullet item, A, first line",
            "-\t\tfoo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:7
                item @1:1-1:7
                  code_block "" "  foo\\n" @1:3-1:7

            """
        ),
        Case(
            "bullet item, A, after a blank line",
            "\n-\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:7
                item @2:1-2:7
                  code_block "" "  foo\\n" @2:3-2:7

            """
        ),
        Case(
            "bullet item, A, after a paragraph in the same container",
            "- a\n \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:7
                item @1:1-2:7
                  paragraph @1:3-2:7
                    text "a" @1:3-1:4
                    softbreak @-
                    text "foo" @2:4-2:7

            """
        ),
        Case(
            "bullet item, A, after a lazy continuation line",
            "- a\nb\n \t\tfoo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:7
                item @1:1-3:7
                  paragraph @1:3-3:7
                    text "a" @1:3-1:4
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:4-3:7

            """
        ),
        Case(
            "bullet item, A, ending an open fenced code block's container",
            "- ```\n-\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:7
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:7
                  code_block "" "  foo\\n" @2:3-2:7

            """
        ),
        Case(
            "bullet item, A, after a closed fenced code block",
            "```\nx\n```\n-\t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:7
                item @4:1-4:7
                  code_block "" "  foo\\n" @4:3-4:7

            """
        ),
        Case(
            "bullet item, A, after an indented code block",
            "    code\n-\t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:7
                item @2:1-2:7
                  code_block "" "  foo\\n" @2:3-2:7

            """
        ),
        Case(
            "bullet item, B, first line",
            "- \t\tfoo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  code_block "" "  foo\\n" @1:4-1:8

            """
        ),
        Case(
            "bullet item, B, after a blank line",
            "\n- \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:8
                item @2:1-2:8
                  code_block "" "  foo\\n" @2:4-2:8

            """
        ),
        Case(
            "bullet item, B, after a paragraph in the same container",
            "- a\n  \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:8
                item @1:1-2:8
                  paragraph @1:3-2:8
                    text "a" @1:3-1:4
                    softbreak @-
                    text "foo" @2:5-2:8

            """
        ),
        Case(
            "bullet item, B, after a lazy continuation line",
            "- a\nb\n  \t\tfoo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-3:8
                    text "a" @1:3-1:4
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:5-3:8

            """
        ),
        Case(
            "bullet item, B, ending an open fenced code block's container",
            "- ```\n- \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:8
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:8
                  code_block "" "  foo\\n" @2:4-2:8

            """
        ),
        Case(
            "bullet item, B, after a closed fenced code block",
            "```\nx\n```\n- \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:8
                item @4:1-4:8
                  code_block "" "  foo\\n" @4:4-4:8

            """
        ),
        Case(
            "bullet item, B, after an indented code block",
            "    code\n- \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:8
                item @2:1-2:8
                  code_block "" "  foo\\n" @2:4-2:8

            """
        ),
        Case(
            "bullet item, C, first line",
            "-    \tfoo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
                  code_block "" "  foo\\n" @1:6-1:10

            """
        ),
        Case(
            "bullet item, C, after a blank line",
            "\n-    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:10
                item @2:1-2:10
                  code_block "" "  foo\\n" @2:6-2:10

            """
        ),
        Case(
            "bullet item, C, after a paragraph in the same container",
            "- a\n     \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:10
                item @1:1-2:10
                  paragraph @1:3-2:10
                    text "a" @1:3-1:4
                    softbreak @-
                    text "foo" @2:7-2:10

            """
        ),
        Case(
            "bullet item, C, after a lazy continuation line",
            "- a\nb\n     \tfoo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-3:10
                    text "a" @1:3-1:4
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:7-3:10

            """
        ),
        Case(
            "bullet item, C, ending an open fenced code block's container",
            "- ```\n-    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:10
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:10
                  code_block "" "  foo\\n" @2:6-2:10

            """
        ),
        Case(
            "bullet item, C, after a closed fenced code block",
            "```\nx\n```\n-    \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:10
                item @4:1-4:10
                  code_block "" "  foo\\n" @4:6-4:10

            """
        ),
        Case(
            "bullet item, C, after an indented code block",
            "    code\n-    \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:10
                item @2:1-2:10
                  code_block "" "  foo\\n" @2:6-2:10

            """
        ),
        Case(
            "bullet item, D, first line",
            "-\t  foo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  code_block "" "foo\\n" @1:5-1:8

            """
        ),
        Case(
            "bullet item, D, after a blank line",
            "\n-\t  foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:8
                item @2:1-2:8
                  code_block "" "foo\\n" @2:5-2:8

            """
        ),
        Case(
            "bullet item, D, after a paragraph in the same container",
            "- a\n \t  foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:8
                item @1:1-2:8
                  paragraph @1:3-2:8
                    text "a" @1:3-1:4
                    softbreak @-
                    text "foo" @2:5-2:8

            """
        ),
        Case(
            "bullet item, D, after a lazy continuation line",
            "- a\nb\n \t  foo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-3:8
                    text "a" @1:3-1:4
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:5-3:8

            """
        ),
        Case(
            "bullet item, D, ending an open fenced code block's container",
            "- ```\n-\t  foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:8
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:8
                  code_block "" "foo\\n" @2:5-2:8

            """
        ),
        Case(
            "bullet item, D, after a closed fenced code block",
            "```\nx\n```\n-\t  foo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:8
                item @4:1-4:8
                  code_block "" "foo\\n" @4:5-4:8

            """
        ),
        Case(
            "bullet item, D, after an indented code block",
            "    code\n-\t  foo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:8
                item @2:1-2:8
                  code_block "" "foo\\n" @2:5-2:8

            """
        ),
        Case(
            "bullet item, continuation lines",
            "-\t\tfoo\n  \t\tfoo\n     \tfoo\n \t  foo\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:8
                item @1:1-4:8
                  code_block "" "  foo\\n  foo\\n  foo\\nfoo\\n" @1:3-4:8

            """
        ),
        Case(
            "one-digit ordered item, A, first line",
            "1.\t\tfoo\n",
            """
            document @1:1-2:1
              list ordered start=1 delim=period tight @1:1-1:8
                item @1:1-1:8
                  code_block "" " foo\\n" @1:4-1:8

            """
        ),
        Case(
            "one-digit ordered item, A, after a blank line",
            "\n1.\t\tfoo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @2:1-2:8
                item @2:1-2:8
                  code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "one-digit ordered item, A, after a paragraph in the same container",
            "1. a\n  \t\tfoo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:8
                item @1:1-2:8
                  paragraph @1:4-2:8
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:5-2:8

            """
        ),
        Case(
            "one-digit ordered item, A, after a lazy continuation line",
            "1. a\nb\n  \t\tfoo\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:8
                item @1:1-3:8
                  paragraph @1:4-3:8
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:5-3:8

            """
        ),
        Case(
            "one-digit ordered item, A, ending an open fenced code block's container",
            "- ```\n1.\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              list ordered start=1 delim=period tight @2:1-2:8
                item @2:1-2:8
                  code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "one-digit ordered item, A, after a closed fenced code block",
            "```\nx\n```\n1.\t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list ordered start=1 delim=period tight @4:1-4:8
                item @4:1-4:8
                  code_block "" " foo\\n" @4:4-4:8

            """
        ),
        Case(
            "one-digit ordered item, A, after an indented code block",
            "    code\n1.\t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list ordered start=1 delim=period tight @2:1-2:8
                item @2:1-2:8
                  code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "one-digit ordered item, B, first line",
            "1. \t\tfoo\n",
            """
            document @1:1-2:1
              list ordered start=1 delim=period tight @1:1-1:9
                item @1:1-1:9
                  code_block "" " foo\\n" @1:5-1:9

            """
        ),
        Case(
            "one-digit ordered item, B, after a blank line",
            "\n1. \t\tfoo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @2:1-2:9
                item @2:1-2:9
                  code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "one-digit ordered item, B, after a paragraph in the same container",
            "1. a\n   \t\tfoo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:9
                item @1:1-2:9
                  paragraph @1:4-2:9
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:6-2:9

            """
        ),
        Case(
            "one-digit ordered item, B, after a lazy continuation line",
            "1. a\nb\n   \t\tfoo\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-3:9
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:6-3:9

            """
        ),
        Case(
            "one-digit ordered item, B, ending an open fenced code block's container",
            "- ```\n1. \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              list ordered start=1 delim=period tight @2:1-2:9
                item @2:1-2:9
                  code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "one-digit ordered item, B, after a closed fenced code block",
            "```\nx\n```\n1. \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list ordered start=1 delim=period tight @4:1-4:9
                item @4:1-4:9
                  code_block "" " foo\\n" @4:5-4:9

            """
        ),
        Case(
            "one-digit ordered item, B, after an indented code block",
            "    code\n1. \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list ordered start=1 delim=period tight @2:1-2:9
                item @2:1-2:9
                  code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "one-digit ordered item, C, first line",
            "1.    \tfoo\n",
            """
            document @1:1-2:1
              list ordered start=1 delim=period tight @1:1-1:11
                item @1:1-1:11
                  code_block "" " foo\\n" @1:7-1:11

            """
        ),
        Case(
            "one-digit ordered item, C, after a blank line",
            "\n1.    \tfoo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @2:1-2:11
                item @2:1-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "one-digit ordered item, C, after a paragraph in the same container",
            "1. a\n      \tfoo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:11
                item @1:1-2:11
                  paragraph @1:4-2:11
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:8-2:11

            """
        ),
        Case(
            "one-digit ordered item, C, after a lazy continuation line",
            "1. a\nb\n      \tfoo\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-3:11
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:8-3:11

            """
        ),
        Case(
            "one-digit ordered item, C, ending an open fenced code block's container",
            "- ```\n1.    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              list ordered start=1 delim=period tight @2:1-2:11
                item @2:1-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "one-digit ordered item, C, after a closed fenced code block",
            "```\nx\n```\n1.    \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list ordered start=1 delim=period tight @4:1-4:11
                item @4:1-4:11
                  code_block "" " foo\\n" @4:7-4:11

            """
        ),
        Case(
            "one-digit ordered item, C, after an indented code block",
            "    code\n1.    \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list ordered start=1 delim=period tight @2:1-2:11
                item @2:1-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "one-digit ordered item, D, first line",
            "1.\t   foo\n",
            """
            document @1:1-2:1
              list ordered start=1 delim=period tight @1:1-1:10
                item @1:1-1:10
                  code_block "" "foo\\n" @1:7-1:10

            """
        ),
        Case(
            "one-digit ordered item, D, after a blank line",
            "\n1.\t   foo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @2:1-2:10
                item @2:1-2:10
                  code_block "" "foo\\n" @2:7-2:10

            """
        ),
        Case(
            "one-digit ordered item, D, after a paragraph in the same container",
            "1. a\n  \t   foo\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:10
                item @1:1-2:10
                  paragraph @1:4-2:10
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:7-2:10

            """
        ),
        Case(
            "one-digit ordered item, D, after a lazy continuation line",
            "1. a\nb\n  \t   foo\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-3:10
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:7-3:10

            """
        ),
        Case(
            "one-digit ordered item, D, ending an open fenced code block's container",
            "- ```\n1.\t   foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              list ordered start=1 delim=period tight @2:1-2:10
                item @2:1-2:10
                  code_block "" "foo\\n" @2:7-2:10

            """
        ),
        Case(
            "one-digit ordered item, D, after a closed fenced code block",
            "```\nx\n```\n1.\t   foo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list ordered start=1 delim=period tight @4:1-4:10
                item @4:1-4:10
                  code_block "" "foo\\n" @4:7-4:10

            """
        ),
        Case(
            "one-digit ordered item, D, after an indented code block",
            "    code\n1.\t   foo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list ordered start=1 delim=period tight @2:1-2:10
                item @2:1-2:10
                  code_block "" "foo\\n" @2:7-2:10

            """
        ),
        Case(
            "one-digit ordered item, continuation lines",
            "1.\t\tfoo\n   \t\tfoo\n      \tfoo\n  \t   foo\n",
            """
            document @1:1-5:1
              list ordered start=1 delim=period tight @1:1-4:10
                item @1:1-4:10
                  code_block "" " foo\\n foo\\n foo\\nfoo\\n" @1:4-4:10

            """
        ),
        Case(
            "block quote in item, A, first line",
            "-  >\t\tfoo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
                  block_quote @1:4-1:10
                    code_block "" "   foo\\n" @1:6-1:10

            """
        ),
        Case(
            "block quote in item, A, after a blank line",
            "\n-  >\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:10
                item @2:1-2:10
                  block_quote @2:4-2:10
                    code_block "" "   foo\\n" @2:6-2:10

            """
        ),
        Case(
            "block quote in item, A, after a paragraph in the same container",
            "-  > a\n   >\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:10
                item @1:1-2:10
                  block_quote @1:4-2:10
                    paragraph @1:6-2:10
                      text "a" @1:6-1:7
                      softbreak @-
                      text "foo" @2:7-2:10

            """
        ),
        Case(
            "block quote in item, A, after a lazy continuation line",
            "-  > a\nb\n   >\t\tfoo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:10
                item @1:1-3:10
                  block_quote @1:4-3:10
                    paragraph @1:6-3:10
                      text "a" @1:6-1:7
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:7-3:10

            """
        ),
        Case(
            "block quote in item, A, ending an open fenced code block's container",
            "- ```\n-  >\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:10
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:10
                  block_quote @2:4-2:10
                    code_block "" "   foo\\n" @2:6-2:10

            """
        ),
        Case(
            "block quote in item, A, after a closed fenced code block",
            "```\nx\n```\n-  >\t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:10
                item @4:1-4:10
                  block_quote @4:4-4:10
                    code_block "" "   foo\\n" @4:6-4:10

            """
        ),
        Case(
            "block quote in item, A, after an indented code block",
            "    code\n-  >\t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:10
                item @2:1-2:10
                  block_quote @2:4-2:10
                    code_block "" "   foo\\n" @2:6-2:10

            """
        ),
        Case(
            "block quote in item, B, first line",
            "-  > \t\tfoo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:11
                item @1:1-1:11
                  block_quote @1:4-1:11
                    code_block "" "   foo\\n" @1:7-1:11

            """
        ),
        Case(
            "block quote in item, B, after a blank line",
            "\n-  > \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:11
                item @2:1-2:11
                  block_quote @2:4-2:11
                    code_block "" "   foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in item, B, after a paragraph in the same container",
            "-  > a\n   > \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:11
                item @1:1-2:11
                  block_quote @1:4-2:11
                    paragraph @1:6-2:11
                      text "a" @1:6-1:7
                      softbreak @-
                      text "foo" @2:8-2:11

            """
        ),
        Case(
            "block quote in item, B, after a lazy continuation line",
            "-  > a\nb\n   > \t\tfoo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:11
                item @1:1-3:11
                  block_quote @1:4-3:11
                    paragraph @1:6-3:11
                      text "a" @1:6-1:7
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:8-3:11

            """
        ),
        Case(
            "block quote in item, B, ending an open fenced code block's container",
            "- ```\n-  > \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:11
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:11
                  block_quote @2:4-2:11
                    code_block "" "   foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in item, B, after a closed fenced code block",
            "```\nx\n```\n-  > \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:11
                item @4:1-4:11
                  block_quote @4:4-4:11
                    code_block "" "   foo\\n" @4:7-4:11

            """
        ),
        Case(
            "block quote in item, B, after an indented code block",
            "    code\n-  > \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:11
                item @2:1-2:11
                  block_quote @2:4-2:11
                    code_block "" "   foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in item, C, first line",
            "-  >    \tfoo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:13
                item @1:1-1:13
                  block_quote @1:4-1:13
                    code_block "" "   foo\\n" @1:9-1:13

            """
        ),
        Case(
            "block quote in item, C, after a blank line",
            "\n-  >    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:13
                item @2:1-2:13
                  block_quote @2:4-2:13
                    code_block "" "   foo\\n" @2:9-2:13

            """
        ),
        Case(
            "block quote in item, C, after a paragraph in the same container",
            "-  > a\n   >    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:13
                item @1:1-2:13
                  block_quote @1:4-2:13
                    paragraph @1:6-2:13
                      text "a" @1:6-1:7
                      softbreak @-
                      text "foo" @2:10-2:13

            """
        ),
        Case(
            "block quote in item, C, after a lazy continuation line",
            "-  > a\nb\n   >    \tfoo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:13
                item @1:1-3:13
                  block_quote @1:4-3:13
                    paragraph @1:6-3:13
                      text "a" @1:6-1:7
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:10-3:13

            """
        ),
        Case(
            "block quote in item, C, ending an open fenced code block's container",
            "- ```\n-  >    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:13
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:13
                  block_quote @2:4-2:13
                    code_block "" "   foo\\n" @2:9-2:13

            """
        ),
        Case(
            "block quote in item, C, after a closed fenced code block",
            "```\nx\n```\n-  >    \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:13
                item @4:1-4:13
                  block_quote @4:4-4:13
                    code_block "" "   foo\\n" @4:9-4:13

            """
        ),
        Case(
            "block quote in item, C, after an indented code block",
            "    code\n-  >    \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:13
                item @2:1-2:13
                  block_quote @2:4-2:13
                    code_block "" "   foo\\n" @2:9-2:13

            """
        ),
        Case(
            "block quote in item, D, first line",
            "-  >\t   foo\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:12
                item @1:1-1:12
                  block_quote @1:4-1:12
                    code_block "" "  foo\\n" @1:7-1:12

            """
        ),
        Case(
            "block quote in item, D, after a blank line",
            "\n-  >\t   foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @2:1-2:12
                item @2:1-2:12
                  block_quote @2:4-2:12
                    code_block "" "  foo\\n" @2:7-2:12

            """
        ),
        Case(
            "block quote in item, D, after a paragraph in the same container",
            "-  > a\n   >\t   foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:12
                item @1:1-2:12
                  block_quote @1:4-2:12
                    paragraph @1:6-2:12
                      text "a" @1:6-1:7
                      softbreak @-
                      text "foo" @2:9-2:12

            """
        ),
        Case(
            "block quote in item, D, after a lazy continuation line",
            "-  > a\nb\n   >\t   foo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:12
                item @1:1-3:12
                  block_quote @1:4-3:12
                    paragraph @1:6-3:12
                      text "a" @1:6-1:7
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:9-3:12

            """
        ),
        Case(
            "block quote in item, D, ending an open fenced code block's container",
            "- ```\n-  >\t   foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:12
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
                item @2:1-2:12
                  block_quote @2:4-2:12
                    code_block "" "  foo\\n" @2:7-2:12

            """
        ),
        Case(
            "block quote in item, D, after a closed fenced code block",
            "```\nx\n```\n-  >\t   foo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              list bullet '-' tight @4:1-4:12
                item @4:1-4:12
                  block_quote @4:4-4:12
                    code_block "" "  foo\\n" @4:7-4:12

            """
        ),
        Case(
            "block quote in item, D, after an indented code block",
            "    code\n-  >\t   foo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              list bullet '-' tight @2:1-2:12
                item @2:1-2:12
                  block_quote @2:4-2:12
                    code_block "" "  foo\\n" @2:7-2:12

            """
        ),
        Case(
            "block quote in item, continuation lines",
            "-  >\t\tfoo\n   > \t\tfoo\n   >    \tfoo\n   >\t   foo\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:12
                item @1:1-4:12
                  block_quote @1:4-4:12
                    code_block "" "   foo\\n   foo\\n   foo\\n  foo\\n" @1:6-4:12

            """
        ),
        Case(
            "item in block quote, A, first line",
            ">-\t\tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                list bullet '-' tight @1:2-1:8
                  item @1:2-1:8
                    code_block "" " foo\\n" @1:4-1:8

            """
        ),
        Case(
            "item in block quote, A, after a blank line",
            "\n>-\t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:8
                list bullet '-' tight @2:2-2:8
                  item @2:2-2:8
                    code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "item in block quote, A, after a paragraph in the same container",
            ">- a\n> \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:8
                list bullet '-' tight @1:2-2:8
                  item @1:2-2:8
                    paragraph @1:4-2:8
                      text "a" @1:4-1:5
                      softbreak @-
                      text "foo" @2:5-2:8

            """
        ),
        Case(
            "item in block quote, A, after a lazy continuation line",
            ">- a\nb\n> \t\tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:2-3:8
                  item @1:2-3:8
                    paragraph @1:4-3:8
                      text "a" @1:4-1:5
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:5-3:8

            """
        ),
        Case(
            "item in block quote, A, ending an open fenced code block's container",
            "- ```\n>-\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:8
                list bullet '-' tight @2:2-2:8
                  item @2:2-2:8
                    code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "item in block quote, A, after a closed fenced code block",
            "```\nx\n```\n>-\t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:8
                list bullet '-' tight @4:2-4:8
                  item @4:2-4:8
                    code_block "" " foo\\n" @4:4-4:8

            """
        ),
        Case(
            "item in block quote, A, after an indented code block",
            "    code\n>-\t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:8
                list bullet '-' tight @2:2-2:8
                  item @2:2-2:8
                    code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "item in block quote, B, first line",
            ">- \t\tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                list bullet '-' tight @1:2-1:9
                  item @1:2-1:9
                    code_block "" " foo\\n" @1:5-1:9

            """
        ),
        Case(
            "item in block quote, B, after a blank line",
            "\n>- \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:9
                list bullet '-' tight @2:2-2:9
                  item @2:2-2:9
                    code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "item in block quote, B, after a paragraph in the same container",
            ">- a\n>  \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:9
                list bullet '-' tight @1:2-2:9
                  item @1:2-2:9
                    paragraph @1:4-2:9
                      text "a" @1:4-1:5
                      softbreak @-
                      text "foo" @2:6-2:9

            """
        ),
        Case(
            "item in block quote, B, after a lazy continuation line",
            ">- a\nb\n>  \t\tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:9
                list bullet '-' tight @1:2-3:9
                  item @1:2-3:9
                    paragraph @1:4-3:9
                      text "a" @1:4-1:5
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:6-3:9

            """
        ),
        Case(
            "item in block quote, B, ending an open fenced code block's container",
            "- ```\n>- \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:9
                list bullet '-' tight @2:2-2:9
                  item @2:2-2:9
                    code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "item in block quote, B, after a closed fenced code block",
            "```\nx\n```\n>- \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:9
                list bullet '-' tight @4:2-4:9
                  item @4:2-4:9
                    code_block "" " foo\\n" @4:5-4:9

            """
        ),
        Case(
            "item in block quote, B, after an indented code block",
            "    code\n>- \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:9
                list bullet '-' tight @2:2-2:9
                  item @2:2-2:9
                    code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "item in block quote, C, first line",
            ">-    \tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                list bullet '-' tight @1:2-1:11
                  item @1:2-1:11
                    code_block "" " foo\\n" @1:7-1:11

            """
        ),
        Case(
            "item in block quote, C, after a blank line",
            "\n>-    \tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:11
                list bullet '-' tight @2:2-2:11
                  item @2:2-2:11
                    code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "item in block quote, C, after a paragraph in the same container",
            ">- a\n>     \tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:11
                list bullet '-' tight @1:2-2:11
                  item @1:2-2:11
                    paragraph @1:4-2:11
                      text "a" @1:4-1:5
                      softbreak @-
                      text "foo" @2:8-2:11

            """
        ),
        Case(
            "item in block quote, C, after a lazy continuation line",
            ">- a\nb\n>     \tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:11
                list bullet '-' tight @1:2-3:11
                  item @1:2-3:11
                    paragraph @1:4-3:11
                      text "a" @1:4-1:5
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:8-3:11

            """
        ),
        Case(
            "item in block quote, C, ending an open fenced code block's container",
            "- ```\n>-    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:11
                list bullet '-' tight @2:2-2:11
                  item @2:2-2:11
                    code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "item in block quote, C, after a closed fenced code block",
            "```\nx\n```\n>-    \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:11
                list bullet '-' tight @4:2-4:11
                  item @4:2-4:11
                    code_block "" " foo\\n" @4:7-4:11

            """
        ),
        Case(
            "item in block quote, C, after an indented code block",
            "    code\n>-    \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:11
                list bullet '-' tight @2:2-2:11
                  item @2:2-2:11
                    code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "item in block quote, D, first line",
            ">-\t   foo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                list bullet '-' tight @1:2-1:10
                  item @1:2-1:10
                    code_block "" "foo\\n" @1:7-1:10

            """
        ),
        Case(
            "item in block quote, D, after a blank line",
            "\n>-\t   foo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:10
                list bullet '-' tight @2:2-2:10
                  item @2:2-2:10
                    code_block "" "foo\\n" @2:7-2:10

            """
        ),
        Case(
            "item in block quote, D, after a paragraph in the same container",
            ">- a\n> \t   foo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:10
                list bullet '-' tight @1:2-2:10
                  item @1:2-2:10
                    paragraph @1:4-2:10
                      text "a" @1:4-1:5
                      softbreak @-
                      text "foo" @2:7-2:10

            """
        ),
        Case(
            "item in block quote, D, after a lazy continuation line",
            ">- a\nb\n> \t   foo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:10
                list bullet '-' tight @1:2-3:10
                  item @1:2-3:10
                    paragraph @1:4-3:10
                      text "a" @1:4-1:5
                      softbreak @-
                      text "b" @2:1-2:2
                      softbreak @-
                      text "foo" @3:7-3:10

            """
        ),
        Case(
            "item in block quote, D, ending an open fenced code block's container",
            "- ```\n>-\t   foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:10
                list bullet '-' tight @2:2-2:10
                  item @2:2-2:10
                    code_block "" "foo\\n" @2:7-2:10

            """
        ),
        Case(
            "item in block quote, D, after a closed fenced code block",
            "```\nx\n```\n>-\t   foo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:10
                list bullet '-' tight @4:2-4:10
                  item @4:2-4:10
                    code_block "" "foo\\n" @4:7-4:10

            """
        ),
        Case(
            "item in block quote, D, after an indented code block",
            "    code\n>-\t   foo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:10
                list bullet '-' tight @2:2-2:10
                  item @2:2-2:10
                    code_block "" "foo\\n" @2:7-2:10

            """
        ),
        Case(
            "item in block quote, continuation lines",
            ">-\t\tfoo\n>  \t\tfoo\n>     \tfoo\n> \t   foo\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:10
                list bullet '-' tight @1:2-4:10
                  item @1:2-4:10
                    code_block "" " foo\\nfoo\\nfoo\\n" @1:4-3:11
                    paragraph @4:7-4:10
                      text "foo" @4:7-4:10

            """
        ),
        Case(
            "block quote in block quote, A, first line",
            ">>\t\tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                block_quote @1:2-1:8
                  code_block "" " foo\\n" @1:4-1:8

            """
        ),
        Case(
            "block quote in block quote, A, after a blank line",
            "\n>>\t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:8
                block_quote @2:2-2:8
                  code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "block quote in block quote, A, after a paragraph in the same container",
            ">> a\n>>\t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:8
                block_quote @1:2-2:8
                  paragraph @1:4-2:8
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:5-2:8

            """
        ),
        Case(
            "block quote in block quote, A, after a lazy continuation line",
            ">> a\nb\n>>\t\tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                block_quote @1:2-3:8
                  paragraph @1:4-3:8
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:5-3:8

            """
        ),
        Case(
            "block quote in block quote, A, ending an open fenced code block's container",
            "- ```\n>>\t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:8
                block_quote @2:2-2:8
                  code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "block quote in block quote, A, after a closed fenced code block",
            "```\nx\n```\n>>\t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:8
                block_quote @4:2-4:8
                  code_block "" " foo\\n" @4:4-4:8

            """
        ),
        Case(
            "block quote in block quote, A, after an indented code block",
            "    code\n>>\t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:8
                block_quote @2:2-2:8
                  code_block "" " foo\\n" @2:4-2:8

            """
        ),
        Case(
            "block quote in block quote, B, first line",
            ">> \t\tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  code_block "" " foo\\n" @1:5-1:9

            """
        ),
        Case(
            "block quote in block quote, B, after a blank line",
            "\n>> \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:9
                block_quote @2:2-2:9
                  code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "block quote in block quote, B, after a paragraph in the same container",
            ">> a\n>> \t\tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:9
                block_quote @1:2-2:9
                  paragraph @1:4-2:9
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:6-2:9

            """
        ),
        Case(
            "block quote in block quote, B, after a lazy continuation line",
            ">> a\nb\n>> \t\tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:9
                block_quote @1:2-3:9
                  paragraph @1:4-3:9
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:6-3:9

            """
        ),
        Case(
            "block quote in block quote, B, ending an open fenced code block's container",
            "- ```\n>> \t\tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:9
                block_quote @2:2-2:9
                  code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "block quote in block quote, B, after a closed fenced code block",
            "```\nx\n```\n>> \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:9
                block_quote @4:2-4:9
                  code_block "" " foo\\n" @4:5-4:9

            """
        ),
        Case(
            "block quote in block quote, B, after an indented code block",
            "    code\n>> \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:9
                block_quote @2:2-2:9
                  code_block "" " foo\\n" @2:5-2:9

            """
        ),
        Case(
            "block quote in block quote, C, first line",
            ">>    \tfoo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  code_block "" " foo\\n" @1:7-1:11

            """
        ),
        Case(
            "block quote in block quote, C, after a blank line",
            "\n>>    \tfoo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:11
                block_quote @2:2-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in block quote, C, after a paragraph in the same container",
            ">> a\n>>    \tfoo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:11
                block_quote @1:2-2:11
                  paragraph @1:4-2:11
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:8-2:11

            """
        ),
        Case(
            "block quote in block quote, C, after a lazy continuation line",
            ">> a\nb\n>>    \tfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:11
                block_quote @1:2-3:11
                  paragraph @1:4-3:11
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:8-3:11

            """
        ),
        Case(
            "block quote in block quote, C, ending an open fenced code block's container",
            "- ```\n>>    \tfoo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:11
                block_quote @2:2-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in block quote, C, after a closed fenced code block",
            "```\nx\n```\n>>    \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:11
                block_quote @4:2-4:11
                  code_block "" " foo\\n" @4:7-4:11

            """
        ),
        Case(
            "block quote in block quote, C, after an indented code block",
            "    code\n>>    \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:11
                block_quote @2:2-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in block quote, D, first line",
            ">>\t    foo\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  code_block "" " foo\\n" @1:7-1:11

            """
        ),
        Case(
            "block quote in block quote, D, after a blank line",
            "\n>>\t    foo\n",
            """
            document @1:1-3:1
              block_quote @2:1-2:11
                block_quote @2:2-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in block quote, D, after a paragraph in the same container",
            ">> a\n>>\t    foo\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:11
                block_quote @1:2-2:11
                  paragraph @1:4-2:11
                    text "a" @1:4-1:5
                    softbreak @-
                    text "foo" @2:8-2:11

            """
        ),
        Case(
            "block quote in block quote, D, after a lazy continuation line",
            ">> a\nb\n>>\t    foo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:11
                block_quote @1:2-3:11
                  paragraph @1:4-3:11
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:8-3:11

            """
        ),
        Case(
            "block quote in block quote, D, ending an open fenced code block's container",
            "- ```\n>>\t    foo\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:11
                block_quote @2:2-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in block quote, D, after a closed fenced code block",
            "```\nx\n```\n>>\t    foo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              block_quote @4:1-4:11
                block_quote @4:2-4:11
                  code_block "" " foo\\n" @4:7-4:11

            """
        ),
        Case(
            "block quote in block quote, D, after an indented code block",
            "    code\n>>\t    foo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n" @1:5-1:9
              block_quote @2:1-2:11
                block_quote @2:2-2:11
                  code_block "" " foo\\n" @2:7-2:11

            """
        ),
        Case(
            "block quote in block quote, continuation lines",
            ">>\t\tfoo\n>> \t\tfoo\n>>    \tfoo\n>>\t    foo\n",
            """
            document @1:1-5:1
              block_quote @1:1-4:11
                block_quote @1:2-4:11
                  code_block "" " foo\\n foo\\n foo\\n foo\\n" @1:4-4:11

            """
        ),
        Case(
            "two-digit ordered item, A, after a blank line",
            "10.  a\n\n\t\t\tfoo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period loose @1:1-3:7
                item @1:1-3:7
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "   foo\\n" @3:3-3:7

            """
        ),
        Case(
            "two-digit ordered item, A, after a paragraph in the same container",
            "10.  a\n\t\t\tfoo\n",
            """
            document @1:1-3:1
              list ordered start=10 delim=period tight @1:1-2:7
                item @1:1-2:7
                  paragraph @1:6-2:7
                    text "a" @1:6-1:7
                    softbreak @-
                    text "foo" @2:4-2:7

            """
        ),
        Case(
            "two-digit ordered item, A, after a lazy continuation line",
            "10.  a\nb\n\t\t\tfoo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period tight @1:1-3:7
                item @1:1-3:7
                  paragraph @1:6-3:7
                    text "a" @1:6-1:7
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:4-3:7

            """
        ),
        Case(
            "two-digit ordered item, A, after a closed fenced code block",
            "10.  a\n\n     ```\n     ```\n\t\t\tfoo\n",
            """
            document @1:1-6:1
              list ordered start=10 delim=period loose @1:1-5:7
                item @1:1-5:7
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "" @3:6-4:9
                  code_block "" "   foo\\n" @5:3-5:7

            """
        ),
        Case(
            "two-digit ordered item, B, after a blank line",
            "10.  a\n\n     \t\tfoo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "   foo\\n" @3:7-3:11

            """
        ),
        Case(
            "two-digit ordered item, B, after a paragraph in the same container",
            "10.  a\n     \t\tfoo\n",
            """
            document @1:1-3:1
              list ordered start=10 delim=period tight @1:1-2:11
                item @1:1-2:11
                  paragraph @1:6-2:11
                    text "a" @1:6-1:7
                    softbreak @-
                    text "foo" @2:8-2:11

            """
        ),
        Case(
            "two-digit ordered item, B, after a lazy continuation line",
            "10.  a\nb\n     \t\tfoo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period tight @1:1-3:11
                item @1:1-3:11
                  paragraph @1:6-3:11
                    text "a" @1:6-1:7
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:8-3:11

            """
        ),
        Case(
            "two-digit ordered item, B, after a closed fenced code block",
            "10.  a\n\n     ```\n     ```\n     \t\tfoo\n",
            """
            document @1:1-6:1
              list ordered start=10 delim=period loose @1:1-5:11
                item @1:1-5:11
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "" @3:6-4:9
                  code_block "" "   foo\\n" @5:7-5:11

            """
        ),
        Case(
            "two-digit ordered item, C, after a blank line",
            "10.  a\n\n        \tfoo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period loose @1:1-3:13
                item @1:1-3:13
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "   foo\\n" @3:9-3:13

            """
        ),
        Case(
            "two-digit ordered item, C, after a paragraph in the same container",
            "10.  a\n        \tfoo\n",
            """
            document @1:1-3:1
              list ordered start=10 delim=period tight @1:1-2:13
                item @1:1-2:13
                  paragraph @1:6-2:13
                    text "a" @1:6-1:7
                    softbreak @-
                    text "foo" @2:10-2:13

            """
        ),
        Case(
            "two-digit ordered item, C, after a lazy continuation line",
            "10.  a\nb\n        \tfoo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period tight @1:1-3:13
                item @1:1-3:13
                  paragraph @1:6-3:13
                    text "a" @1:6-1:7
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:10-3:13

            """
        ),
        Case(
            "two-digit ordered item, C, after a closed fenced code block",
            "10.  a\n\n     ```\n     ```\n        \tfoo\n",
            """
            document @1:1-6:1
              list ordered start=10 delim=period loose @1:1-5:13
                item @1:1-5:13
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "" @3:6-4:9
                  code_block "" "   foo\\n" @5:9-5:13

            """
        ),
        Case(
            "two-digit ordered item, D, after a blank line",
            "10.  a\n\n\t\t    foo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "   foo\\n" @3:4-3:10

            """
        ),
        Case(
            "two-digit ordered item, D, after a paragraph in the same container",
            "10.  a\n\t\t    foo\n",
            """
            document @1:1-3:1
              list ordered start=10 delim=period tight @1:1-2:10
                item @1:1-2:10
                  paragraph @1:6-2:10
                    text "a" @1:6-1:7
                    softbreak @-
                    text "foo" @2:7-2:10

            """
        ),
        Case(
            "two-digit ordered item, D, after a lazy continuation line",
            "10.  a\nb\n\t\t    foo\n",
            """
            document @1:1-4:1
              list ordered start=10 delim=period tight @1:1-3:10
                item @1:1-3:10
                  paragraph @1:6-3:10
                    text "a" @1:6-1:7
                    softbreak @-
                    text "b" @2:1-2:2
                    softbreak @-
                    text "foo" @3:7-3:10

            """
        ),
        Case(
            "two-digit ordered item, D, after a closed fenced code block",
            "10.  a\n\n     ```\n     ```\n\t\t    foo\n",
            """
            document @1:1-6:1
              list ordered start=10 delim=period loose @1:1-5:10
                item @1:1-5:10
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "" @3:6-4:9
                  code_block "" "   foo\\n" @5:4-5:10

            """
        ),
        Case(
            "two-digit ordered item, continuation lines",
            "10.  a\n\n\t\t\tfoo\n     \t\tfoo\n        \tfoo\n\t\t    foo\n",
            """
            document @1:1-7:1
              list ordered start=10 delim=period loose @1:1-6:10
                item @1:1-6:10
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                  code_block "" "   foo\\n   foo\\n   foo\\n   foo\\n" @3:3-6:10

            """
        ),
        Case(
            "footnote definition in block quote, A, after a blank line",
            "x[^a]\n\n>[^a]: y\n>\n>\t\t\tfoo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:8
              footnote_definition "a" @3:2-5:8
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "  foo\\n" @5:4-5:8

            """
        ),
        Case(
            "footnote definition in block quote, A, after a paragraph in the same container",
            "x[^a]\n\n>[^a]: y\n>\t\t\tfoo\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-4:8
              footnote_definition "a" @3:2-4:8
                paragraph @3:8-4:8
                  text "y" @3:8-3:9
                  softbreak @-
                  text "foo" @4:5-4:8

            """
        ),
        Case(
            "footnote definition in block quote, A, after a lazy continuation line",
            "x[^a]\n\n>[^a]: y\nb\n>\t\t\tfoo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:8
              footnote_definition "a" @3:2-5:8
                paragraph @3:8-5:8
                  text "y" @3:8-3:9
                  softbreak @-
                  text "b" @4:1-4:2
                  softbreak @-
                  text "foo" @5:5-5:8

            """
        ),
        Case(
            "footnote definition in block quote, A, after a closed fenced code block",
            "x[^a]\n\n>[^a]: y\n>\n>     ```\n>     ```\n>\t\t\tfoo\n",
            """
            document @1:1-8:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-7:8
              footnote_definition "a" @3:2-7:8
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "" @5:7-6:10
                code_block "" "  foo\\n" @7:4-7:8

            """
        ),
        Case(
            "footnote definition in block quote, B, after a blank line",
            "x[^a]\n\n>[^a]: y\n>\n> \t\t\tfoo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:9
              footnote_definition "a" @3:2-5:9
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "  foo\\n" @5:5-5:9

            """
        ),
        Case(
            "footnote definition in block quote, B, after a paragraph in the same container",
            "x[^a]\n\n>[^a]: y\n> \t\t\tfoo\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-4:9
              footnote_definition "a" @3:2-4:9
                paragraph @3:8-4:9
                  text "y" @3:8-3:9
                  softbreak @-
                  text "foo" @4:6-4:9

            """
        ),
        Case(
            "footnote definition in block quote, B, after a lazy continuation line",
            "x[^a]\n\n>[^a]: y\nb\n> \t\t\tfoo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:9
              footnote_definition "a" @3:2-5:9
                paragraph @3:8-5:9
                  text "y" @3:8-3:9
                  softbreak @-
                  text "b" @4:1-4:2
                  softbreak @-
                  text "foo" @5:6-5:9

            """
        ),
        Case(
            "footnote definition in block quote, B, after a closed fenced code block",
            "x[^a]\n\n>[^a]: y\n>\n>     ```\n>     ```\n> \t\t\tfoo\n",
            """
            document @1:1-8:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-7:9
              footnote_definition "a" @3:2-7:9
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "" @5:7-6:10
                code_block "" "  foo\\n" @7:5-7:9

            """
        ),
        Case(
            "footnote definition in block quote, C, after a blank line",
            "x[^a]\n\n>[^a]: y\n>\n>       \tfoo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:13
              footnote_definition "a" @3:2-5:13
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "  foo\\n" @5:9-5:13

            """
        ),
        Case(
            "footnote definition in block quote, C, after a paragraph in the same container",
            "x[^a]\n\n>[^a]: y\n>       \tfoo\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-4:13
              footnote_definition "a" @3:2-4:13
                paragraph @3:8-4:13
                  text "y" @3:8-3:9
                  softbreak @-
                  text "foo" @4:10-4:13

            """
        ),
        Case(
            "footnote definition in block quote, C, after a lazy continuation line",
            "x[^a]\n\n>[^a]: y\nb\n>       \tfoo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:13
              footnote_definition "a" @3:2-5:13
                paragraph @3:8-5:13
                  text "y" @3:8-3:9
                  softbreak @-
                  text "b" @4:1-4:2
                  softbreak @-
                  text "foo" @5:10-5:13

            """
        ),
        Case(
            "footnote definition in block quote, C, after a closed fenced code block",
            "x[^a]\n\n>[^a]: y\n>\n>     ```\n>     ```\n>       \tfoo\n",
            """
            document @1:1-8:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-7:13
              footnote_definition "a" @3:2-7:13
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "" @5:7-6:10
                code_block "" "  foo\\n" @7:9-7:13

            """
        ),
        Case(
            "footnote definition in block quote, D, after a blank line",
            "x[^a]\n\n>[^a]: y\n>\n>\t\t  foo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:9
              footnote_definition "a" @3:2-5:9
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "foo\\n" @5:6-5:9

            """
        ),
        Case(
            "footnote definition in block quote, D, after a paragraph in the same container",
            "x[^a]\n\n>[^a]: y\n>\t\t  foo\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-4:9
              footnote_definition "a" @3:2-4:9
                paragraph @3:8-4:9
                  text "y" @3:8-3:9
                  softbreak @-
                  text "foo" @4:6-4:9

            """
        ),
        Case(
            "footnote definition in block quote, D, after a lazy continuation line",
            "x[^a]\n\n>[^a]: y\nb\n>\t\t  foo\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-5:9
              footnote_definition "a" @3:2-5:9
                paragraph @3:8-5:9
                  text "y" @3:8-3:9
                  softbreak @-
                  text "b" @4:1-4:2
                  softbreak @-
                  text "foo" @5:6-5:9

            """
        ),
        Case(
            "footnote definition in block quote, D, after a closed fenced code block",
            "x[^a]\n\n>[^a]: y\n>\n>     ```\n>     ```\n>\t\t  foo\n",
            """
            document @1:1-8:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-7:9
              footnote_definition "a" @3:2-7:9
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "" @5:7-6:10
                code_block "" "foo\\n" @7:6-7:9

            """
        ),
        Case(
            "footnote definition in block quote, continuation lines",
            "x[^a]\n\n>[^a]: y\n>\n>\t\t\tfoo\n> \t\t\tfoo\n>       \tfoo\n>\t\t  foo\n",
            """
            document @1:1-9:1
              paragraph @1:1-1:6
                text "x" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              block_quote @3:1-8:9
              footnote_definition "a" @3:2-8:9
                paragraph @3:8-3:9
                  text "y" @3:8-3:9
                code_block "" "  foo\\n  foo\\n  foo\\nfoo\\n" @5:4-8:9

            """
        ),
        Case(
            "top level, tab after spaces, first line",
            "  \tfoo\n",
            """
            document @1:1-2:1
              code_block "" "foo\\n" @1:4-1:7

            """
        ),
        Case(
            "top level, tab after spaces, after a blank line",
            "\n  \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "foo\\n" @2:4-2:7

            """
        ),
        Case(
            "top level, tab after spaces, after a paragraph in the same container",
            "a\n  \tfoo\n",
            """
            document @1:1-3:1
              paragraph @1:1-2:7
                text "a" @1:1-1:2
                softbreak @-
                text "foo" @2:4-2:7

            """
        ),
        Case(
            "top level, tab after spaces, after a closed fenced code block",
            "```\nx\n```\n  \tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              code_block "" "foo\\n" @4:4-4:7

            """
        ),
        Case(
            "top level, tab after spaces, after an indented code block",
            "    code\n  \tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\nfoo\\n" @1:5-2:7

            """
        ),
        Case(
            "top level, tab after three spaces then a tab, first line",
            "   \t\tfoo\n",
            """
            document @1:1-2:1
              code_block "" "\\tfoo\\n" @1:5-1:9

            """
        ),
        Case(
            "top level, tab after three spaces then a tab, after a blank line",
            "\n   \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "\\tfoo\\n" @2:5-2:9

            """
        ),
        Case(
            "top level, tab after three spaces then a tab, after a paragraph in the same container",
            "a\n   \t\tfoo\n",
            """
            document @1:1-3:1
              paragraph @1:1-2:9
                text "a" @1:1-1:2
                softbreak @-
                text "foo" @2:6-2:9

            """
        ),
        Case(
            "top level, tab after three spaces then a tab, after a closed fenced code block",
            "```\nx\n```\n   \t\tfoo\n",
            """
            document @1:1-5:1
              code_block "" "x\\n" @1:1-3:4
              code_block "" "\\tfoo\\n" @4:5-4:9

            """
        ),
        Case(
            "top level, tab after three spaces then a tab, after an indented code block",
            "    code\n   \t\tfoo\n",
            """
            document @1:1-3:1
              code_block "" "code\\n\\tfoo\\n" @1:5-2:9

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
