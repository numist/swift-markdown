/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Tests for the extended parse options `.inlineOnly` and `.preserveWhitespace`.
///
/// Ground-truth behavior at the parser / AST level:
///  - No block containers are ever opened. Markers like `#`, `* `, `> `, `---`, ` ``` ` and 4-space indents stay literal text rather than producing headings / lists / quotes / thematic breaks / code blocks.
///  - Inline syntax is still parsed (emphasis, code spans, links, …).
///  - Leading and trailing whitespace is preserved.
///  - At the parser level `.inlineOnly` and `.preserveWhitespace` produce an identical tree; the whitespace *collapsing* that distinguishes the two modes happens in a higher rendering layer, not in the parser.
@Suite("Parse options - inlineOnly / preserveWhitespace")
struct InlineOnlyOptionTests {

    private static let inlineOnlyOptions: [MarkdownDocument.ParseOptions] = [.inlineOnly, .preserveWhitespace]

    // MARK: - inlineOnly

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

    // MARK: - preserveWhitespace

    @Test("preserveWhitespace is a superset that includes inlineOnly")
    func preserveWhitespaceImpliesInlineOnly() {
        // Pure option-set composition - independent of the parser implementation.
        #expect(MarkdownDocument.ParseOptions.preserveWhitespace.contains(.inlineOnly))
    }
}
