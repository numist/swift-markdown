/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

private let autolinkOptions: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink]

/// An extended www autolink's domain runs from `www.` to the first non-ASCII character, Unicode whitespace character,
/// or ASCII punctuation character other than `.`, `-` and `_`, and holds a period.
/// An extended url autolink's domain begins with a character that is neither a punctuation character nor a Unicode
/// whitespace character; a non-ASCII first character ends it, and an ASCII one continues it as a www domain does.
/// An underscore in either of the last two period-separated segments rejects a www or url domain unless the domain
/// holds more than ten periods; the domain scan never examines the inline content's last character, and a backslash
/// makes it examine the character after it in its place.
/// An extended email autolink's domain is a run of ASCII alphanumerics, `-`, `_`, periods each followed by an
/// alphanumeric, and, after `xmpp:`, `/`; it ends in a letter, and it holds a period unless a second `@` restarted the
/// address after a domain that held one.
@Suite("Extended autolink domains")
struct ExtendedAutolinkDomainTests {
    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: autolinkOptions, sourceRanges: true)
    }

    // MARK: - Extended url autolink domains

    @Test func urlDomainWithoutPeriodIsLink() {
        #expect(tree("http://e") == """
            document @1:1-1:9
              paragraph @1:1-1:9
                link "http://e" "" @1:1-1:9
                  text "http://e" @1:1-1:9

            """)
        #expect(tree("http://localhost") == """
            document @1:1-1:17
              paragraph @1:1-1:17
                link "http://localhost" "" @1:1-1:17
                  text "http://localhost" @1:1-1:17

            """)
    }

    @Test func urlDomainWithEmptySegmentIsLink() {
        #expect(tree("http://a..b") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://a..b" "" @1:1-1:12
                  text "http://a..b" @1:1-1:12

            """)
    }

    @Test func urlDomainWithPeriodIsLink() {
        #expect(tree("http://e.f") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                link "http://e.f" "" @1:1-1:11
                  text "http://e.f" @1:1-1:11

            """)
    }

    @Test("scheme with nothing after `://` is text")
    func urlEmptyDomainIsText() {
        #expect(tree("http://") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "http://" @1:1-1:8

            """)
    }

    @Test("url autolink whose domain starts with a hyphen is text")
    func urlDomainStartingWithHyphenIsText() {
        #expect(tree("http://-x") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "http://-x" @1:1-1:10

            """)
    }

    @Test("url autolink ending in an underscore links without it")
    func urlTrailingUnderscoreTrims() {
        #expect(tree("http://a_") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "http://a" "" @1:1-1:9
                  text "http://a" @1:1-1:9
                text "_" @1:9-1:10

            """)
    }

    @Test func urlDomainStartingWithNonASCIILetterIsLink() {
        #expect(tree("http://\u{4E2D}a.b") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://中a.b" "" @1:1-1:14
                  text "http://中a.b" @1:1-1:14

            """)
    }

    @Test(arguments: [
        ("http://\u{00D7}", """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "http://×" "" @1:1-1:10
                  text "http://×" @1:1-1:10

            """),
        ("http://\u{0301}", """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "http://́" "" @1:1-1:10
                  text "http://́" @1:1-1:10

            """),
        ("http://\u{1F600}", """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://😀" "" @1:1-1:12
                  text "http://😀" @1:1-1:12

            """),
        ("http://\u{00E9}", """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "http://é" "" @1:1-1:10
                  text "http://é" @1:1-1:10

            """),
    ])
    func urlDomainStartingWithNonASCIICharacterIsLink(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test func urlDomainStartingWithPunctuationIsText() {
        #expect(tree("http://\u{00AB}") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "http://«" @1:1-1:10

            """)
    }

    @Test("url autolink with a U+FFFD before an underscore links")
    func urlReplacementCharacterInDomainAutolinks() {
        // U+FFFD is not a domain character, so the domain ends before it and the underscore is outside its last two
        // segments.
        #expect(tree("http://a\u{FFFD}_b") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://a\u{FFFD}_b" "" @1:1-1:14
                  text "http://a\u{FFFD}_b" @1:1-1:14

            """)
    }

    // MARK: - Extended www autolink domains

    @Test func wwwDomainWithoutSecondPeriodIsLink() {
        #expect(tree("www.foo") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "http://www.foo" "" @1:1-1:8
                  text "www.foo" @1:1-1:8

            """)
    }

    @Test func wwwDomainWithPeriodIsLink() {
        #expect(tree("www.foo.bar") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://www.foo.bar" "" @1:1-1:12
                  text "www.foo.bar" @1:1-1:12

            """)
    }

    /// The domain scan stops at the first character outside a domain, so a www domain keeps the period before it.
    @Test(arguments: [
        ("www.\u{00D7}", """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "http://www.×" "" @1:1-1:7
                  text "www.×" @1:1-1:7

            """),
        ("http://a.\u{00D7}", """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://a.×" "" @1:1-1:12
                  text "http://a.×" @1:1-1:12

            """),
        ("www.\u{00AB}", """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "http://www.«" "" @1:1-1:7
                  text "www.«" @1:1-1:7

            """),
        ("http://a.\u{00AB}", """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://a.«" "" @1:1-1:12
                  text "http://a.«" @1:1-1:12

            """),
        ("www.\u{0301}", """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "http://www.́" "" @1:1-1:7
                  text "www.́" @1:1-1:7

            """),
        ("http://a.\u{0301}", """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://a.́" "" @1:1-1:12
                  text "http://a.́" @1:1-1:12

            """),
        ("www.\u{1F600}", """
            document @1:1-1:9
              paragraph @1:1-1:9
                link "http://www.😀" "" @1:1-1:9
                  text "www.😀" @1:1-1:9

            """),
        ("http://a.\u{1F600}", """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://a.😀" "" @1:1-1:14
                  text "http://a.😀" @1:1-1:14

            """),
        ("www.\u{00E9}", """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "http://www.é" "" @1:1-1:7
                  text "www.é" @1:1-1:7

            """),
        ("http://a.\u{00E9}", """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://a.é" "" @1:1-1:12
                  text "http://a.é" @1:1-1:12

            """),
    ])
    func domainEndingAtNonASCIICharacterIsLink(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test("www autolink with a non-ASCII letter after `www.`")
    func wwwNonASCIILetterDomainAutolinks() {
        #expect(tree("www.\u{E9}x y") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "http://www.éx" "" @1:1-1:8
                  text "www.éx" @1:1-1:8
                text " y" @1:8-1:10

            """)
        #expect(tree("www.\u{E9}x.y z") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://www.éx.y" "" @1:1-1:10
                  text "www.éx.y" @1:1-1:10
                text " z" @1:10-1:12

            """)
    }

    @Test("www autolink with a U+FFFD after `www.`")
    func wwwReplacementCharacterDomainAutolinks() {
        // U+FFFD is not a domain character, so the domain ends before it and the underscores are outside its last two
        // segments. As trailing punctuation, they are not part of the autolink.
        #expect(tree("www.\u{FFFD}__") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "http://www.\u{FFFD}" "" @1:1-1:8
                  text "www.\u{FFFD}" @1:1-1:8
                text "__" @1:8-1:10

            """)
    }

    // MARK: - Underscores in domains

    @Test("url autolink with underscores in its last two domain segments is text")
    func urlUnderscoreInLastTwoSegmentsIsText() {
        #expect(tree("http://a_b.c_d") == """
            document @1:1-1:15
              paragraph @1:1-1:15
                text "http://a_b.c_d" @1:1-1:15

            """)
    }

    @Test("www domain with an underscore in its last segment is text")
    func wwwUnderscoreInLastSegmentIsText() {
        #expect(tree("www.a_b x") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "www.a_b x" @1:1-1:10

            """)
    }

    @Test("www domain with an underscore outside its last two segments autolinks")
    func wwwUnderscoreOutsideLastTwoSegmentsAutolinks() {
        #expect(tree("www.a_b.c.d x") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://www.a_b.c.d" "" @1:1-1:12
                  text "www.a_b.c.d" @1:1-1:12
                text " x" @1:12-1:14

            """)
    }

    @Test("email with an underscore in its first domain segment autolinks")
    func emailUnderscoreInFirstDomainSegmentAutolinks() {
        #expect(tree("o@b_c.d") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "mailto:o@b_c.d" "" @1:1-1:8
                  text "o@b_c.d" @1:1-1:8

            """)
    }

    @Test("email whose last domain segment contains an underscore autolinks")
    func emailUnderscoreInLastDomainSegmentAutolinks() {
        #expect(tree("a@b.c_d") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "mailto:a@b.c_d" "" @1:1-1:8
                  text "a@b.c_d" @1:1-1:8

            """)
    }

    @Test("email with an empty first domain segment autolinks")
    func emailEmptyFirstDomainSegmentAutolinks() {
        #expect(tree("a@.b_o") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "mailto:a@.b_o" "" @1:1-1:7
                  text "a@.b_o" @1:1-1:7

            """)
    }

    @Test("email with a hyphen local part and an empty first domain segment autolinks")
    func emailHyphenLocalPartEmptyFirstDomainSegmentAutolinks() {
        #expect(tree("-@.b_o") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "mailto:-@.b_o" "" @1:1-1:7
                  text "-@.b_o" @1:1-1:7

            """)
    }

    // MARK: - Extended email autolink domains

    @Test("email with a non-empty last segment autolinks")
    func emailNonEmptyLastSegmentAutolinks() {
        #expect(tree("o@b.c") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                link "mailto:o@b.c" "" @1:1-1:6
                  text "o@b.c" @1:1-1:6

            """)
    }

    @Test("email with three domain segments autolinks")
    func emailMultiDotDomainAutolinks() {
        #expect(tree("a@b.c.d") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "mailto:a@b.c.d" "" @1:1-1:8
                  text "a@b.c.d" @1:1-1:8

            """)
    }

    @Test("email with a digit inside its domain autolinks")
    func emailInteriorDigitLetterLastAutolinks() {
        #expect(tree("o@b2.co") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "mailto:o@b2.co" "" @1:1-1:8
                  text "o@b2.co" @1:1-1:8

            """)
    }

    @Test("email with a hyphen local part and a plain domain autolinks")
    func emailHyphenLocalPlainDomainAutolinks() {
        #expect(tree("-@b.c") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                link "mailto:-@b.c" "" @1:1-1:6
                  text "-@b.c" @1:1-1:6

            """)
    }

    @Test func emailDomainStartingWithPeriodIsLink() {
        #expect(tree("o@.x") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                link "mailto:o@.x" "" @1:1-1:5
                  text "o@.x" @1:1-1:5

            """)
    }

    /// A second `@` in the domain restarts the address just past the first `@`; the periods the first domain held still
    /// count.
    @Test func emailRestartedAtSecondAtSignKeepsFirstDomainPeriod() {
        #expect(tree("o@.e@b") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "o@" @1:1-1:3
                link "mailto:.e@b" "" @1:3-1:7
                  text ".e@b" @1:3-1:7

            """)
    }

    @Test("email whose domain ends in a period is text")
    func emailDomainEndingInPeriodIsText() {
        // A final period is not part of the address, which leaves the domain `b` with no period.
        #expect(tree("o@b.") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "o@b." @1:1-1:5

            """)
    }

    @Test func emailDomainEndingInDigitIsText() {
        #expect(tree("a@b.c9") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "a@b.c9" @1:1-1:7

            """)
        #expect(tree("a@1.2") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "a@1.2" @1:1-1:6

            """)
    }

    @Test("email whose domain has an empty first segment and ends in a digit is text")
    func emailEmptyFirstSegmentDigitDomainIsText() {
        #expect(tree("f@.0") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "f@.0" @1:1-1:5

            """)
    }

    @Test("email whose domain has an empty first segment and a final period is text")
    func emailDomainEndingInDigitAndFinalPeriodIsText() {
        // A final period is not part of the address, which leaves the domain `.0` ending in a digit.
        #expect(tree("a@.0.") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "a@.0." @1:1-1:6

            """)
    }

    @Test("email whose domain ends in a digit before a final period is text")
    func emailDomainEndingInDigitBeforeFinalPeriodIsText() {
        #expect(tree("a@b.c9.") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "a@b.c9." @1:1-1:8

            """)
    }

    @Test func emailDomainEndingInHyphenIsText() {
        #expect(tree("a@b.c-") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "a@b.c-" @1:1-1:7

            """)
    }

    @Test("email domain ends before a period that no alphanumeric follows")
    func emailDomainEndsBeforeHyphenSegment() {
        #expect(tree("a@x.y.-5") == """
            document @1:1-1:9
              paragraph @1:1-1:9
                link "mailto:a@x.y" "" @1:1-1:6
                  text "a@x.y" @1:1-1:6
                text ".-5" @1:6-1:9

            """)
    }
}

/// The domain scan of an extended www or url autolink runs to the first character outside a domain and never examines
/// the inline content's final character, whatever the trailing punctuation trim later leaves of the link. A backslash
/// makes the scan examine the character after it in its place. An underscore in the last two segments rejects the
/// domain only while the scan has passed ten periods or fewer.
@Suite("Extended www and url autolink domain scan")
struct ExtendedAutolinkDomainScanTests {
    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: autolinkOptions)
    }

    @Test func wwwTrailingPeriodIsTrimmed() {
        #expect(tree("www.a.") == """
            document
              paragraph
                link "http://www.a" ""
                  text "www.a"
                text "."

            """)
    }

    @Test func wwwDomainTrimmedBeforeItsPeriodIsLink() {
        #expect(tree("www..") == """
            document
              paragraph
                link "http://www" ""
                  text "www"
                text ".."

            """)
    }

    @Test func underscoreEndingInlineContentIsTrimmed() {
        #expect(tree("www.a_") == """
            document
              paragraph
                link "http://www.a" ""
                  text "www.a"
                text "_"

            """)
        #expect(tree("_www.a.b_") == """
            document
              paragraph
                emph
                  link "http://www.a.b" ""
                    text "www.a.b"

            """)
    }

    @Test func trailingUnderscoreBeforeMoreContentRejectsDomain() {
        #expect(tree("www.a.b_ c") == """
            document
              paragraph
                text "www.a.b_ c"

            """)
        #expect(tree("http://a.b_ x") == """
            document
              paragraph
                text "http://a.b_ x"

            """)
        #expect(tree("x www.a.b__ y") == """
            document
              paragraph
                text "x www.a.b__ y"

            """)
        #expect(tree("__www.a.b__") == """
            document
              paragraph
                strong
                  text "www.a.b"

            """)
    }

    @Test func escapedUnderscoreRejectsDomain() {
        #expect(tree("www.a.b\\_c d") == """
            document
              paragraph
                text "www.a.b_c d"

            """)
        #expect(tree("http://a\\_b.c x") == """
            document
              paragraph
                text "http://a_b.c x"

            """)
    }

    @Test func backslashInDomainIsLink() {
        #expect(tree("www.a\\b.c") == """
            document
              paragraph
                link "http://www.a\\\\b.c" ""
                  text "www.a\\\\b.c"

            """)
    }

    @Test func underscoreInLastTwoSegmentsRejectsDomain() {
        #expect(tree("www.a_b.c") == """
            document
              paragraph
                text "www.a_b.c"

            """)
        #expect(tree("www.a.b_c") == """
            document
              paragraph
                text "www.a.b_c"

            """)
        #expect(tree("www.a.b.c.d.e.f.g.h.i.l_m") == """
            document
              paragraph
                text "www.a.b.c.d.e.f.g.h.i.l_m"

            """)
    }

    /// The final candidate's underscore is the inline content's last character, which the domain scan does not examine.
    @Test("a url candidate after a rejected one in the same word links",
          arguments: [.gfmAutolink, [.gfmAutolink, .inlineOnly]] as [MarkdownDocument.ParseOptions])
    func candidateAfterRejectedCandidateIsLink(_ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("http://a_http://a_", options: options) == """
            document
              paragraph
                text "http://a_"
                link "http://a" ""
                  text "http://a"
                text "_"

            """)
    }

    @Test func underscoreAfterMoreThanTenPeriodsIsLink() {
        #expect(tree("www.a.b.c.d.e.f.g.h.i.j.l_m") == """
            document
              paragraph
                link "http://www.a.b.c.d.e.f.g.h.i.j.l_m" ""
                  text "www.a.b.c.d.e.f.g.h.i.j.l_m"

            """)
    }

    @Test(arguments: [
        ("http://a:80/x", """
            document
              paragraph
                link "http://a:80/x" ""
                  text "http://a:80/x"

            """),
        ("http://user@a.b", """
            document
              paragraph
                link "http://user@a.b" ""
                  text "http://user@a.b"

            """),
        ("http://a/b", """
            document
              paragraph
                link "http://a/b" ""
                  text "http://a/b"

            """),
        ("http://a?b", """
            document
              paragraph
                link "http://a?b" ""
                  text "http://a?b"

            """),
        ("http://a#b", """
            document
              paragraph
                link "http://a#b" ""
                  text "http://a#b"

            """),
    ])
    func urlWithPortUserPathQueryOrFragmentIsLink(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    /// Line tabulation is not whitespace that ends an extended autolink.
    @Test func urlDomainStartingWithLineTabulationIsLink() {
        #expect(tree("http://\u{0B}x") == """
            document
              paragraph
                link "http://\\u{B}x" ""
                  text "http://\\u{B}x"

            """)
    }
}

/// Links may not contain other links, at any level of nesting, and an autolink binds more tightly than the brackets of
/// link text (Links), so the brackets of a link around an autolink are literal text.
@Suite("Autolinks in link text")
struct AutolinkInLinkTextTests {
    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: autolinkOptions, sourceRanges: true)
    }

    @Test func uriAutolinkInLinkText() {
        #expect(tree("[<http://a.b>](/u)") == """
            document @1:1-1:19
              paragraph @1:1-1:19
                text "[" @1:1-1:2
                link "http://a.b" "" @1:2-1:14
                  text "http://a.b" @1:3-1:13
                text "](/u)" @1:14-1:19

            """)
    }

    /// Image descriptions may contain links (Images).
    @Test func autolinkInImageDescription() {
        #expect(tree("![<http://a.b>](/u)") == """
            document @1:1-1:20
              paragraph @1:1-1:20
                image "/u" "" @1:1-1:20
                  link "http://a.b" "" @1:3-1:15
                    text "http://a.b" @1:4-1:14

            """)
    }

    @Test func linkAfterAutolinkOutsideLinkText() {
        #expect(tree("<http://a.b> [x](/u)") == """
            document @1:1-1:21
              paragraph @1:1-1:21
                link "http://a.b" "" @1:1-1:13
                  text "http://a.b" @1:2-1:12
                text " " @1:13-1:14
                link "/u" "" @1:14-1:21
                  text "x" @1:15-1:16

            """)
    }

    @Test func autolinkInLinkTextBeforeAnotherBracket() {
        #expect(tree("[a <http://b.c> [d] e](f)") == """
            document @1:1-1:26
              paragraph @1:1-1:26
                text "[a " @1:1-1:4
                link "http://b.c" "" @1:4-1:16
                  text "http://b.c" @1:5-1:15
                text " [d] e](f)" @1:16-1:26

            """)
    }

    @Test func linkInLinkTextBeforeAnotherBracket() {
        #expect(tree("[a [b](c) [d] e](f)") == """
            document @1:1-1:20
              paragraph @1:1-1:20
                text "[a " @1:1-1:4
                link "c" "" @1:4-1:10
                  text "b" @1:5-1:6
                text " [d] e](f)" @1:10-1:20

            """)
    }
}
