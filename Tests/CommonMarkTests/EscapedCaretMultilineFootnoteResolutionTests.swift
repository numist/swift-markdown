/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote definition's label holds no whitespace, so a footnote-shaped bracket that spans a line ending is no
/// footnote reference; with only footnote definitions to match, it is literal text, whether its caret is
/// backslash-escaped or a definition matches the bracket's first line.
@Suite("Footnote-shaped bracket across a line ending")
struct EscapedCaretMultilineFootnoteResolutionTests {
    private static let long = String(repeating: "a", count: 998)

    static let cases: [(markdown: String, expected: String)] = [
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
        ("[\\^\(Self.long)bbb\n\(String(repeating: "x", count: 1000))]\n\n[^\(Self.long)]: note", "document\n  paragraph\n    text \"[^\(Self.long)bbb\"\n    softbreak\n    text \"\(String(repeating: "x", count: 1000))]\"\n"),
        ("[\\^\(Self.long)abbb\n\(String(repeating: "x", count: 1001))]\n\n[^\(Self.long)a]: note", "document\n  paragraph\n    text \"[^\(Self.long)abbb\"\n    softbreak\n    text \"\(String(repeating: "x", count: 1001))]\"\n"),
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
        ("[^a\nx]\n\n[^a x]: note text", """
            document
              paragraph
                text "[^a"
                softbreak
                text "x]"
              paragraph
                text "[^a x]: note text"

            """),
        ("![\\^\u{07F9}\n\u{FFFD}]", """
            document
              paragraph
                text "![^\u{07F9}"
                softbreak
                text "\u{FFFD}]"

            """),
        ("[\\^\u{1F600}\n\u{FFFD}]", """
            document
              paragraph
                text "[^\u{1F600}"
                softbreak
                text "\u{FFFD}]"

            """),
    ]

    @Test(arguments: cases)
    func bracketStaysLiteral(_ markdown: String, _ expected: String) {
        #expect(TreeDump.dump(markdown, options: [.sourcePosition, .footnotes]) == expected)
    }
}
