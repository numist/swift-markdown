/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote definition's label holds no whitespace, so a footnote-shaped bracket with a line ending between two
/// non-whitespace characters after its caret matches no footnote definition. With no matching link reference
/// definition, the bracket stays literal text around the soft line break.
@Suite("Footnote-shaped bracket across a line ending: definition lookup")
struct FootnoteCrossLineBracketLookupTests {
    private static func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: .footnotes)
    }

    @Test(arguments: [
            ("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", """
                document
                  paragraph
                    text "[^\u{2003}"
                    softbreak
                    text "xxxx]"

                """),
            ("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}]: n", """
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
        #expect(Self.tree(markdown) == expected)
    }
}
