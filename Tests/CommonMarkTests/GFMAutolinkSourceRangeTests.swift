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
/// its text span the matched bytes. Columns are 1-based UTF-8 byte offsets and each end is
/// half-open.
@Suite("Source ranges of GFM autolinks")
struct GFMAutolinkSourceRangeTests {

    private static let opts: MarkdownDocument.ParseOptions = [.sourcePosition, .gfmAutolink]

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = opts) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    /// cmark-gfm stretches the `(` to `@1:1-1:6` and starts the link at `@1:1`, because it rewinds over the scheme
    /// after emitting it as text.
    @Test("a URL autolink spans the URL")
    func url() {
        #expect(tree("(http://e.e") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                text "(" @1:1-1:2
                link "http://e.e" "" @1:2-1:12
                  text "http://e.e" @1:2-1:12

            """)
    }

    /// cmark-gfm starts the link at `@1:1`, the paragraph's line start.
    @Test("a www autolink spans the domain")
    func www() {
        #expect(tree(" www.w.w") == """
            document @1:1-1:9
              paragraph @1:2-1:9
                link "http://www.w.w" "" @1:2-1:9
                  text "www.w.w" @1:2-1:9

            """)
    }

    @Test("an email autolink spans the address")
    func email() {
        #expect(tree("x a@b.co y") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "x " @1:1-1:3
                link "mailto:a@b.co" "" @1:3-1:9
                  text "a@b.co" @1:3-1:9
                text " y" @1:9-1:11

            """)
    }

    /// A NUL makes the paragraph's text a copy with the NUL replaced by U+FFFD; the address is still placed on its
    /// source bytes, and the U+FFFD before it on the NUL.
    @Test("an email autolink after a NUL spans the address")
    func emailAfterNUL() {
        #expect(tree("\u{0}a@b.co") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "\u{FFFD}" @1:1-1:2
                link "mailto:a@b.co" "" @1:2-1:8
                  text "a@b.co" @1:2-1:8

            """)
    }

    /// The curly quote that replaces `'` isn't a source byte, but the text holding it still spans the `'`.
    @Test("the text before an email autolink spans a smart quote")
    func smartQuoteBeforeEmail() {
        #expect(tree("'a@b.co", options: Self.opts.union(.smart)) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "\u{2019}" @1:1-1:2
                link "mailto:a@b.co" "" @1:2-1:8
                  text "a@b.co" @1:2-1:8

            """)
    }

    /// The first address's last character comes from the character reference `&#111;`, so that address ends just
    /// past the reference's `;`. The text before it is the NUL, and the text between the two addresses is the space.
    @Test("an email autolink ending in a character reference ends past the reference")
    func emailEndingInEntity() {
        #expect(tree("\u{0}a@b.c&#111; x@y.zz") == """
            document @1:1-1:20
              paragraph @1:1-1:20
                text "\u{FFFD}" @1:1-1:2
                link "mailto:a@b.co" "" @1:2-1:13
                  text "a@b.co" @1:2-1:13
                text " " @1:13-1:14
                link "mailto:x@y.zz" "" @1:14-1:20
                  text "x@y.zz" @1:14-1:20

            """)
    }

    /// A URL autolink at the start of a paragraph is just the link, whereas cmark-gfm also leaves an empty text node
    /// before it.
    @Test("a URL autolink has no empty text before it")
    func noEmptyTextBeforeURL() {
        #expect(tree("http://a.a") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                link "http://a.a" "" @1:1-1:11
                  text "http://a.a" @1:1-1:11

            """)
    }

    /// An email autolink that fills its paragraph is just the link, whereas cmark-gfm also leaves empty text nodes on
    /// both sides of it.
    @Test("an email autolink has no empty texts beside it")
    func noEmptyTextsBesideEmail() {
        #expect(tree("a@b.co") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "mailto:a@b.co" "" @1:1-1:7
                  text "a@b.co" @1:1-1:7

            """)
    }

    /// The text after an email autolink spans the NUL its U+FFFD replaces and no text precedes the link, whereas
    /// cmark-gfm also leaves an empty text node before it.
    @Test("the text after an email autolink spans a NUL")
    func nulAfterEmailWithoutEmptyText() {
        #expect(tree("a@b.co\u{0}") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "mailto:a@b.co" "" @1:1-1:7
                  text "a@b.co" @1:1-1:7
                text "\u{FFFD}" @1:7-1:8

            """)
    }

    /// A backslash before a line ending is a hard line break and the footnote-shaped bracket matches no definition, so
    /// the bracket stays text placed on its bytes around the email autolink, whereas cmark-gfm collapses it into
    /// reconstructed text that can't be placed.
    @Test("an email in an undefined footnote-shaped bracket spanning a hard break is placed")
    func emailInUndefinedFootnoteBracket() {
        #expect(tree("![^b@b.B\\\n]", options: Self.opts.union(.footnotes)) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "![^" @1:1-1:4
                link "mailto:b@b.B" "" @1:4-1:9
                  text "b@b.B" @1:4-1:9
                linebreak @-
                text "]" @2:1-2:2

            """)
    }

    @Test("an email ending in an entity reference spans the reference")
    func emailEndingInEntityReference() {
        #expect(tree("a@b.&#99;") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "mailto:a@b.c" "" @1:1-1:10
                  text "a@b.c" @1:1-1:10

            """)
    }

    @Test("an email ending in an entity reference after other references spans its own reference")
    func emailEndingInEntityReferenceAfterOtherReferences() {
        #expect(tree("&amp;&amp; a@b.&#99;") == """
            document @1:1-1:21
              paragraph @1:1-1:21
                text "&& " @1:1-1:12
                link "mailto:a@b.c" "" @1:12-1:21
                  text "a@b.c" @1:12-1:21

            """)
    }

    @Test("an email starting in an entity reference spans the reference")
    func emailStartingInEntityReference() {
        #expect(tree("&#97;@b.c") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "mailto:a@b.c" "" @1:1-1:10
                  text "a@b.c" @1:1-1:10

            """)
    }

    @Test("an email ending in an entity reference on a block quote's second line spans the reference")
    func emailEndingInEntityReferenceOnContinuationLine() {
        #expect(tree("> x\n> a@b.&#99;") == """
            document @1:1-2:12
              block_quote @1:1-2:12
                paragraph @1:3-2:12
                  text "x" @1:3-1:4
                  softbreak @-
                  link "mailto:a@b.c" "" @2:3-2:12
                    text "a@b.c" @2:3-2:12

            """)
    }
}
