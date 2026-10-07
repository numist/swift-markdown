/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote-shaped bracket whose `]` is on a later line resolves only against a definition matching its whole label.
/// A definition whose label holds U+FFFD in place of the bracket's first-line characters does not match, so the
/// bracket stays literal text around the soft line break.
@Suite("Footnote-shaped bracket across a line ending: definition lookup")
struct FootnoteCrossLineBracketLookupTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    private static func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    @Test
    func bracketStaysLiteral() {
        #expect(Self.surface("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n") == """
            document
              paragraph
                text "[^\u{2003}"
                softbreak
                text "xxxx]"

            """)
        #expect(Self.surface("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}]: n") == """
            document
              paragraph
                text "[^\u{2003}"
                softbreak
                text "xxxx]"

            """)
    }

    @Test(arguments: [
            ("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", """
                document
                  paragraph
                    text "[^\u{2003}"
                    softbreak
                    text "xxxx]"

                """),
            ("[^\u{1F600}\nxxxxx]\n\n[^\u{FFFD}\u{FFFD}\u{FFFD}]: n", """
                document
                  paragraph
                    text "[^😀"
                    softbreak
                    text "xxxxx]"

                """),
            ("[^a\u{20AC}\nxxxxx]\n\n[^a\u{FFFD}\u{FFFD}]: n", """
                document
                  paragraph
                    text "[^a€"
                    softbreak
                    text "xxxxx]"

                """),
            ("[\\^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", """
                document
                  paragraph
                    text "[^\u{2003}"
                    softbreak
                    text "xxxx]"

                """),
            ("![\\^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", """
                document
                  paragraph
                    text "![^\u{2003}"
                    softbreak
                    text "xxxx]"

                """),
            ("[^\u{FFFD}\nxxx]\n\n[^\u{FFFD}]: n", """
                document
                  paragraph
                    text "[^\u{FFFD}"
                    softbreak
                    text "xxx]"

                """),
    ])
    func everyBracketStaysLiteral(_ markdown: String, _ expected: String) {
        #expect(Self.surface(markdown) == expected)
    }
}
