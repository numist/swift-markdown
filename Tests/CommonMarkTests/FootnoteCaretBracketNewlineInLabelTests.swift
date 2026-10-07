/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A bracket opening `[^[`, followed by a bracket pair that spans a line ending.
@Suite("Footnote-shaped bracket holding an attribute opener across a line ending")
struct FootnoteCaretBracketNewlineInLabelTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink, .footnotes]

    /// `[^[` opens no footnote reference, because a label may not contain an unescaped `[` (Links), and `^[]` followed
    /// by `[` rather than `(` is not inline attributes. The brackets stay literal text unless a later pair forms a link.
    @Test func testBracketStaysLiteral() {
        let cases: [(markdown: String, expected: String)] = [
            ("[^[][\n]]", """
                document
                  paragraph
                    text "[^[]["
                    softbreak
                    text "]]"

                """),
            ("[^[][\nx]]", """
                document
                  paragraph
                    text "[^[]["
                    softbreak
                    text "x]]"

                """),
            ("[^[][\r\n]]", """
                document
                  paragraph
                    text "[^[]["
                    softbreak
                    text "]]"

                """),
            ("[^[x][\n]]", """
                document
                  paragraph
                    text "[^[x]["
                    softbreak
                    text "]]"

                """),
            ("a [^[][\n]] b", """
                document
                  paragraph
                    text "a [^[]["
                    softbreak
                    text "]] b"

                """),
            ("[^[][ ]]", """
                document
                  paragraph
                    text "[^[][ ]]"

                """),
            ("[^a ^[][\n]]", """
                document
                  paragraph
                    text "[^a ^[]["
                    softbreak
                    text "]]"

                """),
            ("[^[][\n]()]", """
                document
                  paragraph
                    text "[^[]"
                    link "" ""
                      softbreak
                    text "]"

                """),
            ("[^[][a\nb\nc]]", """
                document
                  paragraph
                    text "[^[][a"
                    softbreak
                    text "b"
                    softbreak
                    text "c]]"

                """),
            ("[^[][\n]\n]", """
                document
                  paragraph
                    text "[^[]["
                    softbreak
                    text "]"
                    softbreak
                    text "]"

                """),
            ("> [^[][\n> ]]", """
                document
                  block_quote
                    paragraph
                      text "[^[]["
                      softbreak
                      text "]]"

                """),
            ("[^x ![a][b\nc]]\n\n[b c]: /u", """
                document
                  paragraph
                    text "[^x "
                    image "/u" ""
                      text "a"
                    text "]"

                """),
        ]
        for (markdown, expected) in cases {
            #expect(TreeDump.dump(markdown, options: Self.options) == expected, "\(markdown.debugDescription)")
        }
    }
}
