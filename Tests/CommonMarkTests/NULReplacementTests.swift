/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Every U+0000 in the input is replaced with U+FFFD (Insecure characters), in every kind of content.
/// Other control characters are kept.
@Suite("NUL replacement (U+0000 -> U+FFFD)")
struct NULReplacementTests {

    @Test("NUL in paragraph text becomes U+FFFD")
    func paragraphText() {
        #expect(TreeDump.dump("a\u{0}b", options: []) == """
            document
              paragraph
                text "a\u{FFFD}b"

            """)
    }

    @Test("NUL in a code span becomes U+FFFD")
    func codeSpan() {
        #expect(TreeDump.dump("`\u{0}`", options: []) == """
            document
              paragraph
                code "\u{FFFD}"

            """)
    }

    @Test("NUL in a fenced code block body becomes U+FFFD")
    func fencedCodeBlock() {
        #expect(TreeDump.dump("```\n\u{0}\n```", options: []) == """
            document
              code_block "" "\u{FFFD}\\n"

            """)
    }

    @Test("NUL in an indented code block body becomes U+FFFD")
    func indentedCodeBlock() {
        #expect(TreeDump.dump("    \u{0}", options: []) == """
            document
              code_block "" "\u{FFFD}\\n"

            """)
    }

    @Test("NUL in a fenced code block info string becomes U+FFFD")
    func codeBlockInfoString() {
        #expect(TreeDump.dump("```\u{0}x\n\n```", options: []) == """
            document
              code_block "\u{FFFD}x" "\\n"

            """)
    }

    @Test("NUL in an HTML block body becomes U+FFFD")
    func htmlBlock() {
        #expect(TreeDump.dump("<div>\n\u{0}\n</div>", options: []) == """
            document
              html_block "<div>\\n\u{FFFD}\\n</div>\\n"

            """)
    }

    @Test("NUL in an inline link destination becomes U+FFFD")
    func inlineLinkDestination() {
        #expect(TreeDump.dump("[a](\u{0})", options: []) == """
            document
              paragraph
                link "\u{FFFD}" ""
                  text "a"

            """)
    }

    @Test("NUL in a reference-definition destination becomes U+FFFD")
    func referenceDefinitionDestination() {
        #expect(TreeDump.dump("[a]\n\n[a]: \u{0}", options: []) == """
            document
              paragraph
                link "\u{FFFD}" ""
                  text "a"

            """)
    }

    /// The `===` line follows a paragraph holding only a link reference definition, which it cannot
    /// underline (Setext headings).
    @Test("NUL in a link reference definition destination followed by `===` becomes U+FFFD")
    func setextStrippedReferenceDefinition() {
        #expect(TreeDump.dump("[a]: /u\u{0}\n===\n\n[a]", options: []) == """
            document
              paragraph
                text "==="
              paragraph
                link "/u\u{FFFD}" ""
                  text "a"

            """)
    }

    @Test("NUL in a footnote definition's content becomes U+FFFD")
    func footnoteDefinitionContent() {
        #expect(TreeDump.dump("[^a]: x\u{0}\n\n[^a]", options: [.footnotes]) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x\u{FFFD}"

            """)
    }

    @Test("NUL in an ATX heading becomes U+FFFD")
    func atxHeading() {
        #expect(TreeDump.dump("# \u{0}", options: []) == """
            document
              heading 1
                text "\u{FFFD}"

            """)
    }

    @Test("NUL in a setext heading becomes U+FFFD")
    func setextHeading() {
        #expect(TreeDump.dump("a\u{0}\n==", options: []) == """
            document
              heading 1
                text "a\u{FFFD}"

            """)
    }

    @Test("NUL in a paragraph continued across block quote lines becomes U+FFFD")
    func blockQuoteMultiline() {
        #expect(TreeDump.dump("> a\u{0}\n> b", options: []) == """
            document
              block_quote
                paragraph
                  text "a\u{FFFD}"
                  softbreak
                  text "b"

            """)
    }

    /// A URI autolink (Autolinks) excludes ASCII control characters; U+FFFD is not one.
    @Test("NUL inside an angle-bracket autolink body forms a link with a U+FFFD destination")
    func angleAutolinkBody() {
        #expect(TreeDump.dump("<http://a\u{0}b>", options: []) == """
            document
              paragraph
                link "http://a\u{FFFD}b" ""
                  text "http://a\u{FFFD}b"

            """)
    }

    @Test("NUL in a GFM table cell becomes U+FFFD")
    func tableCell() {
        #expect(TreeDump.dump("h\u{0}\n|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "h\u{FFFD}"

            """)
    }

    @Test("NUL in inline-only mode becomes U+FFFD")
    func inlineOnly() {
        #expect(TreeDump.dump("a\u{0}b", options: [.inlineOnly]) == """
            document
              paragraph
                text "a\u{FFFD}b"

            """)
    }

    @Test("NUL in an inline `^[..](..)` attribute becomes U+FFFD")
    func inlineAttribute() {
        #expect(TreeDump.dump("^[x](a\u{0}b)", options: [.attributes]) == """
            document
              paragraph
                attribute "a\u{FFFD}b"
                  text "x"

            """)
    }

    @Test("NUL in a reference-form `^[label]: ..` attribute becomes U+FFFD")
    func referenceAttribute() {
        #expect(TreeDump.dump("^[label]: a\u{0}b\n\n^[content][label]", options: [.attributes]) == """
            document
              paragraph
                attribute "a\u{FFFD}b"
                  text "content"

            """)
    }

    @Test("other C0 control bytes are left literal (only NUL is replaced)", arguments: [
        ("a\u{1}b", """
            document
              paragraph
                text "a\\u{1}b"

            """),
        ("a\u{8}b", """
            document
              paragraph
                text "a\\u{8}b"

            """),
        ("a\u{1F}b", """
            document
              paragraph
                text "a\\u{1F}b"

            """),
    ])
    func otherControlBytesUnchanged(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: []) == tree)
    }
}
