/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An extended www autolink comes at the start of the inline content, or after a space, tab, line ending, `*`, `_`,
/// `~` or `(`. An extended url autolink's scheme is the whole run of ASCII letters before `://`, so the autolink may
/// follow any character but a letter. An extended email autolink's local part is the run of local-part characters
/// before the `@`, so the autolink may follow any other character.
@Suite("Character before an extended autolink")
struct ExtendedAutolinkPrecedingCharacterTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .attributes, .gfmAutolink]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    private func text(_ literal: String) -> String {
        "document\n  paragraph\n    text \"\(literal)\"\n"
    }

    // MARK: - Extended url autolinks

    @Test func testURLAfterQuotationMarkIsLink() {
        #expect(surface("\"https://a.b\" in quotes;") == """
            document
              paragraph
                text "\\""
                link "https://a.b" ""
                  text "https://a.b"
                text "\\" in quotes;"

            """)
    }

    @Test func testURLAfterExclamationMarkIsLink() {
        #expect(surface("!http://a.b") == """
            document
              paragraph
                text "!"
                link "http://a.b" ""
                  text "http://a.b"

            """)
    }

    @Test func testURLAfterDigitIsLink() {
        #expect(surface("1ftp://a.b") == """
            document
              paragraph
                text "1"
                link "ftp://a.b" ""
                  text "ftp://a.b"

            """)
    }

    @Test func testURLAfterNonASCIILetterIsLink() {
        #expect(surface("\u{E9}http://a.b") == """
            document
              paragraph
                text "\u{E9}"
                link "http://a.b" ""
                  text "http://a.b"

            """)
    }

    @Test func testURLAfterASCIILetterIsText() {
        #expect(surface("xHTTP://a.b") == text("xHTTP://a.b"))
    }

    @Test func testURLInLinkTextBracketIsText() {
        #expect(surface("[http://a.b];") == text("[http://a.b];"))
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

    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func testURLAfterLineTabulationOrFormFeedIsLink(_ whitespace: String, _ escaped: String) {
        #expect(surface("x" + whitespace + "http://a.b") == """
            document
              paragraph
                text "x\(escaped)"
                link "http://a.b" ""
                  text "http://a.b"

            """)
    }

    // MARK: - Extended www autolinks

    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func testWWWAfterLineTabulationOrFormFeedIsText(_ whitespace: String, _ escaped: String) {
        #expect(surface("x" + whitespace + "www.a.b") == text("x\(escaped)www.a.b"))
    }

    @Test func testWWWAfterTabIsLink() {
        #expect(surface("x\twww.a.b") == """
            document
              paragraph
                text "x\\t"
                link "http://www.a.b" ""
                  text "www.a.b"

            """)
    }

    @Test(arguments: [(".", "."), ("\"", "\\\""), ("\u{E9}", "\u{E9}")])
    func testWWWAfterOtherCharacterIsText(_ preceding: String, _ escaped: String) {
        #expect(surface(preceding + "www.a.b") == text(escaped + "www.a.b"))
    }

    // MARK: - Extended email autolinks

    @Test(arguments: [("\u{0B}", "\\u{B}"), ("\u{0C}", "\\u{C}")])
    func testEmailAfterLineTabulationOrFormFeedIsLink(_ whitespace: String, _ escaped: String) {
        #expect(surface("x" + whitespace + "foo@b.cd") == """
            document
              paragraph
                text "x\(escaped)"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterLessThanSignIsLink() {
        #expect(surface("<o@e.e;") == """
            document
              paragraph
                text "<"
                link "mailto:o@e.e" ""
                  text "o@e.e"
                text ";"

            """)
    }

    @Test func testEmailAfterExclamationMarkIsLink() {
        #expect(surface("!foo@b.cd;") == """
            document
              paragraph
                text "!"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"
                text ";"

            """)
    }

    @Test func testEmailAfterAtSignIsLink() {
        #expect(surface("a@b@c.de") == """
            document
              paragraph
                text "a@"
                link "mailto:b@c.de" ""
                  text "b@c.de"

            """)
    }

    /// `MAILTO:` is not the lowercase `mailto:` scheme, so the `:` ends the local part.
    @Test func testEmailAfterUppercaseSchemeIsLink() {
        #expect(surface("MAILTO:x@a.b.") == """
            document
              paragraph
                text "MAILTO:"
                link "mailto:x@a.b" ""
                  text "x@a.b"
                text "."

            """)
    }

    /// A `mailto:` scheme right after a letter is not a scheme, so the `:` ends the local part.
    @Test func testEmailAfterLetterAndSchemeIsLink() {
        #expect(surface("amailto:foo@b.cd") == """
            document
              paragraph
                text "amailto:"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
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

    @Test func testEmailAfterCodeSpanIsLink() {
        #expect(surface("`x`foo@b.cd") == """
            document
              paragraph
                code "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterLinkIsLink() {
        #expect(surface("[x](u)foo@b.cd") == """
            document
              paragraph
                link "u" ""
                  text "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailInUnresolvedBracketsIsLink() {
        #expect(surface("[foo@b.cd]") == """
            document
              paragraph
                text "["
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"
                text "]"

            """)
    }

    @Test func testEmailOpeningImageDescriptionIsLink() {
        #expect(surface("![foo@b.cd](u)") == """
            document
              paragraph
                image "u" ""
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningAttributeTextIsLink() {
        #expect(surface("^[foo@b.cd](k: 1)") == """
            document
              paragraph
                attribute "k: 1"
                  link "mailto:foo@b.cd" ""
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

    @Test func testEmailAfterStrongEmphasisIsLink() {
        #expect(surface("**x**foo@b.cd") == """
            document
              paragraph
                strong
                  text "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningStrongEmphasisIsLink() {
        #expect(surface("**foo@b.cd**") == """
            document
              paragraph
                strong
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func testEmailAfterRawHTMLIsLink() {
        #expect(surface("<b>foo@b.cd") == """
            document
              paragraph
                html_inline "<b>"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func testEmailOpeningTableCellIsLink() {
        #expect(surface("|foo@b.cd|\n|-|") == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
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
