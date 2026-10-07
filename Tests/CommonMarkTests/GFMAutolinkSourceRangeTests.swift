/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of extended autolinks (Autolinks (extension)): a bare URL, a `www.` domain, and an email address. The
/// link and its text span the matched bytes. Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Source ranges of extended autolinks")
struct GFMAutolinkSourceRangeTests {

    private static let opts: MarkdownDocument.ParseOptions = [.sourcePosition, .gfmAutolink]

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = opts) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

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

    /// The U+FFFD that replaces a NUL (Insecure characters) spans the NUL, and the address spans its own bytes.
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

    /// The curly quote that replaces `'` spans the `'`.
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
    func emailEndingInCharacterReferenceBeforeAnotherEmail() {
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

    @Test("a URL autolink has no empty text before it")
    func noEmptyTextBeforeURL() {
        #expect(tree("http://a.a") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                link "http://a.a" "" @1:1-1:11
                  text "http://a.a" @1:1-1:11

            """)
    }

    @Test("an email autolink has no empty texts beside it")
    func noEmptyTextsBesideEmail() {
        #expect(tree("a@b.co") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                link "mailto:a@b.co" "" @1:1-1:7
                  text "a@b.co" @1:1-1:7

            """)
    }

    /// The U+FFFD that replaces a NUL spans the NUL, and no text precedes the link.
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

    /// A backslash before a line ending is a hard line break (Hard line breaks), and `[^b@b.B` matches no footnote
    /// definition, so the bracket is text spanning its own bytes on either side of the email autolink.
    @Test("an email in an undefined footnote-shaped bracket across a hard line break spans the address")
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

    @Test("an email ending in a character reference spans the reference")
    func emailEndingInCharacterReference() {
        #expect(tree("a@b.&#99;") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "mailto:a@b.c" "" @1:1-1:10
                  text "a@b.c" @1:1-1:10

            """)
    }

    @Test("an email ending in a character reference after other references spans its own reference")
    func emailEndingInCharacterReferenceAfterOtherReferences() {
        #expect(tree("&amp;&amp; a@b.&#99;") == """
            document @1:1-1:21
              paragraph @1:1-1:21
                text "&& " @1:1-1:12
                link "mailto:a@b.c" "" @1:12-1:21
                  text "a@b.c" @1:12-1:21

            """)
    }

    @Test("an email starting in a character reference spans the reference")
    func emailStartingInCharacterReference() {
        #expect(tree("&#97;@b.c") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "mailto:a@b.c" "" @1:1-1:10
                  text "a@b.c" @1:1-1:10

            """)
    }

    @Test("an email ending in a character reference on a block quote's second line spans the reference")
    func emailEndingInCharacterReferenceOnContinuationLine() {
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
