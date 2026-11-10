/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Outside an open `[`, an extended www autolink comes at the start of the inline content, or after a space, tab, line
/// ending, `*`, `_`, `~` or `(`, and an extended url autolink, whose scheme is the whole run of ASCII letters before
/// `://`, may follow any character but an ASCII letter. An extended email autolink's local part is the run of
/// local-part characters before the `@`, so the autolink may follow any other character.
@Suite("Character before an extended autolink")
struct ExtendedAutolinkPrecedingCharacterTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .attributes, .gfmAutolink]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    // MARK: - Extended url autolinks

    @Test func urlAfterQuotationMarkIsLink() {
        #expect(tree("\"https://a.b\" in quotes;") == """
            document
              paragraph
                text "\\""
                link "https://a.b" ""
                  text "https://a.b"
                text "\\" in quotes;"

            """)
    }

    @Test func urlAfterExclamationMarkIsLink() {
        #expect(tree("!http://a.b") == """
            document
              paragraph
                text "!"
                link "http://a.b" ""
                  text "http://a.b"

            """)
    }

    @Test func urlAfterDigitIsLink() {
        #expect(tree("1ftp://a.b") == """
            document
              paragraph
                text "1"
                link "ftp://a.b" ""
                  text "ftp://a.b"

            """)
    }

    @Test func urlAfterNonASCIILetterIsLink() {
        #expect(tree("\u{E9}http://a.b") == """
            document
              paragraph
                text "\u{E9}"
                link "http://a.b" ""
                  text "http://a.b"

            """)
    }

    @Test func urlAfterASCIILetterIsText() {
        #expect(tree("xHTTP://a.b") == """
            document
              paragraph
                text "xHTTP://a.b"

            """)
    }

    @Test func urlInLinkTextBracketIsText() {
        #expect(tree("[http://a.b];") == """
            document
              paragraph
                text "[http://a.b];"

            """)
    }

    @Test func urlAfterParenthesisIsLink() {
        #expect(tree("(https://a.b") == """
            document
              paragraph
                text "("
                link "https://a.b" ""
                  text "https://a.b"

            """)
    }

    @Test(arguments: [
        (".http://e.e", """
            document
              paragraph
                text "."
                link "http://e.e" ""
                  text "http://e.e"

            """),
        ("-http://e.e", """
            document
              paragraph
                text "-"
                link "http://e.e" ""
                  text "http://e.e"

            """),
        ("/http://e.e", """
            document
              paragraph
                text "/"
                link "http://e.e" ""
                  text "http://e.e"

            """),
        ("*http://e.e", """
            document
              paragraph
                text "*"
                link "http://e.e" ""
                  text "http://e.e"

            """),
        ("_http://e.e", """
            document
              paragraph
                text "_"
                link "http://e.e" ""
                  text "http://e.e"

            """),
        ("~http://e.e", """
            document
              paragraph
                text "~"
                link "http://e.e" ""
                  text "http://e.e"

            """),
    ])
    func urlAfterPunctuationIsLink(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    /// A NUL is replaced with U+FFFD (Insecure characters), which is not a letter.
    @Test func urlAfterNULIsLink() {
        #expect(tree("\0http://e.e") == """
            document
              paragraph
                text "\u{FFFD}"
                link "http://e.e" ""
                  text "http://e.e"

            """)
    }

    /// The `x` is part of the scheme `xhttp`.
    @Test func urlAfterASCIILetterOfLowercaseSchemeIsText() {
        #expect(tree("xhttp://e.e") == """
            document
              paragraph
                text "xhttp://e.e"

            """)
    }

    /// A paragraph's initial spaces are stripped (Paragraphs).
    @Test func urlStartingParagraphAfterLeadingSpaceIsLink() {
        #expect(tree(" http://e.e") == """
            document
              paragraph
                link "http://e.e" ""
                  text "http://e.e"

            """)
    }

    @Test(arguments: [
        ("x\u{0B}http://a.b", """
            document
              paragraph
                text "x\\u{B}"
                link "http://a.b" ""
                  text "http://a.b"

            """),
        ("x\u{0C}http://a.b", """
            document
              paragraph
                text "x\\u{C}"
                link "http://a.b" ""
                  text "http://a.b"

            """),
    ])
    func urlAfterLineTabulationOrFormFeedIsLink(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    // MARK: - Extended www autolinks

    @Test(arguments: [
        ("x\u{0B}www.a.b", """
            document
              paragraph
                text "x\\u{B}www.a.b"

            """),
        ("x\u{0C}www.a.b", """
            document
              paragraph
                text "x\\u{C}www.a.b"

            """),
    ])
    func wwwAfterLineTabulationOrFormFeedIsText(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test func wwwAfterTabIsLink() {
        #expect(tree("x\twww.a.b") == """
            document
              paragraph
                text "x\\t"
                link "http://www.a.b" ""
                  text "www.a.b"

            """)
    }

    @Test func wwwAfterParenthesisIsLink() {
        #expect(tree("(www.e.f") == """
            document
              paragraph
                text "("
                link "http://www.e.f" ""
                  text "www.e.f"

            """)
    }

    @Test(arguments: [
        (".www.a.b", """
            document
              paragraph
                text ".www.a.b"

            """),
        ("\"www.a.b", """
            document
              paragraph
                text "\\"www.a.b"

            """),
        ("\u{E9}www.a.b", """
            document
              paragraph
                text "éwww.a.b"

            """),
        ("!www.e.f", """
            document
              paragraph
                text "!www.e.f"

            """),
    ])
    func wwwAfterOtherCharacterIsText(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    // MARK: - Extended email autolinks

    @Test(arguments: [
        ("x\u{0B}foo@b.cd", """
            document
              paragraph
                text "x\\u{B}"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """),
        ("x\u{0C}foo@b.cd", """
            document
              paragraph
                text "x\\u{C}"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """),
    ])
    func emailAfterLineTabulationOrFormFeedIsLink(markdown: String, expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test func emailAfterLessThanSignIsLink() {
        #expect(tree("<o@e.e;") == """
            document
              paragraph
                text "<"
                link "mailto:o@e.e" ""
                  text "o@e.e"
                text ";"

            """)
    }

    @Test func emailAfterExclamationMarkIsLink() {
        #expect(tree("!foo@b.cd;") == """
            document
              paragraph
                text "!"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"
                text ";"

            """)
    }

    @Test func emailAfterAtSignIsLink() {
        #expect(tree("a@b@c.de") == """
            document
              paragraph
                text "a@"
                link "mailto:b@c.de" ""
                  text "b@c.de"

            """)
    }

    /// `MAILTO:` is not the lowercase `mailto:` scheme, so the `:` ends the local part.
    @Test func emailAfterUppercaseSchemeIsLink() {
        #expect(tree("MAILTO:x@a.b.") == """
            document
              paragraph
                text "MAILTO:"
                link "mailto:x@a.b" ""
                  text "x@a.b"
                text "."

            """)
    }

    /// A `mailto:` scheme right after a letter is not a scheme, so the `:` ends the local part.
    @Test func emailAfterLetterAndSchemeIsLink() {
        #expect(tree("amailto:foo@b.cd") == """
            document
              paragraph
                text "amailto:"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailWithSchemeAfterSpaceIsLink() {
        #expect(tree("x mailto:foo@b.cd") == """
            document
              paragraph
                text "x "
                link "mailto:foo@b.cd" ""
                  text "mailto:foo@b.cd"

            """)
    }

    @Test func emailAfterCodeSpanIsLink() {
        #expect(tree("`x`foo@b.cd") == """
            document
              paragraph
                code "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailAfterLinkIsLink() {
        #expect(tree("[x](u)foo@b.cd") == """
            document
              paragraph
                link "u" ""
                  text "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailInUnresolvedBracketsIsLink() {
        #expect(tree("[foo@b.cd]") == """
            document
              paragraph
                text "["
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"
                text "]"

            """)
    }

    @Test func emailOpeningImageDescriptionIsLink() {
        #expect(tree("![foo@b.cd](u)") == """
            document
              paragraph
                image "u" ""
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func emailOpeningAttributeTextIsLink() {
        #expect(tree("^[foo@b.cd](k: 1)") == """
            document
              paragraph
                attribute "k: 1"
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func emailOpeningEmphasisIsLink() {
        #expect(tree("*foo@b.cd*") == """
            document
              paragraph
                emph
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func emailOpeningStrikethroughIsLink() {
        #expect(tree("~foo@b.cd~") == """
            document
              paragraph
                strikethrough
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func emailAfterEmphasisIsLink() {
        #expect(tree("*x*foo@b.cd") == """
            document
              paragraph
                emph
                  text "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailAfterStrongEmphasisIsLink() {
        #expect(tree("**x**foo@b.cd") == """
            document
              paragraph
                strong
                  text "x"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailOpeningStrongEmphasisIsLink() {
        #expect(tree("**foo@b.cd**") == """
            document
              paragraph
                strong
                  link "mailto:foo@b.cd" ""
                    text "foo@b.cd"

            """)
    }

    @Test func emailAfterRawHTMLIsLink() {
        #expect(tree("<b>foo@b.cd") == """
            document
              paragraph
                html_inline "<b>"
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailOpeningTableCellIsLink() {
        #expect(tree("|foo@b.cd|\n|-|") == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    link "mailto:foo@b.cd" ""
                      text "foo@b.cd"

            """)
    }

    @Test func emailAfterSoftBreakIsLink() {
        #expect(tree("x\nfoo@b.cd") == """
            document
              paragraph
                text "x"
                softbreak
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test func emailAfterHardBreakIsLink() {
        #expect(tree("x\\\nfoo@b.cd") == """
            document
              paragraph
                text "x"
                linebreak
                link "mailto:foo@b.cd" ""
                  text "foo@b.cd"

            """)
    }

    @Test("email autolinks after a leading `<`")
    func emailAfterAngle() {
        // Without a `>`, the `<` is literal text.
        #expect(tree("<o@e.e") == """
            document
              paragraph
                text "<"
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    @Test("standalone email autolinks")
    func emailStandalone() {
        #expect(tree("o@e.e") == """
            document
              paragraph
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    @Test("email after text and a space autolinks")
    func emailAfterTextSpace() {
        #expect(tree("x o@e.e") == """
            document
              paragraph
                text "x "
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    @Test("email after `(` autolinks")
    func emailAfterParen() {
        #expect(tree("(o@e.e") == """
            document
              paragraph
                text "("
                link "mailto:o@e.e" ""
                  text "o@e.e"

            """)
    }

    // MARK: - Local-part characters

    // An extended email autolink's local part holds only alphanumerics, `.`, `-`, `_` and `+`, unlike the email
    // address of an email autolink (Autolinks), which admits characters such as `!`.

    @Test("`<a!@e.e` is text: `!` is not a local-part character")
    func bangBeforeAtNoLink() {
        #expect(tree("<a!@e.e") == """
            document
              paragraph
                text "<a!@e.e"

            """)
    }

    @Test("`x!@e.e` at the start of a line is text")
    func bangLocalAtStartNoLink() {
        #expect(tree("x!@e.e") == """
            document
              paragraph
                text "x!@e.e"

            """)
    }

    @Test("an email autolink admits `!` in its local part")
    func angleEmailKeepsBroadLocalSet() {
        #expect(tree("<a!b@c.de>") == """
            document
              paragraph
                link "mailto:a!b@c.de" ""
                  text "a!b@c.de"

            """)
    }
}
