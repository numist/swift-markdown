/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Every extended autolink, whether www, url or email, comes only at the beginning of a line, after whitespace, or
/// after `*`, `_`, `~` or `(` (Autolinks (extension)).
@Suite("Character before an extended autolink")
struct ExtendedAutolinkPrecedingCharacterTests {
    private static let options: MarkdownDocument.ParseOptions = [.strikethrough, .attributes, .gfmAutolink]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    // MARK: - Extended url autolinks

    @Test func testURLAfterExclamationMarkIsText() {
        #expect(surface("!http://a.b") == text("!http://a.b"))
    }

    @Test func testURLAfterDigitIsText() {
        #expect(surface("1ftp://a.b") == text("1ftp://a.b"))
    }

    @Test func testURLAfterParenthesisIsLink() {
        #expect(surface("(https://a.b") == """
            document
              paragraph
                text "("
                link "https://a.b" ""
                  text "https://a.b"

            """)
    }

    // MARK: - Extended email autolinks

    @Test func testEmailAfterLessThanSignIsText() {
        #expect(surface("<o@e.e") == text("<o@e.e"))
    }

    @Test func testEmailAfterExclamationMarkIsText() {
        #expect(surface("!foo@b.cd") == text("!foo@b.cd"))
    }

    @Test func testEmailAfterAtSignIsText() {
        #expect(surface("a@b@c.de") == text("a@b@c.de"))
    }

    @Test func testEmailAfterLetterAndSchemeIsText() {
        #expect(surface("amailto:foo@b.cd") == text("amailto:foo@b.cd"))
    }

    @Test func testEmailWithSchemeAfterSpaceIsLink() {
        #expect(surface("x mailto:foo@b.cd") == """
            document
              paragraph
                text "x "
                link "mailto:foo@b.cd" ""
                  text "mailto:foo@b.cd"

            """)
    }

    @Test func testEmailAfterCodeSpanIsText() {
        #expect(surface("`x`foo@b.cd") == """
            document
              paragraph
                code "x"
                text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterLinkIsText() {
        #expect(surface("[x](u)foo@b.cd") == """
            document
              paragraph
                link "u" ""
                  text "x"
                text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningImageDescriptionIsText() {
        #expect(surface("![foo@b.cd](u)") == """
            document
              paragraph
                image "u" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningAttributeTextIsText() {
        #expect(surface("^[foo@b.cd](k: 1)") == """
            document
              paragraph
                attribute "k: 1"
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningEmphasisIsLink() {
        #expect(surface("*foo@b.cd*") == """
            document
              paragraph
                emph
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningStrikethroughIsLink() {
        #expect(surface("~foo@b.cd~") == """
            document
              paragraph
                strikethrough
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterEmphasisIsLink() {
        #expect(surface("*x*foo@b.cd") == """
            document
              paragraph
                emph
                  text "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterSoftBreakIsLink() {
        #expect(surface("x\nfoo@b.cd") == """
            document
              paragraph
                text "x"
                softbreak
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterHardBreakIsLink() {
        #expect(surface("x\\\nfoo@b.cd") == """
            document
              paragraph
                text "x"
                linebreak
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }
}
