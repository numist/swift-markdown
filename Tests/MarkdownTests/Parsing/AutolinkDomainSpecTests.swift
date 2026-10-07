/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(Autolinking) import Markdown
import Testing

/// An extended www or url autolink needs a valid domain: segments of alphanumeric characters,
/// underscores and hyphens separated by periods, with at least one period and no underscore in the
/// last two segments. An extended email autolink's domain is one or more such segments separated by
/// periods, with at least one period, ending in neither `-` nor `_` (spec "Autolinks (extension)").
struct AutolinkDomainSpecTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: .gfmAutolink).debugDescription(options: .printSourceLocations)
    }

    private func text(_ literal: String) -> String {
        let end = literal.utf8.count + 1
        return """
            Document @1:1-1:\(end)
            └─ Paragraph @1:1-1:\(end)
               └─ Text @1:1-1:\(end) "\(literal)"
            """
    }

    @Test func urlHostWithoutPeriodIsText() {
        #expect(tree("http://e") == text("http://e"))
    }

    @Test func urlHostWithoutPeriodBeforeAngleBracketIsText() {
        #expect(tree("http://l>") == text("http://l>"))
    }

    @Test func urlHostWithEmptySegmentIsText() {
        #expect(tree("http://a..b") == text("http://a..b"))
    }

    @Test func urlHostWithPeriodIsLink() {
        #expect(tree("http://e.f") == """
            Document @1:1-1:11
            └─ Paragraph @1:1-1:11
               └─ Link @1:1-1:11 destination: "http://e.f"
                  └─ Text @1:1-1:11 "http://e.f"
            """)
    }

    @Test func wwwDomainWithoutPeriodIsText() {
        #expect(tree("www.foo") == text("www.foo"))
    }

    @Test func wwwDomainWithPeriodIsLink() {
        #expect(tree("www.foo.bar") == """
            Document @1:1-1:12
            └─ Paragraph @1:1-1:12
               └─ Link @1:1-1:12 destination: "http://www.foo.bar"
                  └─ Text @1:1-1:12 "www.foo.bar"
            """)
    }

    /// A letter outside ASCII is alphanumeric; a symbol, punctuation or combining mark is not.
    @Test func nonASCIILetterIsDomainCharacter() {
        #expect(tree("http://\u{4E2D}a.b") == """
            Document @1:1-1:14
            └─ Paragraph @1:1-1:14
               └─ Link @1:1-1:14 destination: "http://\u{4E2D}a.b"
                  └─ Text @1:1-1:14 "http://\u{4E2D}a.b"
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

    @Test func emailAfterRejectedCandidateIsText() {
        #expect(tree("l@o+@.b") == text("l@o+@.b"))
    }

    @Test func emailRestartedAtSecondAtSignNeedsItsOwnPeriod() {
        #expect(tree("o@.e@b") == text("o@.e@b"))
    }

    @Test func emailDomainEndingInDigitIsLink() {
        #expect(tree("a@b.c9") == """
            Document @1:1-1:7
            └─ Paragraph @1:1-1:7
               └─ Link @1:1-1:7 destination: "mailto:a@b.c9"
                  └─ Text @1:1-1:7 "a@b.c9"
            """)
    }

    @Test func emailDomainEndingInHyphenIsText() {
        #expect(tree("a@b.c-") == text("a@b.c-"))
    }
}

/// Links may not contain other links, at any level of nesting, and an autolink binds more tightly than
/// the brackets of link text (spec "Links"), so link text holding an autolink is literal text.
struct AutolinkInLinkTextTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: .gfmAutolink).debugDescription(options: .printSourceLocations)
    }

    @Test func emailAutolinkInLinkText() {
        #expect(tree("[<M@C>B@.B]()") == """
            Document @1:1-1:14
            └─ Paragraph @1:1-1:14
               ├─ Text @1:1-1:2 "["
               ├─ Link @1:2-1:7 destination: "mailto:M@C"
               │  └─ Text @1:3-1:6 "M@C"
               └─ Text @1:7-1:14 "B@.B]()"
            """)
    }

    @Test func uriAutolinkInLinkText() {
        #expect(tree("[<http://a.b>](/u)") == """
            Document @1:1-1:19
            └─ Paragraph @1:1-1:19
               ├─ Text @1:1-1:2 "["
               ├─ Link @1:2-1:14 destination: "http://a.b"
               │  └─ Text @1:3-1:13 "http://a.b"
               └─ Text @1:14-1:19 "](/u)"
            """)
    }

    /// Image descriptions may contain links (spec "Images").
    @Test func autolinkInImageDescription() {
        #expect(tree("![<http://a.b>](/u)") == """
            Document @1:1-1:20
            └─ Paragraph @1:1-1:20
               └─ Image @1:1-1:20 source: "/u"
                  └─ Link @1:3-1:15 destination: "http://a.b"
                     └─ Text @1:4-1:14 "http://a.b"
            """)
    }

    @Test func linkAfterAutolinkOutsideLinkText() {
        #expect(tree("<http://a.b> [x](/u)") == """
            Document @1:1-1:21
            └─ Paragraph @1:1-1:21
               ├─ Link @1:1-1:13 destination: "http://a.b"
               │  └─ Text @1:2-1:12 "http://a.b"
               ├─ Text @1:13-1:14 " "
               └─ Link @1:14-1:21 destination: "/u"
                  └─ Text @1:15-1:16 "x"
            """)
    }
}
