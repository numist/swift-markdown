/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Definition lookup for a footnote-shaped bracket whose `]` lands on a later line.
///
/// A footnote reference never spans a line, so the bracket stays literal text around a soft break.
@Suite("Footnote cross-line truncated capture lookup")
struct FootnoteCrossLineTruncatedCaptureLookupTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    private static func surface(_ markdown: String) -> String {
        CmarkTreeDump.dump(markdown, options: Self.options)
    }

    @Test
    func withoutCompatibilityBracketStaysLiteral() {
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

    /// Flag-off a footnote reference never spans a line, so the bracket stays literal text around a soft break.
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
    func withoutCompatibilityTruncatedCaptureStaysLiteral(_ markdown: String, _ expected: String) {
        #expect(Self.surface(markdown) == expected)
    }
}
