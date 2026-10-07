/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Definition lookup for a footnote-shaped bracket whose caret is immediately followed by `[`
/// (`[^[…]`).
@Suite("Footnote caret-bracket resolution")
struct FootnoteCaretBracketResolutionTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    private static func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    @Test
    func withoutCompatibilityBracketStaysLiteral() {
        #expect(Self.surface("[^[]]\n\n[^\\[]: n") == """
            document
              paragraph
                text "[^[]]"

            """)
        #expect(Self.surface("[^[]:[^[]]") == """
            document
              paragraph
                text "[^[]:[^[]]"

            """)
    }

    /// A footnote-shaped bracket whose caret is followed by `[` is no footnote reference, so it stays literal text,
    /// even beside a definition of the escaped label `\[`. A definition label may not hold an unescaped `[`, as a
    /// link label may not (spec "Links"), so `[^[]:` defines nothing.
    @Test(arguments: [
            ("[^[]]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^\\[]: n\n\n[^[]]", """
                document
                  paragraph
                    text "[^[]]"

                """),
            ("[^[a]]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "[^[a]]"

                """),
            ("[^[]a]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "[^[]a]"

                """),
            ("[^[]\nabcd]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "[^[]"
                    softbreak
                    text "abcd]"

                """),
            ("[^[\nabcd]]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "[^["
                    softbreak
                    text "abcd]]"

                """),
            ("[^[" + String(repeating: "a", count: 998) + "]]\n\n[^\\[]: n", "document\n  paragraph\n    text \"[^[" + String(repeating: "a", count: 998) + "]]\"\n"),
            ("![^[]]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "![^[]]"

                """),
            ("[[^[]]]\n\n[^\\[]: n", """
                document
                  paragraph
                    text "[[^[]]]"

                """),
            ("[[^[]]](/u)\n\n[^\\[]: n", """
                document
                  paragraph
                    link "/u" ""
                      text "[^[]]"

                """),
            ("[^a] [^[x]]\n\n[^a]: m\n\n[^\\[]: n", """
                document
                  paragraph
                    footnote_reference "1"
                    text " [^[x]]"
                  footnote_definition "a"
                    paragraph
                      text "m"

                """),
            ("[^[]:[^[]]", """
                document
                  paragraph
                    text "[^[]:[^[]]"

                """),
            ("[^[" + String(repeating: "a", count: 999) + "]]\n\n[^\\[]: n", "document\n  paragraph\n    text \"[^[" + String(repeating: "a", count: 999) + "]]\"\n"),
            ("[^[]]\n\n[^\\[a]: n", """
                document
                  paragraph
                    text "[^[]]"

                """),    ] as [(String, String)])
    func withoutCompatibilityEveryBracketStaysLiteral(_ markdown: String, _ expected: String) {
        #expect(Self.surface(markdown) == expected)
    }
}
