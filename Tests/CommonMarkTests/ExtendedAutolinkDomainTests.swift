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

/// An extended www autolink's domain runs from `www.` to the first whitespace or punctuation character other than `.`,
/// `-` and `_`, and holds a period. An extended url autolink's domain begins with a character that is neither
/// whitespace nor punctuation. Neither domain may have an underscore in its last two period-separated segments. An
/// extended email autolink's domain is a run of ASCII alphanumerics, `-`, `_`, and periods each followed by an
/// alphanumeric; it holds a period and ends in a letter.
@Suite("Extended autolink domains")
struct ExtendedAutolinkDomainTests {
    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: autolinkOptions, sourceRanges: true)
    }

    private func text(_ literal: String) -> String {
        let end = literal.utf8.count + 1
        return """
            document @1:1-1:\(end)
              paragraph @1:1-1:\(end)
                text "\(literal)" @1:1-1:\(end)

            """
    }

    private func link(_ url: String, _ literal: String) -> String {
        let end = literal.utf8.count + 1
        return """
            document @1:1-1:\(end)
              paragraph @1:1-1:\(end)
                link "\(url)" "" @1:1-1:\(end)
                  text "\(literal)" @1:1-1:\(end)

            """
    }

    @Test func urlHostWithoutPeriodIsLink() {
        #expect(tree("http://e") == link("http://e", "http://e"))
        #expect(tree("http://localhost") == link("http://localhost", "http://localhost"))
    }

    @Test func urlHostWithEmptySegmentIsLink() {
        #expect(tree("http://a..b") == link("http://a..b", "http://a..b"))
    }

    @Test func urlHostWithPeriodIsLink() {
        #expect(tree("http://e.f") == link("http://e.f", "http://e.f"))
    }

    @Test func wwwDomainWithoutSecondPeriodIsLink() {
        #expect(tree("www.foo") == link("http://www.foo", "www.foo"))
    }

    @Test func wwwDomainWithPeriodIsLink() {
        #expect(tree("www.foo.bar") == link("http://www.foo.bar", "www.foo.bar"))
    }

    @Test func nonASCIILetterIsDomainCharacter() {
        #expect(tree("http://\u{4E2D}a.b") == link("http://\u{4E2D}a.b", "http://\u{4E2D}a.b"))
    }

    /// The www domain scan stops at the first character outside a domain, which leaves the period it already holds.
    @Test(arguments: ["\u{00D7}", "\u{00AB}", "\u{0301}", "\u{1F600}", "\u{00E9}"])
    func wwwDomainEndingInNonASCIICharacterIsLink(_ scalar: String) {
        #expect(tree("www.\(scalar)") == link("http://www.\(scalar)", "www.\(scalar)"))
        #expect(tree("http://a.\(scalar)") == link("http://a.\(scalar)", "http://a.\(scalar)"))
    }

    @Test(arguments: ["\u{00D7}", "\u{0301}", "\u{1F600}", "\u{00E9}"])
    func urlHostStartingWithNonASCIICharacterIsLink(_ scalar: String) {
        #expect(tree("http://\(scalar)") == link("http://\(scalar)", "http://\(scalar)"))
    }

    @Test func urlHostStartingWithPunctuationIsText() {
        #expect(tree("http://\u{00AB}") == text("http://\u{00AB}"))
    }

    @Test func emailDomainStartingWithPeriodIsLink() {
        #expect(tree("o@.x") == link("mailto:o@.x", "o@.x"))
    }

    /// A second `@` in the domain restarts the address there; the periods the first domain held still count.
    @Test func emailRestartedAtSecondAtSignKeepsFirstDomainPeriod() {
        #expect(tree("o@.e@b") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "o@" @1:1-1:3
                link "mailto:.e@b" "" @1:3-1:7
                  text ".e@b" @1:3-1:7

            """)
    }

    @Test func emailDomainEndingInDigitIsText() {
        #expect(tree("a@b.c9") == text("a@b.c9"))
        #expect(tree("a@1.2") == text("a@1.2"))
    }

    @Test func emailDomainEndingInHyphenIsText() {
        #expect(tree("a@b.c-") == text("a@b.c-"))
    }
}

/// The domain scan of an extended www or url autolink runs over the rest of the inline content, short of its final
/// character, without regard to where the trailing punctuation trim later ends the link. A backslash makes the scan
/// examine the character after it in its place. An underscore in the last two segments rejects the domain only while
/// the scan has passed ten periods or fewer.
@Suite("Extended www and url autolink domain scan")
struct ExtendedAutolinkDomainScanTests {
    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: autolinkOptions)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    @Test func wwwDomainTrimmedToPeriodIsLink() {
        #expect(surface("www.a.") == """
            document
              paragraph
                link "http://www.a" ""
                  text "www.a"
                text "."

            """)
    }

    @Test func wwwDomainTrimmedBeforeItsPeriodIsLink() {
        #expect(surface("www..") == """
            document
              paragraph
                link "http://www" ""
                  text "www"
                text ".."

            """)
    }

    @Test func underscoreEndingInlineContentIsTrimmed() {
        #expect(surface("www.a_") == """
            document
              paragraph
                link "http://www.a" ""
                  text "www.a"
                text "_"

            """)
        #expect(surface("_www.a.b_") == """
            document
              paragraph
                emph
                  link "http://www.a.b" ""
                    text "www.a.b"

            """)
    }

    @Test func trailingUnderscoreBeforeMoreContentRejectsDomain() {
        #expect(surface("www.a.b_ c") == text("www.a.b_ c"))
        #expect(surface("http://a.b_ x") == text("http://a.b_ x"))
        #expect(surface("x www.a.b__ y") == text("x www.a.b__ y"))
        #expect(surface("__www.a.b__") == """
            document
              paragraph
                strong
                  text "www.a.b"

            """)
    }

    @Test func escapedUnderscoreRejectsDomain() {
        #expect(surface("www.a.b\\_c d") == text("www.a.b_c d"))
        #expect(surface("http://a\\_b.c x") == text("http://a_b.c x"))
    }

    @Test func backslashInDomainIsLink() {
        #expect(surface("www.a\\b.c") == """
            document
              paragraph
                link "http://www.a\\\\b.c" ""
                  text "www.a\\\\b.c"

            """)
    }

    @Test func underscoreInLastTwoSegmentsRejectsDomain() {
        #expect(surface("www.a_b.c") == text("www.a_b.c"))
        #expect(surface("www.a.b_c") == text("www.a.b_c"))
        #expect(surface("www.a.b.c.d.e.f.g.h.i.l_m") == text("www.a.b.c.d.e.f.g.h.i.l_m"))
    }

    @Test func underscoreAfterMoreThanTenPeriodsIsLink() {
        #expect(surface("www.a.b.c.d.e.f.g.h.i.j.l_m") == """
            document
              paragraph
                link "http://www.a.b.c.d.e.f.g.h.i.j.l_m" ""
                  text "www.a.b.c.d.e.f.g.h.i.j.l_m"

            """)
    }

    @Test func urlWithPortPathAndUserIsLink() {
        for url in ["http://a:80/x", "http://user@a.b", "http://a/b", "http://a?b", "http://a#b"] {
            #expect(surface(url) == """
                document
                  paragraph
                    link "\(url)" ""
                      text "\(url)"

                """)
        }
    }

    /// Line tabulation is not whitespace that ends an extended autolink.
    @Test func urlHostStartingWithLineTabulationIsLink() {
        #expect(surface("http://\u{0B}x") == """
            document
              paragraph
                link "http://\\u{B}x" ""
                  text "http://\\u{B}x"

            """)
    }
}

/// Links may not contain other links, at any level of nesting, and an autolink binds more tightly than
/// the brackets of link text (spec "Links"), so link text holding an autolink is literal text.
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

    /// Image descriptions may contain links (spec "Images").
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
