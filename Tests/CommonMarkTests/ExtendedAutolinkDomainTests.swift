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

/// An extended www or url autolink needs a valid domain: segments of alphanumeric characters,
/// underscores and hyphens separated by periods, with at least one period and no underscore in the
/// last two segments. An extended email autolink's domain is one or more such segments separated by
/// periods, with at least one period, ending in neither `-` nor `_` (spec "Autolinks (extension)").
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

    @Test func urlHostWithoutPeriodIsText() {
        #expect(tree("http://e") == text("http://e"))
    }

    @Test func urlHostWithEmptySegmentIsText() {
        #expect(tree("http://a..b") == text("http://a..b"))
    }

    @Test func urlHostWithPeriodIsLink() {
        #expect(tree("http://e.f") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                link "http://e.f" "" @1:1-1:11
                  text "http://e.f" @1:1-1:11

            """)
    }

    @Test func wwwDomainWithoutPeriodIsText() {
        #expect(tree("www.foo") == text("www.foo"))
    }

    @Test func wwwDomainWithPeriodIsLink() {
        #expect(tree("www.foo.bar") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                link "http://www.foo.bar" "" @1:1-1:12
                  text "www.foo.bar" @1:1-1:12

            """)
    }

    /// A letter outside ASCII is alphanumeric; a symbol, punctuation or combining mark is not.
    @Test func nonASCIILetterIsDomainCharacter() {
        #expect(tree("http://\u{4E2D}a.b") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                link "http://\u{4E2D}a.b" "" @1:1-1:14
                  text "http://\u{4E2D}a.b" @1:1-1:14

            """)
    }

    @Test(arguments: ["\u{00D7}", "\u{00AB}", "\u{0301}", "\u{1F600}"])
    func nonAlphanumericSegmentIsText(_ scalar: String) {
        #expect(tree("www.\(scalar)") == text("www.\(scalar)"))
        #expect(tree("http://a.\(scalar)") == text("http://a.\(scalar)"))
        #expect(tree("http://\(scalar)") == text("http://\(scalar)"))
    }

    @Test func periodlessNonASCIIHostIsText() {
        #expect(tree("www.\u{00E9}") == text("www.\u{00E9}"))
        #expect(tree("http://\u{00E9}") == text("http://\u{00E9}"))
    }

    @Test func emailDomainStartingWithPeriodIsText() {
        #expect(tree("o@.x") == text("o@.x"))
    }

    @Test func emailRestartedAtSecondAtSignNeedsItsOwnPeriod() {
        #expect(tree("o@.e@b") == text("o@.e@b"))
    }

    @Test func emailDomainEndingInDigitIsLink() {
        #expect(tree("a@b.c9") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "mailto:a@b.c9" "" @1:1-1:7
                  text "a@b.c9" @1:1-1:7

            """)
    }

    @Test func emailDomainEndingInHyphenIsText() {
        #expect(tree("a@b.c-") == text("a@b.c-"))
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
