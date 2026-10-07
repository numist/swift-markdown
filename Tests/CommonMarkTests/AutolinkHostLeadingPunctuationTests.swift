/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A GFM extended autolink whose host begins with a multi-byte punctuation or whitespace character.
@Suite("Extended autolink host beginning with punctuation")
struct AutolinkHostLeadingPunctuationTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    @Test func testCase1() {
        #expect(surface("https://\u{AB}") == text("https://\u{AB}"))
    }

    @Test func testCase2() {
        #expect(surface("ftp://\u{AB})") == text("ftp://\u{AB})"))
    }

    @Test func testCase3() {
        #expect(surface("x http://\u{AB}.") == text("x http://\u{AB}."))
    }

    @Test func testCase4() {
        #expect(surface("HTTP://\u{AB}*") == text("HTTP://\u{AB}*"))
    }

    @Test func testCase6() {
        #expect(surface("http://\u{AB}a.b") == text("http://\u{AB}a.b"))
    }

    @Test func testCase9() {
        #expect(surface("http://\u{A1}x") == text("http://\u{A1}x"))
    }

    @Test func testCase10() {
        #expect(surface("http://\u{2014}x") == text("http://\u{2014}x"))
    }

    @Test func testCase11() {
        #expect(surface("http://\u{201C}x") == text("http://\u{201C}x"))
    }

    // MARK: - Category probes

    /// Punctuation (P[cdefios]) and Unicode whitespace (Zs) at the host start: never a link.
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

    /// The rejection is spec-correct (punctuation is not a valid domain character), so the shipped flag-OFF
    /// parser agrees.
    @Test(arguments: ["\u{2014}", "\u{00AB}", "\u{00A1}", "\u{00A0}"])
    func testHostStartPunctuationIsNotALinkWithoutBugCompatibility(scalar: String) {
        #expect(surface("http://\(scalar)a.b") == text("http://\(scalar)a.b"))
    }

    /// A letter is a valid domain character at a label's start or end, so a host holding one links; flag-off the
    /// scheme autolink is the paragraph's only child.
    @Test func testLetterInHostIsALinkWithoutBugCompatibility() {
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
