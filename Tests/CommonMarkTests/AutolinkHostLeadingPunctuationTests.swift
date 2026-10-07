/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A valid domain holds only alphanumerics, `_` and `-` (Autolinks (extension)), so a host that begins with a
/// non-ASCII punctuation or space character is not an extended autolink.
@Suite("Extended autolink host beginning with punctuation")
struct AutolinkHostLeadingPunctuationTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    @Test func testGuillemetHostIsText() {
        #expect(surface("https://\u{AB}") == text("https://\u{AB}"))
    }

    @Test func testGuillemetHostBeforeParenthesisIsText() {
        #expect(surface("ftp://\u{AB})") == text("ftp://\u{AB})"))
    }

    @Test func testGuillemetHostBeforePeriodIsText() {
        #expect(surface("x http://\u{AB}.") == text("x http://\u{AB}."))
    }

    @Test func testUppercaseSchemeGuillemetHostIsText() {
        #expect(surface("HTTP://\u{AB}*") == text("HTTP://\u{AB}*"))
    }

    @Test func testGuillemetBeforeDottedHostIsText() {
        #expect(surface("http://\u{AB}a.b") == text("http://\u{AB}a.b"))
    }

    @Test func testInvertedExclamationHostIsText() {
        #expect(surface("http://\u{A1}x") == text("http://\u{A1}x"))
    }

    @Test func testEmDashHostIsText() {
        #expect(surface("http://\u{2014}x") == text("http://\u{2014}x"))
    }

    @Test func testLeftQuotationMarkHostIsText() {
        #expect(surface("http://\u{201C}x") == text("http://\u{201C}x"))
    }

    // MARK: - Unicode general categories

    @Test(arguments: [
        ("Pd hyphen", "\u{2010}"), ("Pd em dash", "\u{2014}"),
        ("Ps fullwidth paren", "\u{FF08}"), ("Pe fullwidth paren", "\u{FF09}"), ("Ps corner bracket", "\u{300C}"),
        ("Pi left quote", "\u{201C}"), ("Pf right quote", "\u{201D}"), ("Pi single guillemet", "\u{2039}"), ("Pf guillemet", "\u{00BB}"),
        ("Po inverted question", "\u{00BF}"), ("Po ideographic full stop", "\u{3002}"), ("Po double exclamation", "\u{203C}"),
        ("Pc undertie", "\u{203F}"), ("Po Aegean word separator (4-byte)", "\u{10100}"),
        ("Zs no-break space", "\u{00A0}"), ("Zs ideographic space", "\u{3000}"),
    ] as [(String, String)])
    func testHostStartPunctuationOrSpaceIsNotALink(category: String, scalar: String) {
        #expect(surface("http://\(scalar)a.b") == text("http://\(scalar)a.b"), "\(category)")
    }

    @Test(arguments: ["\u{2014}", "\u{00AB}", "\u{00A1}", "\u{00A0}"])
    func testHostStartPunctuationIsNotALink(scalar: String) {
        #expect(surface("http://\(scalar)a.b") == text("http://\(scalar)a.b"))
    }

    /// A non-ASCII letter is alphanumeric, so it may start or end a domain segment.
    @Test func testLetterInHostIsALink() {
        #expect(surface("http://\u{4E2D}a.b") == """
            document
              paragraph
                link "http://\u{4E2D}a.b" ""
                  text "http://\u{4E2D}a.b"

            """)
        #expect(surface("http://a.\u{4E2D}b") == """
            document
              paragraph
                link "http://a.\u{4E2D}b" ""
                  text "http://a.\u{4E2D}b"

            """)
        #expect(surface("http://a\u{4E2D}.b") == """
            document
              paragraph
                link "http://a\u{4E2D}.b" ""
                  text "http://a\u{4E2D}.b"

            """)
        #expect(surface("www.a\u{4E2D}.b") == """
            document
              paragraph
                link "http://www.a\u{4E2D}.b" ""
                  text "www.a\u{4E2D}.b"

            """)
    }
}
