/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of GFM autolinks (`.gfmAutolink`): a bare URL, a `www.` domain, and an email address. The link and
/// its text span the matched bytes. With `.cmarkBugCompatibility` the empty text nodes cmark-gfm leaves beside an
/// autolink are kept, each with an empty range where it sits. Columns are 1-based UTF-8 byte offsets and each end is
/// half-open.
@Suite("Source ranges of GFM autolinks")
struct GFMAutolinkSourceRangeTests {

    private static let opts: MarkdownDocument.ParseOptions = [.sourcePosition, .gfmAutolink]

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = opts) throws -> String {
        try CmarkTreeDump.dump(source, options: options, sourceRanges: true)
    }

    /// cmark-gfm stretches the `(` to `@1:1-1:6` and starts the link at `@1:1`, because it rewinds over the scheme
    /// after emitting it as text.
    @Test("a URL autolink spans the URL")
    func url() throws {
        #expect(try tree("(http://e") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "(" @1:1-1:2
                link "http://e" "" @1:2-1:10
                  text "http://e" @1:2-1:10

            """)
    }

    /// cmark-gfm starts the link at `@1:1`, the paragraph's line start.
    @Test("a www autolink spans the domain")
    func www() throws {
        #expect(try tree(" www.w") == """
            document @1:1-1:7
              paragraph @1:2-1:7
                link "http://www.w" "" @1:2-1:7
                  text "www.w" @1:2-1:7

            """)
    }

    @Test("an email autolink spans the address")
    func email() throws {
        #expect(try tree("x a@b.co y") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "x " @1:1-1:3
                link "mailto:a@b.co" "" @1:3-1:9
                  text "a@b.co" @1:3-1:9
                text " y" @1:9-1:11

            """)
    }

    /// The empty text before the URL sits where the URL starts. cmark-gfm gives it the scheme's columns,
    /// `@1:1-1:5`, and leaves the link without a range.
    @Test("with cmark bug compatibility, the empty text before a URL autolink has an empty range")
    func emptyTextBeforeURL() throws {
        #expect(try tree("http://a", options: Self.opts.union(.cmarkBugCompatibility)) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "" @1:1-1:1
                link "http://a" "" @1:1-1:9
                  text "http://a" @1:1-1:9

            """)
    }

    /// The empty text before the address sits where the address starts, and the empty text after it where it
    /// ends. cmark-gfm gives the first `@1:1-1:7`, and leaves the link, its text and the empty text after it
    /// without a range.
    @Test("with cmark bug compatibility, the empty texts beside an email autolink have empty ranges")
    func emptyTextsBesideEmail() throws {
        #expect(try tree("a@b.co", options: Self.opts.union(.cmarkBugCompatibility)) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "" @1:1-1:1
                link "mailto:a@b.co" "" @1:1-1:7
                  text "a@b.co" @1:1-1:7
                text "" @1:7-1:7

            """)
    }

    /// A NUL makes the paragraph's text a copy with the NUL replaced by U+FFFD; the address is still placed on its
    /// source bytes, and the U+FFFD before it on the NUL.
    @Test("an email autolink after a NUL spans the address")
    func emailAfterNUL() throws {
        #expect(try tree("\u{0}a@b.co") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "\u{FFFD}" @1:1-1:2
                link "mailto:a@b.co" "" @1:2-1:8
                  text "a@b.co" @1:2-1:8

            """)
    }

    /// The curly quote that replaces `'` isn't a source byte, but the text holding it still spans the `'`.
    @Test("the text before an email autolink spans a smart quote")
    func smartQuoteBeforeEmail() throws {
        #expect(try tree("'a@b.co", options: Self.opts.union(.smart)) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "\u{2019}" @1:1-1:2
                link "mailto:a@b.co" "" @1:2-1:8
                  text "a@b.co" @1:2-1:8

            """)
    }

    @Test("with cmark bug compatibility, the text after an email autolink spans a NUL")
    func nulAfterEmail() throws {
        #expect(try tree("a@b.co\u{0}", options: Self.opts.union(.cmarkBugCompatibility)) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "" @1:1-1:1
                link "mailto:a@b.co" "" @1:1-1:7
                  text "a@b.co" @1:1-1:7
                text "\u{FFFD}" @1:7-1:8

            """)
    }

    /// With `.cmarkBugCompatibility` and footnotes, a footnote-shaped bracket whose `]` is on the next line collapses
    /// into reconstructed text with no source image of its own, so the address found in it has none either. The
    /// text before the address keeps where the bracket starts, as an empty range; the link and the text after it
    /// have no range, as in cmark-gfm.
    @Test("with cmark bug compatibility, the text before an email in a collapsed footnote bracket keeps its start")
    func emailInCollapsedFootnoteBracket() throws {
        #expect(try tree("![^b@.B\\\n]", options: Self.opts.union([.footnotes, .cmarkBugCompatibility])) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "![^" @1:1-1:1
                link "mailto:b@.B" "" @-
                  text "b@.B" @-
                text "\\\\\\n]" @-

            """)
    }

    /// The first address's last byte comes from the entity `&#111;`, which has no source byte of its own, so that
    /// address can't be placed: the text before it keeps only where it starts, and its link has no range, as in
    /// cmark-gfm. The second address is placed; the text between the two, whose start isn't known, starts where the
    /// second address does.
    @Test("an email autolink ending in an entity has no range")
    func emailEndingInEntity() throws {
        #expect(try tree("\u{0}a@b.c&#111; x@y.zz") == """
            document @1:1-1:20
              paragraph @1:1-1:20
                text "\u{FFFD}" @1:1-1:1
                link "mailto:a@b.co" "" @-
                  text "a@b.co" @-
                text " " @1:14-1:14
                link "mailto:x@y.zz" "" @1:14-1:20
                  text "x@y.zz" @1:14-1:20

            """)
    }
}
