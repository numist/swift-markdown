/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline-only parsing extracts leading link reference definitions and turns a backslash before a line ending into a
/// hard line break.
@Suite("Inline-only reference definitions and hard breaks")
struct InlineOnlyReferenceDefinitionAndHardBreakTests {

    private static let inlineOnly: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .inlineOnly,
    ]

    private static let preserveWhitespace: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace,
    ]

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func leadingDefinitionBeforeBlankLine(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\n\n[a]", options: options) == """
            document
              paragraph
                text "\\n"
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func leadingDefinitionThenReference(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\n[a]", options: options) == """
            document
              paragraph
                link "/u" ""
                  text "a"

            """)
        #expect(CmarkTreeDump.dump("[a]: /u \"t\"\nx [a]", options: options) == """
            document
              paragraph
                text "x "
                link "/u" "t"
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionDestinationOnNextLine(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]:\n/u\n\n[a]", options: options) == """
            document
              paragraph
                text "\\n"
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func literalDefinitionControls(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u", options: options) == """
            document
              paragraph
                text "[a]: /u"

            """)
        #expect(CmarkTreeDump.dump(" [a]: /u\n\n[a]", options: options) == """
            document
              paragraph
                text " [a]: /u\\n\\n[a]"

            """)
        #expect(CmarkTreeDump.dump("x\n[a]: /u\n[a]", options: options) == """
            document
              paragraph
                text "x\\n[a]: /u\\n[a]"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreak(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\\\nb", options: options) == """
            document
              paragraph
                text "a"
                linebreak
                text "b"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func trailingWhitespaceStaysLiteral(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a  \nb", options: options) == """
            document
              paragraph
                text "a  \\nb"

            """)
        #expect(CmarkTreeDump.dump("a\t\nb", options: options) == """
            document
              paragraph
                text "a\\t\\nb"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func stackedLeadingDefinitions(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\n[b]: /v\n[a] [b]", options: options) == """
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
        #expect(CmarkTreeDump.dump("[a]: /u \"t\nu\"\n[a]", options: options) == """
            document
              paragraph
                link "/u" "t\\nu"
                  text "a"

            """)
        // A next-line title with trailing content is rejected; the definition ends after its destination.
        #expect(CmarkTreeDump.dump("[a]: /u\n(t) x\n[a]", options: options) == """
            document
              paragraph
                text "(t) x\\n"
                link "/u" ""
                  text "a"

            """)
    }

    /// cmark keeps the paragraph (now empty, or whitespace-only) after extracting every definition: its
    /// empty-paragraph removal is gated off in inline-only modes.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionFollowedOnlyByWhitespace(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\n", options: options) == """
            document
              paragraph

            """)
        #expect(CmarkTreeDump.dump("[a]: /u\n  ", options: options) == """
            document
              paragraph
                text "  "

            """)
        #expect(CmarkTreeDump.dump("[a]: /u \"t\"", options: options) == """
            document
              paragraph

            """)
    }

    /// cmark's bare-destination scan fails when the destination reaches the very end of the input, which
    /// only inline-only content (no newline appended to its final line) can hit.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionDestinationAtEndOfInputStaysLiteral(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\n[b]: /v", options: options) == """
            document
              paragraph
                text "[b]: /v"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionAfterCRLF(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\r\n[a]", options: options) == """
            document
              paragraph
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreakEdges(options: MarkdownDocument.ParseOptions) {
        // At end of input the backslash is literal.
        #expect(CmarkTreeDump.dump("a\\", options: options) == """
            document
              paragraph
                text "a\\\\"

            """)
        #expect(CmarkTreeDump.dump("a\\\r\nb", options: options) == """
            document
              paragraph
                text "a"
                linebreak
                text "b"

            """)
        #expect(CmarkTreeDump.dump("a\\\n", options: options) == """
            document
              paragraph
                text "a"
                linebreak

            """)
        // The next line's leading spaces stay literal.
        #expect(CmarkTreeDump.dump("a\\\n  b", options: options) == """
            document
              paragraph
                text "a"
                linebreak
                text "  b"

            """)
        // An escaped backslash does not break.
        #expect(CmarkTreeDump.dump("a\\\\\nb", options: options) == """
            document
              paragraph
                text "a\\\\\\nb"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func definitionEdgeForms(options: MarkdownDocument.ParseOptions) {
        // A pointy destination reaching the end of input is rejected like a bare one.
        #expect(CmarkTreeDump.dump("[a]: <>", options: options) == """
            document
              paragraph
                text "[a]: <>"

            """)
        #expect(CmarkTreeDump.dump("[a]: <u> \"t\"\n[a]", options: options) == """
            document
              paragraph
                link "u" "t"
                  text "a"

            """)
        // Trailing space after the destination keeps it off the end of input, so the definition is consumed.
        #expect(CmarkTreeDump.dump("[a]: /u ", options: options) == """
            document
              paragraph

            """)
        // Attribute definitions are consumed too; they have no destination, so one ending the input is accepted.
        #expect(CmarkTreeDump.dump("^[x]: a\ny", options: options) == """
            document
              paragraph
                text "y"

            """)
        #expect(CmarkTreeDump.dump("^[x]: a", options: options) == """
            document
              paragraph

            """)
        // NUL forces the arena path; the definition is still consumed and the NUL becomes U+FFFD.
        #expect(CmarkTreeDump.dump("[a]: /u\n\u{0}[a]", options: options) == """
            document
              paragraph
                text "\u{FFFD}"
                link "/u" ""
                  text "a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreakAfterInlineConstruct(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("`x`\\\nb", options: options) == """
            document
              paragraph
                code "x"
                linebreak
                text "b"

            """)
        #expect(CmarkTreeDump.dump("*a*\\\nb", options: options) == """
            document
              paragraph
                emph
                  text "a"
                linebreak
                text "b"

            """)
    }
}
