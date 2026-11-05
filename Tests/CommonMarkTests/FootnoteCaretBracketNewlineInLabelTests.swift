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

    /// `[^[` opens no footnote reference, because a label may not contain an unescaped `[` (Links). The bracket pair after
    /// `^[…]`, a link label or a blank one, names no attribute definition, so it is dropped and `^[…]` stays literal text.
    /// A bracket pair after another opener can still form a link or image.
    @Test func testBracketStaysLiteral() {
        let cases: [(markdown: String, expected: String)] = [
            ("[^[][\n]]", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^[][\nx]]", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^[][\r\n]]", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^[x][\n]]", """
                document
                  paragraph
                    text "[^[x]]"

                """),
            ("a [^[][\n]] b", """
                document
                  paragraph
                    text "a [^[]] b"

                """),
            ("[^[][ ]]", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^a ^[][\n]]", """
                document
                  paragraph
                    text "[^a ^[]]"

                """),
            ("[^[][\n]()]", """
                document
                  paragraph
                    text "[^[]()]"

                """),
            ("[^[][a\nb\nc]]", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^[][\n]\n]", """
                document
                  paragraph
                    text "[^[]"
                    softbreak
                    text "]"

                """),
            ("> [^[][\n> ]]", """
                document
                  block_quote
                    paragraph
                      text "[^[]]"

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
