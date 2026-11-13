/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// The lines before a setext heading underline are read as the paragraph they would be without it (Setext headings),
/// so the link reference definitions that paragraph begins with end at the underline and are final there. A later
/// underline, or the paragraph's close, reads only the lines past them. They still count as the paragraph's content,
/// and as its list item's first block (Task list items (extension)).
@Suite("Leading definitions at a setext underline")
struct SetextUnderlineDefinitionTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = [.sourcePosition]) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    @Test("a title that closes at an escaped quote before an underline ends there, and the next underline forms a heading")
    func titleEndsAtFirstUnderline() {
        #expect(tree("[a]: /u \"t\nx\n\\\"\n===\nx\n\\\"\n===\n") == """
            document @1:1-8:1
              heading 1 @4:1-7:4
                text "===" @4:1-4:4
                softbreak @-
                text "x" @5:1-5:2
                softbreak @-
                text "\\"" @6:1-6:3

            """)
    }

    @Test("a definition that ends at an underline keeps the title it has there")
    func definitionKeepsTitleAtUnderline() {
        #expect(tree("[a]: /u \"t\n\\\"\n===\n[a]\n===\n") == """
            document @1:1-6:1
              heading 1 @3:1-5:4
                text "===" @3:1-3:4
                softbreak @-
                link "/u" "t\\n\\\\" @4:1-4:4
                  text "a" @4:2-4:3

            """)
    }

    @Test("a paragraph of a definition and a line of only whitespace leaves nothing before a thematic break")
    func definitionAndWhitespaceOnlyLineBeforeThematicBreak() {
        #expect(tree("[a]: /u\n\u{0B}\n---\n") == """
            document @1:1-4:1
              thematic_break @3:1-3:4

            """)
    }

    @Test("a paragraph of a definition and a line of only whitespace leaves nothing before a thematic break in a block quote")
    func definitionAndWhitespaceOnlyLineBeforeThematicBreakInBlockQuote() {
        #expect(tree("> [a]: /u\n> \u{0B}\n> ---\n") == """
            document @1:1-4:1
              block_quote @1:1-3:6
                thematic_break @3:3-3:6

            """)
    }

    @Test("a definition and a line of only whitespace before a table's header row leave no paragraph")
    func definitionAndWhitespaceOnlyLineBeforeTable() {
        #expect(tree("[a]: /u\n\u{0B}\n\u{0C}\n-\n", options: [.tables, .sourcePosition]) == """
            document @1:1-5:1
              table @3:1-4:2
                table_header @3:1-3:1
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:1

            """)
    }

    @Test("a definition and a line of only whitespace before a table's header row leave no paragraph in a block quote")
    func definitionAndWhitespaceOnlyLineBeforeTableInBlockQuote() {
        #expect(tree("> [a]: /u\n> \u{0B}\n> \u{0C}\n> -\n", options: [.tables, .sourcePosition]) == """
            document @1:1-5:1
              block_quote @1:1-4:4
                table @3:3-4:4
                  table_header @3:3-3:3
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:3

            """)
    }

    @Test("a task list item marker after a definition an underline ends is paragraph text")
    func taskItemMarkerAfterDefinition() {
        #expect(tree("- [a]: /u\n  [ ] x\n  \u{0B}\n  ===\n", options: [.tasklist, .sourcePosition]) == """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:6
                item @1:1-4:6
                  paragraph @2:3-4:6
                    text "[ ] x" @2:3-2:8
                    softbreak @-
                    text "\\u{B}" @3:3-3:4
                    softbreak @-
                    text "===" @4:3-4:6

            """)
    }

    @Test("a task list item marker after a definition an underline ends is paragraph text with a NUL")
    func taskItemMarkerAfterDefinitionWithNUL() {
        #expect(tree("- [a]: /u\n[ ] x\u{0}\n\u{0B}\n  ===\n", options: [.tasklist, .sourcePosition]) == """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:6
                item @1:1-4:6
                  paragraph @2:1-4:6
                    text "[ ] x\u{FFFD}" @2:1-2:7
                    softbreak @-
                    text "\\u{B}" @3:1-3:2
                    softbreak @-
                    text "===" @4:3-4:6

            """)
    }

    @Test("a task list item marker after a definition an underline ends is paragraph text before a table")
    func taskItemMarkerAfterDefinitionBeforeTable() {
        #expect(tree("- [a]: /u\n  [ ] x\n  \u{0B}\n  ===\n  h|i\n  -|-\n", options: [.tasklist, .tables, .sourcePosition]) == """
            document @1:1-7:1
              list bullet '-' tight @1:1-6:6
                item @1:1-6:6
                  paragraph @2:3-4:6
                    text "[ ] x" @2:3-2:8
                    softbreak @-
                    text "\\u{B}" @3:3-3:4
                    softbreak @-
                    text "===" @4:3-4:6
                  table @5:3-6:6
                    table_header @5:3-5:6
                      table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                        text "h" @5:3-5:4
                      table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                        text "i" @5:5-5:6

            """)
    }

    @Test("a definition after a line of only whitespace past the definitions an underline ends is paragraph text")
    func definitionAfterWhitespaceOnlyLinePastUnderlineDefinitions() {
        #expect(tree("[a]: /u\n\u{0B}\n[b]: /v\n===\n\n[b]\n") == """
            document @1:1-7:1
              paragraph @3:1-4:4
                text "[b]: /v" @3:1-3:8
                softbreak @-
                text "===" @4:1-4:4
              paragraph @6:1-6:4
                text "[b]" @6:1-6:4

            """)
    }

    @Test("a definition after a line of only whitespace past the definitions an underline ends is paragraph text in a block quote")
    func definitionAfterWhitespaceOnlyLinePastUnderlineDefinitionsInBlockQuote() {
        #expect(tree("> [a]: /u\n> \u{0B}\n> [b]: /v\n> ===\n\n[b]\n") == """
            document @1:1-7:1
              block_quote @1:1-4:6
                paragraph @3:3-4:6
                  text "[b]: /v" @3:3-3:10
                  softbreak @-
                  text "===" @4:3-4:6
              paragraph @6:1-6:4
                text "[b]" @6:1-6:4

            """)
    }

    @Test("a definition after a form feed past the definitions an underline ends is paragraph text")
    func definitionAfterFormFeedPastUnderlineDefinitions() {
        #expect(tree("[a]: /u\n\u{0C}[b]: /v\n\u{0B}\n===\n\n[b]\n") == """
            document @1:1-7:1
              paragraph @2:2-4:4
                text "[b]: /v" @2:2-2:9
                softbreak @-
                text "\\u{B}" @3:1-3:2
                softbreak @-
                text "===" @4:1-4:4
              paragraph @6:1-6:4
                text "[b]" @6:1-6:4

            """)
    }

    @Test("a label after a form feed past the definitions an underline ends begins no definition")
    func labelAfterFormFeedPastUnderlineDefinitions() {
        #expect(tree("[a]: /u\n\u{0C}[b\n\u{0B}\n=\n]: /v\nx\n=\n") == """
            document @1:1-8:1
              paragraph @2:2-7:2
                text "[b" @2:2-2:4
                softbreak @-
                text "\\u{B}" @3:1-3:2
                softbreak @-
                text "=" @4:1-4:2
                softbreak @-
                text "]: /v" @5:1-5:6
                softbreak @-
                text "x" @6:1-6:2
                softbreak @-
                text "=" @7:1-7:2

            """)
    }

    @Test("a definition after a line of only whitespace past the definitions an underline ends is paragraph text before a table")
    func definitionAfterWhitespaceOnlyLinePastUnderlineDefinitionsBeforeTable() {
        #expect(tree("[a]: /u\n\u{0B}\n[b]: /v\n===\nh|i\n-|-\n\n[b]\n", options: [.tables, .sourcePosition]) == """
            document @1:1-9:1
              paragraph @3:1-4:4
                text "[b]: /v" @3:1-3:8
                softbreak @-
                text "===" @4:1-4:4
              table @5:1-6:4
                table_header @5:1-5:4
                  table_cell align=none colspan=1 rowspan=1 @5:1-5:2
                    text "h" @5:1-5:2
                  table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                    text "i" @5:3-5:4
              paragraph @8:1-8:4
                text "[b]" @8:1-8:4

            """)
    }

    @Test("a definition after a line of only whitespace past the definitions an underline ends is paragraph text before a table in a block quote")
    func definitionAfterWhitespaceOnlyLinePastUnderlineDefinitionsBeforeTableInBlockQuote() {
        #expect(tree("> [a]: /u\n> \u{0B}\n> [b]: /v\n> ===\n> h|i\n> -|-\n\n[b]\n", options: [.tables, .sourcePosition]) == """
            document @1:1-9:1
              block_quote @1:1-6:6
                paragraph @3:3-4:6
                  text "[b]: /v" @3:3-3:10
                  softbreak @-
                  text "===" @4:3-4:6
                table @5:3-6:6
                  table_header @5:3-5:6
                    table_cell align=none colspan=1 rowspan=1 @5:3-5:4
                      text "h" @5:3-5:4
                    table_cell align=none colspan=1 rowspan=1 @5:5-5:6
                      text "i" @5:5-5:6
              paragraph @8:1-8:4
                text "[b]" @8:1-8:4

            """)
    }

    /// Lines that many underlines follow.
    struct Shape: Sendable, CustomTestStringConvertible {
        let prefix: String
        let line: String
        /// The tree of `prefix` followed by `count` copies of `line`.
        let tree: @Sendable (_ count: Int) -> String
        let testDescription: String
    }

    static let shapes: [Shape] = [
        Shape(
            prefix: "[a]: /u \"t\n",
            line: "x\n\\\"\n===\n",
            tree: { count in
                "document\n  heading 1\n    text \"===\"\n    softbreak\n    text \"x\"\n    softbreak\n    text \"\\\"\"\n"
                    + String(repeating: "  heading 1\n    text \"x\"\n    softbreak\n    text \"\\\"\"\n", count: count - 2)
            },
            testDescription: "a title that closes at an escaped quote before the first underline, and an escaped quote before each later one"
        ),
        Shape(
            prefix: "[a]: /u \"t\n",
            line: "\u{0B}\n\\\"\n===\n",
            tree: { count in
                "document\n  paragraph\n    text \"===\"\n"
                    + String(repeating: "    softbreak\n    text \"\\u{B}\"\n    softbreak\n    text \"\\\"\"\n    softbreak\n    text \"===\"\n", count: count - 1)
            },
            testDescription: "a title that closes at an escaped quote before a line of only whitespace"
        ),
        Shape(
            prefix: "[a]: /u \"t\n\u{0B}\n",
            line: "'\n===\n",
            tree: { count in
                "document\n  paragraph\n    text \"[a]: /u \\\"t\"\n    softbreak\n    text \"\\u{B}\"\n"
                    + String(repeating: "    softbreak\n    text \"'\"\n    softbreak\n    text \"===\"\n", count: count)
            },
            testDescription: "an open title with a line of only whitespace and lines of a quote it doesn't close at"
        ),
        Shape(
            prefix: "[a]: /u \"t\n\u{0B}\n",
            line: "]\n===\n",
            tree: { count in
                "document\n  paragraph\n    text \"[a]: /u \\\"t\"\n    softbreak\n    text \"\\u{B}\"\n"
                    + String(repeating: "    softbreak\n    text \"]\"\n    softbreak\n    text \"===\"\n", count: count)
            },
            testDescription: "an open title with a line of only whitespace and lines of a bracket"
        ),
        Shape(
            prefix: "[a]: /u \"t\n\u{0B}\n",
            line: "x\\\" y\n===\n",
            tree: { count in
                "document\n  paragraph\n    text \"[a]: /u \\\"t\"\n    softbreak\n    text \"\\u{B}\"\n"
                    + String(repeating: "    softbreak\n    text \"x\\\" y\"\n    softbreak\n    text \"===\"\n", count: count)
            },
            testDescription: "an open title with a line of only whitespace and closers followed by more text"
        ),
        Shape(
            prefix: "> [a]: /u \"t\n> \u{0B}\n",
            line: "> '\n> ===\n",
            tree: { count in
                "document\n  block_quote\n    paragraph\n      text \"[a]: /u \\\"t\"\n      softbreak\n      text \"\\u{B}\"\n"
                    + String(repeating: "      softbreak\n      text \"'\"\n      softbreak\n      text \"===\"\n", count: count)
            },
            testDescription: "an open title with a line of only whitespace in a block quote"
        ),
        Shape(
            prefix: "[a\n\u{0B}\n",
            line: "===\n",
            tree: { count in
                "document\n  paragraph\n    text \"[a\"\n    softbreak\n    text \"\\u{B}\"\n"
                    + String(repeating: "    softbreak\n    text \"===\"\n", count: count)
            },
            testDescription: "an open label with a line of only whitespace"
        ),
    ]

    @Test(.timeLimit(.minutes(1)), arguments: shapes)
    func manyUnderlines(_ shape: Shape) {
        let source = shape.prefix + String(repeating: shape.line, count: 40_000)
        #expect(TreeDump.dump(source, options: []) == shape.tree(40_000))
    }

    @Test(arguments: shapes)
    func fewUnderlines(_ shape: Shape) {
        #expect(TreeDump.dump(shape.prefix + String(repeating: shape.line, count: 3), options: []) == shape.tree(3))
    }
}
