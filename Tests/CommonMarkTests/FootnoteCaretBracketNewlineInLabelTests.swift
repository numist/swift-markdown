/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Bracket pair after an attribute or image bracket inside a footnote-shaped bracket")
struct FootnoteCaretBracketNewlineInLabelTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink, .footnotes]

    // A bracket pair after `^[…]`, a blank one included, is taken as an attribute label even when it names no
    // attribute definition, so it is dropped from the text.
    @Test(arguments: [
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
    ])
    func bracketStaysLiteral(markdown: String, expected: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == expected)
    }
}
