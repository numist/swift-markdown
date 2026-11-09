/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// After its domain, an extended url or www autolink runs to the first space or `<` (Autolinks (extension)), so `>` is
/// part of it, as is an entity reference before its end. A trailing `?`, `!`, `.`, `,`, `:`, `*`, `_`, `~`, `'`, `"` or
/// `;` is not part of it, nor is an unmatched trailing `)`, and a trailing `;` takes a preceding `&` and ASCII letters
/// with it.
@Suite("Extended autolink end and trailing punctuation")
struct AutolinkURLDelimiterTests {

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [.gfmAutolink])
    }

    @Test("`http://a.l>` links with the `>` in its text")
    func greaterThanKept() {
        #expect(tree("http://a.l>") == """
            document
              paragraph
                link "http://a.l>" ""
                  text "http://a.l>"

            """)
    }

    // MARK: - Trailing characters

    @Test("trailing `'` is trimmed")
    func apostropheTrimmed() {
        #expect(tree("http://a.l'") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "'"

            """)
    }

    @Test("trailing `\"` is trimmed")
    func doubleQuoteTrimmed() {
        #expect(tree("http://a.l\"") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "\\""

            """)
    }

    @Test("trailing `;` with no entity is trimmed")
    func semicolonTrimmed() {
        #expect(tree("http://a.l;") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text ";"

            """)
    }

    // MARK: - Entity-like `;` tails

    @Test("a trailing `&` + ASCII letters + `;` is removed whole")
    func semicolonEntityStripped() {
        // `&zq;` is not an entity reference, so the trailing text is literal.
        #expect(tree("http://a.x/&zq;") == """
            document
              paragraph
                link "http://a.x/" ""
                  text "http://a.x/"
                text "&zq;"

            """)
    }

    @Test("with a digit between `&` and `;`, only the `;` is removed")
    func semicolonEntityWithDigitStripped() {
        #expect(tree("http://a.l/&am2;") == """
            document
              paragraph
                link "http://a.l/&am2" ""
                  text "http://a.l/&am2"
                text ";"

            """)
    }

    @Test("an entity reference before the end is part of the URL and stays literal")
    func entityReferenceInsideStaysLiteral() {
        #expect(tree("http://a.a&amp;b") == """
            document
              paragraph
                link "http://a.a&amp;b" ""
                  text "http://a.a&amp;b"

            """)
    }

    // MARK: - Multi-trailing sequences

    @Test("`http://a.l');` removes `;`, then the unbalanced `)`, then `'`")
    func multiTrailingApostropheParenSemicolon() {
        #expect(tree("http://a.l');") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "');"

            """)
    }

    @Test("`http://a.l>.` keeps `>` and trims the trailing `.`")
    func multiTrailingGreaterThanDot() {
        #expect(tree("http://a.l>.") == """
            document
              paragraph
                link "http://a.l>" ""
                  text "http://a.l>"
                text "."

            """)
    }

    @Test("`http://a.l>>` keeps both trailing `>`")
    func multiTrailingDoubleGreaterThan() {
        #expect(tree("http://a.l>>") == """
            document
              paragraph
                link "http://a.l>>" ""
                  text "http://a.l>>"

            """)
    }

    // MARK: - Whitespace at the end of a paragraph

    // The paragraph's raw content has its final whitespace removed, and the spec's whitespace includes
    // line tabulation and form feed (Paragraphs), so neither ends the URL.


    @Test("a trailing vertical tab (0x0B) is not part of the URL")
    func verticalTabRemoved() {
        #expect(tree("http://a.l\u{B}") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"

            """)
    }

    @Test("a trailing form feed (0x0C) is not part of the URL")
    func formFeedRemoved() {
        #expect(tree("http://a.l\u{C}") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"

            """)
    }

    // MARK: - Trailing punctuation and parentheses

    @Test("trailing `.` is trimmed")
    func dotTrimmed() {
        #expect(tree("http://a.l.") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "."

            """)
    }

    @Test("trailing `!` is trimmed")
    func bangTrimmed() {
        #expect(tree("http://a.l!") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "!"

            """)
    }

    @Test("a lone unbalanced trailing `)` is trimmed")
    func unbalancedParenTrimmed() {
        #expect(tree("http://a.l)") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text ")"

            """)
    }

    @Test("`<` ends the URL")
    func lessThanBoundary() {
        #expect(tree("http://a.l<") == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "<"

            """)
    }

    @Test("balanced parentheses are kept")
    func balancedParensKept() {
        #expect(tree("http://e.com/(a)") == """
            document
              paragraph
                link "http://e.com/(a)" ""
                  text "http://e.com/(a)"

            """)
    }

    @Test("only the extra unbalanced `)` is trimmed")
    func extraParenTrimmed() {
        #expect(tree("http://e.com/(a))") == """
            document
              paragraph
                link "http://e.com/(a)" ""
                  text "http://e.com/(a)"
                text ")"

            """)
    }

    @Test("trailing `,`, `?`, `:`, `*`, `_` and `~` are each trimmed", arguments: [",", "?", ":", "*", "_", "~"])
    func remainingTrailingPunctuationTrimmed(_ punctuation: String) {
        #expect(tree("http://a.l" + punctuation) == """
            document
              paragraph
                link "http://a.l" ""
                  text "http://a.l"
                text "\(punctuation)"

            """)
    }

    // MARK: - Extended www autolinks

    @Test("www: trailing `'` is trimmed")
    func wwwApostropheTrimmed() {
        #expect(tree("www.a.b'") == """
            document
              paragraph
                link "http://www.a.b" ""
                  text "www.a.b"
                text "'"

            """)
    }

    @Test("www: trailing `>` is kept")
    func wwwGreaterThanKept() {
        #expect(tree("www.a.b>") == """
            document
              paragraph
                link "http://www.a.b>" ""
                  text "www.a.b>"

            """)
    }
}
