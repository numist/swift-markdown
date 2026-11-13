/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The parse options `.inlineOnly` and `.preserveWhitespace`.
///
/// Neither recognizes block structure other than link reference definitions at the start of the input: the rest of the
/// input is one paragraph, so block markers such as `#`, `* `, `> `, `---` and a 4-space indent are text, and line
/// endings, blank lines and leading and trailing whitespace stay in the paragraph's text, except that a line ending
/// after a backslash is a hard line break. Inline syntax is parsed. The two options produce the same tree.
@Suite("Parse options - inlineOnly / preserveWhitespace")
struct InlineOnlyOptionTests {

    private static let inlineOnlyOptions: [MarkdownDocument.ParseOptions] = [.inlineOnly, .preserveWhitespace]

    @Test("inline-only parsing keeps heading and list item markers as text in one paragraph", arguments: inlineOnlyOptions)
    func suppressesBlocks(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("# heading\n\n* item", options: options) == """
            document
              paragraph
                text "# heading\\n\\n* item"

            """)
    }

    @Test("inline-only parsing recognizes emphasis and code spans", arguments: inlineOnlyOptions)
    func keepsInlineSyntax(options: MarkdownDocument.ParseOptions) {
        let source = "# *em* and `code`"
        #expect(TreeDump.dump(source, options: options) == """
            document
              paragraph
                text "# "
                emph
                  text "em"
                text " and "
                code "code"

            """)
        let kinds = MarkdownDocument.withParsedDocument(source, options: options) {
            dfs($0).map { TreeDump.describe($0.kind) }
        }
        #expect(kinds == ["document", "paragraph", "text", "emph", "text", "text", "code backticks=1"])
    }

    @Test("inline-only parsing recognizes links", arguments: inlineOnlyOptions)
    func parsesLinks(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("see [text](http://example.com) ok", options: options) == """
            document
              paragraph
                text "see "
                link "http://example.com" ""
                  text "text"
                text " ok"

            """)
    }

    @Test("inline-only parsing does not turn a 4-space indent into a code block", arguments: inlineOnlyOptions)
    func noIndentedCodeBlock(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("    indented code", options: options) == """
            document
              paragraph
                text "    indented code"

            """)
    }

    @Test("inline-only parsing leaves a block quote marker as literal text", arguments: inlineOnlyOptions)
    func noBlockQuote(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("> not a quote", options: options) == """
            document
              paragraph
                text "> not a quote"

            """)
    }

    @Test("inline-only parsing keeps leading and trailing whitespace and blank lines", arguments: inlineOnlyOptions)
    func keepsWhitespace(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("   leading   spaces\n\n\ntrailing  ", options: options) == """
            document
              paragraph
                text "   leading   spaces\\n\\n\\ntrailing  "

            """)
        #expect(TreeDump.dump("  # x\n\n  *y*  \n\n> z", options: options) == """
            document
              paragraph
                text "  # x\\n\\n  "
                emph
                  text "y"
                text "  \\n\\n> z"

            """)
    }

    @Test("preserveWhitespace is a superset that includes inlineOnly")
    func preserveWhitespaceImpliesInlineOnly() {
        #expect(MarkdownDocument.ParseOptions.preserveWhitespace.contains(.inlineOnly))
    }
}
