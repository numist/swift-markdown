/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Inline-only link reference definitions and hard line breaks")
struct InlineOnlyReferenceDefinitionAndHardBreakTests {

    private static let inlineOnly: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .inlineOnly,
    ]

    private static let preserveWhitespace: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace,
    ]

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func leadingDefinitionBeforeBlankLine(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u\n\n[a]", options: options) == """
            document
              paragraph
                text "\\n"
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func leadingDefinitionThenReference(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u\n[a]", options: options) == """
            document
              paragraph
                link "/u" ""
                  text "a"

            """)
        #expect(TreeDump.dump("[a]: /u \"t\"\nx [a]", options: options) == """
            document
              paragraph
                text "x "
                link "/u" "t"
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionDestinationOnNextLine(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]:\n/u\n\n[a]", options: options) == """
            document
              paragraph
                text "\\n"
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func indentedOrNonLeadingDefinitionStaysLiteral(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(" [a]: /u\n\n[a]", options: options) == """
            document
              paragraph
                text " [a]: /u\\n\\n[a]"

            """)
        #expect(TreeDump.dump("x\n[a]: /u\n[a]", options: options) == """
            document
              paragraph
                text "x\\n[a]: /u\\n[a]"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreak(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("a\\\nb", options: options) == """
            document
              paragraph
                text "a"
                linebreak
                text "b"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func trailingWhitespaceStaysLiteral(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("a  \nb", options: options) == """
            document
              paragraph
                text "a  \\nb"

            """)
        #expect(TreeDump.dump("a\t\nb", options: options) == """
            document
              paragraph
                text "a\\t\\nb"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func stackedLeadingDefinitions(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u\n[b]: /v\n[a] [b]", options: options) == """
            document
              paragraph
                link "/u" ""
                  text "a"
                text " "
                link "/v" ""
                  text "b"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionTitleSpanningLines(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u \"t\nu\"\n[a]", options: options) == """
            document
              paragraph
                link "/u" "t\\nu"
                  text "a"

            """)
        // `(t) x` is not a title, since only whitespace may follow a title on its line (Link reference definitions).
        #expect(TreeDump.dump("[a]: /u\n(t) x\n[a]", options: options) == """
            document
              paragraph
                text "(t) x\\n"
                link "/u" ""
                  text "a"

            """)
    }

    // Inline-only input keeps its paragraph even when definitions leave it empty.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionFollowedOnlyByWhitespace(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u\n", options: options) == """
            document
              paragraph

            """)
        #expect(TreeDump.dump("[a]: /u\n  ", options: options) == """
            document
              paragraph
                text "  "

            """)
        #expect(TreeDump.dump("[a]: /u \"t\"", options: options) == """
            document
              paragraph

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionDestinationAtEndOfInput(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u", options: options) == """
            document
              paragraph

            """)
        #expect(TreeDump.dump("[a]: /u\n[b]: /v", options: options) == """
            document
              paragraph

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionAfterCRLF(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: /u\r\n[a]", options: options) == """
            document
              paragraph
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreakEdges(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("a\\", options: options) == """
            document
              paragraph
                text "a\\\\"

            """)
        #expect(TreeDump.dump("a\\\r\nb", options: options) == """
            document
              paragraph
                text "a"
                linebreak
                text "b"

            """)
        #expect(TreeDump.dump("a\\\n", options: options) == """
            document
              paragraph
                text "a"
                linebreak

            """)
        // Inline-only mode keeps leading whitespace, including after a hard line break.
        #expect(TreeDump.dump("a\\\n  b", options: options) == """
            document
              paragraph
                text "a"
                linebreak
                text "  b"

            """)
        #expect(TreeDump.dump("a\\\\\nb", options: options) == """
            document
              paragraph
                text "a\\\\\\nb"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionEdgeForms(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a]: <>", options: options) == """
            document
              paragraph

            """)
        #expect(TreeDump.dump("[a]: <u> \"t\"\n[a]", options: options) == """
            document
              paragraph
                link "u" "t"
                  text "a"

            """)
        #expect(TreeDump.dump("[a]: /u ", options: options) == """
            document
              paragraph

            """)
        #expect(TreeDump.dump("^[x]: a\ny", options: options) == """
            document
              paragraph
                text "y"

            """)
        #expect(TreeDump.dump("^[x]: a", options: options) == """
            document
              paragraph

            """)
        #expect(TreeDump.dump("[a]: /u\n\u{0}[a]", options: options) == """
            document
              paragraph
                text "\u{FFFD}"
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreakAfterInlineConstruct(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("`x`\\\nb", options: options) == """
            document
              paragraph
                code "x"
                linebreak
                text "b"

            """)
        #expect(TreeDump.dump("*a*\\\nb", options: options) == """
            document
              paragraph
                emph
                  text "a"
                linebreak
                text "b"

            """)
    }
}
