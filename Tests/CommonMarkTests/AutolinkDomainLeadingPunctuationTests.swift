/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An extended url autolink's domain begins with a character that is neither Unicode whitespace nor Unicode
/// punctuation, so a domain that begins with a non-ASCII punctuation or whitespace character is not an extended url
/// autolink.
@Suite("Extended url autolink domain beginning with punctuation")
struct AutolinkDomainLeadingPunctuationTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .gfmAutolink]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    @Test func guillemetDomainIsText() {
        #expect(tree("https://\u{AB}") == text("https://\u{AB}"))
    }

    @Test func guillemetDomainBeforeParenthesisIsText() {
        #expect(tree("ftp://\u{AB})") == text("ftp://\u{AB})"))
    }

    @Test func guillemetDomainBeforePeriodIsText() {
        #expect(tree("x http://\u{AB}.") == text("x http://\u{AB}."))
    }

    @Test func uppercaseSchemeGuillemetDomainIsText() {
        #expect(tree("HTTP://\u{AB}*") == text("HTTP://\u{AB}*"))
    }

    @Test func guillemetBeforeDottedDomainIsText() {
        #expect(tree("http://\u{AB}a.b") == text("http://\u{AB}a.b"))
    }

    @Test func invertedExclamationDomainIsText() {
        #expect(tree("http://\u{A1}x") == text("http://\u{A1}x"))
    }

    @Test func emDashDomainIsText() {
        #expect(tree("http://\u{2014}x") == text("http://\u{2014}x"))
    }

    @Test func leftQuotationMarkDomainIsText() {
        #expect(tree("http://\u{201C}x") == text("http://\u{201C}x"))
    }

    // MARK: - Unicode general categories

    @Test(arguments: [
        ("Pd hyphen", "\u{2010}"), ("Pd em dash", "\u{2014}"),
        ("Ps fullwidth paren", "\u{FF08}"), ("Pe fullwidth paren", "\u{FF09}"), ("Ps corner bracket", "\u{300C}"),
        ("Pi left quote", "\u{201C}"), ("Pf right quote", "\u{201D}"), ("Pi single guillemet", "\u{2039}"), ("Pf guillemet", "\u{00BB}"),
        ("Po inverted exclamation", "\u{00A1}"), ("Po inverted question", "\u{00BF}"), ("Po ideographic full stop", "\u{3002}"),
        ("Po double exclamation", "\u{203C}"),
        ("Pc undertie", "\u{203F}"), ("Po Aegean word separator (4-byte)", "\u{10100}"),
        ("Zs no-break space", "\u{00A0}"), ("Zs ideographic space", "\u{3000}"),
    ] as [(String, String)])
    func domainStartPunctuationOrWhitespaceIsNotALink(category: String, scalar: String) {
        #expect(tree("http://\(scalar)a.b") == text("http://\(scalar)a.b"), "\(category)")
    }

    @Test func letterInDomainIsALink() {
        #expect(tree("http://\u{4E2D}a.b") == """
            document
              paragraph
                link "http://\u{4E2D}a.b" ""
                  text "http://\u{4E2D}a.b"

            """)
        #expect(tree("http://a.\u{4E2D}b") == """
            document
              paragraph
                link "http://a.\u{4E2D}b" ""
                  text "http://a.\u{4E2D}b"

            """)
        #expect(tree("http://a\u{4E2D}.b") == """
            document
              paragraph
                link "http://a\u{4E2D}.b" ""
                  text "http://a\u{4E2D}.b"

            """)
        #expect(tree("www.a\u{4E2D}.b") == """
            document
              paragraph
                link "http://www.a\u{4E2D}.b" ""
                  text "www.a\u{4E2D}.b"

            """)
    }
}
