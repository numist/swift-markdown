/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("`[^[` footnote-shaped bracket inside a link bracket")
struct FootnoteNestedBracketLinkTests {

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: [.sourcePosition, .footnotes, .attributes])
    }

    // MARK: - `]()` closes a link

    @Test("`[^[]]()` forms a link whose text is `^[]`")
    func caretBracketImmediateParensFormsLink() {
        #expect(tree("[^[]]()") == """
            document
              paragraph
                link "" ""
                  text "^[]"

            """)
    }

    @Test("`[[^[]]()` is literal `[` plus a link whose text is `^[]`")
    func caretBracketPrefixedLink() {
        #expect(tree("[[^[]]()") == """
            document
              paragraph
                text "["
                link "" ""
                  text "^[]"

            """)
    }

    // MARK: - Unclosed and single-close shapes

    @Test("`[^[]` stays literal `[^[]`")
    func caretBracketUnclosedStaysLiteral() {
        #expect(tree("[^[]") == """
            document
              paragraph
                text "[^[]"

            """)
    }

    @Test("`[^[]()` is literal `[` plus an empty inline attribute")
    func caretBracketSingleCloseIsAttribute() {
        #expect(tree("[^[]()") == """
            document
              paragraph
                text "["
                attribute ""

            """)
    }

    // MARK: - An inner `^[…](…)` is an inline attribute

    @Test("`[^[]()]`: the inner `^[]()` is an empty attribute, so `[` + attribute + `]`")
    func caretBracketAttributeInsideOuterBracket() {
        #expect(tree("[^[]()]") == """
            document
              paragraph
                text "["
                attribute ""
                text "]"

            """)
    }

    @Test("`[^[x](y)]`: the inner `^[x](y)` is a non-empty attribute wrapping `x`, so `[` + attribute[`x`] + `]`")
    func caretBracketNonEmptyAttributeInsideOuterBracket() {
        #expect(tree("[^[x](y)]") == """
            document
              paragraph
                text "["
                attribute "y"
                  text "x"
                text "]"

            """)
    }

    // MARK: - `[^[…]` is literal text

    // `[^[` opens no footnote reference, because a label may not contain an unescaped `[` (Links).

    @Test("`[[^[]]]()` is a link whose text is `[^[]]`")
    func nestedCaretBracketFormsLink() {
        #expect(tree("[[^[]]]()") == """
            document
              paragraph
                link "" ""
                  text "[^[]]"

            """)
    }

    @Test("`[^[]]` stays literal `[^[]]`")
    func caretBracketTopLevelStaysLiteral() {
        #expect(tree("[^[]]") == """
            document
              paragraph
                text "[^[]]"

            """)
    }

    @Test("`x[^[]]y` stays literal `x[^[]]y`")
    func caretBracketKeepsTrailingText() {
        #expect(tree("x[^[]]y") == """
            document
              paragraph
                text "x[^[]]y"

            """)
    }

    @Test("`[[^[]]]` stays literal `[[^[]]]`")
    func nestedCaretBracketWithoutParens() {
        #expect(tree("[[^[]]]") == """
            document
              paragraph
                text "[[^[]]]"

            """)
    }

    @Test("`[^[]y]` stays literal `[^[]y]`")
    func caretBracketNonAttributeInsideOuterBracket() {
        #expect(tree("[^[]y]") == """
            document
              paragraph
                text "[^[]y]"

            """)
    }
}
