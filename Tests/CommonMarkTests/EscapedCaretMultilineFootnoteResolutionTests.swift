/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote-shaped bracket that spans a line ending is literal text unless it is a footnote reference whose whole
/// label matches a definition: a backslash-escaped caret never opens one, and a definition matching only the bracket's
/// first line does not match.
@Suite("Footnote-shaped bracket across a line ending")
struct EscapedCaretMultilineFootnoteResolutionTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink, .footnotes]

    @Test func testBracketStaysLiteral() {
        let atCap = String(repeating: "a", count: 1000)
        let overCap = String(repeating: "a", count: 1001)
        let cases: [(markdown: String, expected: String)] = [
            ("[\\^abcdef\nxxxxx]\n\n[^abc]: note", """
                document
                  paragraph
                    text "[^abcdef"
                    softbreak
                    text "xxxxx]"

                """),
            ("[\\^abc\nxxxxx]\n\n[^abc]: note", """
                document
                  paragraph
                    text "[^abc"
                    softbreak
                    text "xxxxx]"

                """),
            ("![\\^abcdef\nxxxxx]\n\n[^abc]: note", """
                document
                  paragraph
                    text "![^abcdef"
                    softbreak
                    text "xxxxx]"

                """),
            ("[\\^ABCdef\nxxxxx]\n\n[^abc]: note", """
                document
                  paragraph
                    text "[^ABCdef"
                    softbreak
                    text "xxxxx]"

                """),
            ("[\\^\(atCap)bbb\n\(String(repeating: "x", count: 1002))]\n\n[^\(atCap)]: note", "document\n  paragraph\n    text \"[^\(atCap)bbb\"\n    softbreak\n    text \"\(String(repeating: "x", count: 1002))]\"\n"),
            ("[\\^\(overCap)bbb\n\(String(repeating: "x", count: 1003))]\n\n[^\(overCap)]: note", "document\n  paragraph\n    text \"[^\(overCap)bbb\"\n    softbreak\n    text \"\(String(repeating: "x", count: 1003))]\"\n"),
            ("[\\^a\u{0}bcdef\nxxxxxxx]\n\n[^a\u{0}b]: note", """
                document
                  paragraph
                    text "[^a\u{FFFD}bcdef"
                    softbreak
                    text "xxxxxxx]"

                """),
            ("[\\^abcdef\nxxxxx]\n[\\^abcdef\nxxxxx]\n\n[^abc]: note", """
                document
                  paragraph
                    text "[^abcdef"
                    softbreak
                    text "xxxxx]"
                    softbreak
                    text "[^abcdef"
                    softbreak
                    text "xxxxx]"

                """),
            ("[\\^abcdef\nxxxxx] [^abc]\n\n[^abc]: note", """
                document
                  paragraph
                    text "[^abcdef"
                    softbreak
                    text "xxxxx] "
                    footnote_reference "1"
                  footnote_definition "abc"
                    paragraph
                      text "note"

                """),
            ("[^zzz]\n[\\^abcdef\nxxxxx]\n\n[^abc]: a\n\n[^zzz]: z", """
                document
                  paragraph
                    footnote_reference "1"
                    softbreak
                    text "[^abcdef"
                    softbreak
                    text "xxxxx]"
                  footnote_definition "zzz"
                    paragraph
                      text "z"

                """),
            ("[\\^ab\nxxxxx]\n\n[^ab]: note", """
                document
                  paragraph
                    text "[^ab"
                    softbreak
                    text "xxxxx]"

                """),
            ("[\\^ab\u{E9}\nxxxxx]\n\n[^ab\u{FFFD}]: note", """
                document
                  paragraph
                    text "[^abé"
                    softbreak
                    text "xxxxx]"

                """),
            ("[^a\nx]\n\n[^a]: note", """
                document
                  paragraph
                    text "[^a"
                    softbreak
                    text "x]"

                """),
        ]
        for (markdown, expected) in cases {
            #expect(TreeDump.dump(markdown, options: Self.options) == expected, "\(markdown.debugDescription)")
        }
    }
}
