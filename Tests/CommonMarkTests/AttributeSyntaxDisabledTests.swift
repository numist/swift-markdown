/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parses without `.attributes`, where neither `^[text](attrs)` nor `^[label]: attrs` is special: `^` is ordinary text,
/// the brackets after it follow the CommonMark link rules, and a `^[label]:` line is ordinary paragraph content.
///
/// Each test mirrors a test that pins attribute behaviour with `.attributes` set, and asserts the whole tree for the same
/// input with the option off. Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Attribute syntax without the attributes option")
struct AttributeSyntaxDisabledTests {

    private static let plain: MarkdownDocument.ParseOptions = [.sourcePosition]
    private static let footnotes: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]
    private static let footnotesAutolink: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes, .gfmAutolink]

    private func tree(_ source: String, _ options: MarkdownDocument.ParseOptions) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    // MARK: - Inline form

    /// `[hello](color: red)` is not an inline link, because a destination followed by an unquoted title is not a link,
    /// and `[hello]` matches no definition, so the whole line is text.
    @Test("an inline attribute whose attributes contain a space is text")
    func inlineFormIsText() {
        #expect(tree("^[hello](color: red)", Self.plain) == """
            document @1:1-1:21
              paragraph @1:1-1:21
                text "^[hello](color: red)" @1:1-1:21

            """)
    }

    /// `[](attr)` is an inline link with empty text, so `^` is text before the link.
    @Test("an empty inline attribute is text followed by an empty link")
    func emptyInlineFormIsLink() {
        #expect(tree("^[](attr)", Self.plain) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^" @1:1-1:2
                link "attr" "" @1:2-1:10

            """)
    }

    /// A destination followed by an unquoted title is not a link, so the whole line is text.
    @Test("comma-separated attributes are text")
    func attributesWithWhitespaceAreText() {
        #expect(tree("^[x](color: red, weight: bold)", Self.plain) == """
            document @1:1-1:31
              paragraph @1:1-1:31
                text "^[x](color: red, weight: bold)" @1:1-1:31

            """)
    }

    /// A destination that ends at a space with an unbalanced `(` is not a link destination, so the whole line is text.
    @Test("attributes with balanced parentheses and spaces are text")
    func attributesWithParensAreText() {
        #expect(tree("^[x](rgb(255, 0, 0))", Self.plain) == """
            document @1:1-1:21
              paragraph @1:1-1:21
                text "^[x](rgb(255, 0, 0))" @1:1-1:21

            """)
    }

    /// `[x](a\)b)` is an inline link whose destination unescapes `\)` to `)`.
    @Test("attributes with an escaped parenthesis are a link destination")
    func attributesWithEscapedParenAreLink() {
        #expect(tree("^[x](a\\)b)", Self.plain) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "^" @1:1-1:2
                link "a)b" "" @1:2-1:11
                  text "x" @1:3-1:4

            """)
    }

    /// `[middle](attr)` is an inline link, so the `^` joins the text before it.
    @Test("an inline attribute between text is a link between text")
    func surroundingTextAroundLink() {
        #expect(tree("before ^[middle](attr) after", Self.plain) == """
            document @1:1-1:29
              paragraph @1:1-1:29
                text "before ^" @1:1-1:9
                link "attr" "" @1:9-1:23
                  text "middle" @1:10-1:16
                text " after" @1:23-1:29

            """)
    }

    /// Emphasis inside link text resolves inside the link.
    @Test("emphasis inside an inline attribute is emphasis inside a link")
    func emphasisInsideLink() {
        #expect(tree("^[*foo*](attr)", Self.plain) == """
            document @1:1-1:15
              paragraph @1:1-1:15
                text "^" @1:1-1:2
                link "attr" "" @1:2-1:15
                  emph @1:3-1:8
                    text "foo" @1:4-1:7

            """)
    }

    /// A link that forms inside another link's text deactivates the outer `[`, which stays text along with its `](a)`.
    @Test("a nested inline attribute is a link inside literal brackets")
    func nestedInlineFormIsInnerLink() {
        #expect(tree("^[outer ^[inner](b)](a)", Self.plain) == """
            document @1:1-1:24
              paragraph @1:1-1:24
                text "^[outer ^" @1:1-1:10
                link "b" "" @1:10-1:20
                  text "inner" @1:11-1:16
                text "](a)" @1:20-1:24

            """)
    }

    /// A bracket followed by neither an inline link nor a matching definition is text.
    @Test("an attribute opener with no attributes is text")
    func bareBracketIsText() {
        #expect(tree("^[content]", Self.plain) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "^[content]" @1:1-1:11

            """)
    }

    /// A full reference link whose label matches no definition is text.
    @Test("an attribute reference with an undefined label is text")
    func undefinedReferenceIsText() {
        #expect(tree("^[content][unknown]", Self.plain) == """
            document @1:1-1:20
              paragraph @1:1-1:20
                text "^[content][unknown]" @1:1-1:20

            """)
    }

    // MARK: - Definitions

    /// A line that starts with `^` is not a link reference definition, so it stays a paragraph, and the reference after
    /// it matches no definition.
    @Test("an attribute definition is a paragraph")
    func definitionIsParagraph() {
        #expect(tree("^[label]: color: blue\n\n^[content][label]", Self.plain) == """
            document @1:1-3:18
              paragraph @1:1-1:22
                text "^[label]: color: blue" @1:1-1:22
              paragraph @3:1-3:18
                text "^[content][label]" @3:1-3:18

            """)
    }

    /// A line that starts with `^` is not a link reference definition, so a label split across lines stays paragraph
    /// text with a soft break.
    @Test("an attribute definition whose label spans a soft break is a paragraph")
    func crossLineDefinitionIsParagraph() {
        #expect(tree("^[la\nbel]: color: blue\n\n^[content][la bel]", Self.plain) == """
            document @1:1-4:19
              paragraph @1:1-2:18
                text "^[la" @1:1-1:5
                softbreak @-
                text "bel]: color: blue" @2:1-2:18
              paragraph @4:1-4:19
                text "^[content][la bel]" @4:1-4:19

            """)
    }

    /// The link reference definition ends at its destination, and the `^[foo]:` line after it is paragraph text in
    /// which `[foo]` is a shortcut reference to that definition, as is every `[foo]` label that follows.
    @Test("an attribute definition after a link definition is a paragraph that uses the link definition")
    func definitionAfterLinkDefinitionIsParagraph() {
        #expect(tree("[foo]: /url\n^[foo]: color: red\n\n[foo] and ^[content][foo]", Self.plain) == """
            document @1:1-4:26
              paragraph @2:1-2:19
                text "^" @2:1-2:2
                link "/url" "" @2:2-2:7
                  text "foo" @2:3-2:6
                text ": color: red" @2:7-2:19
              paragraph @4:1-4:26
                link "/url" "" @4:1-4:6
                  text "foo" @4:2-4:5
                text " and ^" @4:6-4:12
                link "/url" "" @4:12-4:26
                  text "content" @4:13-4:20

            """)
    }

    // MARK: - Close-bracket handling

    /// `[](` newline `)` is an inline link with an empty destination, because whitespace around a destination may
    /// include a line ending.
    @Test("an empty inline attribute spanning a soft break is an empty link")
    func attributeTextSpanningSoftBreakIsLink() {
        #expect(tree(" ^[](\n)", Self.plain) == """
            document @1:1-2:2
              paragraph @1:2-2:2
                text "^" @1:2-1:3
                link "" "" @1:3-2:2

            """)
    }

    /// `[](x)` is an inline link with empty text.
    @Test("a single-line empty inline attribute is an empty link")
    func singleLineAttributeIsLink() {
        #expect(tree("^[](x)", Self.plain) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "^" @1:1-1:2
                link "x" "" @1:2-1:7

            """)
    }

    /// A paragraph's leading space is not content, and `[](x)` is an inline link with empty text.
    @Test("an indented empty inline attribute is an empty link")
    func indentedAttributeIsLink() {
        #expect(tree(" ^[](x)", Self.plain) == """
            document @1:1-1:8
              paragraph @1:2-1:8
                text "^" @1:2-1:3
                link "x" "" @1:3-1:8

            """)
    }

    /// `[x](/u)` is an inline link.
    @Test("an inline attribute with text is a link with text")
    func attributeWithTextIsLink() {
        #expect(tree("^[x](/u)", Self.plain) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "^" @1:1-1:2
                link "/u" "" @1:2-1:9
                  text "x" @1:3-1:4

            """)
    }

    /// An empty bracket pair is neither link text nor a link label, so every bracket is text.
    @Test("an empty attribute followed by empty brackets keeps every bracket")
    func emptyBracketPairsAreText() {
        #expect(tree("^[][]", Self.plain) == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "^[][]" @1:1-1:6

            """)
    }

    /// An empty bracket pair with nothing after it is text.
    @Test("a lone empty attribute is text")
    func loneEmptyBracketIsText() {
        #expect(tree("^[]", Self.plain) == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "^[]" @1:1-1:4

            """)
    }

    /// An empty bracket pair followed by text is text.
    @Test("an empty attribute followed by text is text")
    func emptyBracketThenTextIsText() {
        #expect(tree("^[]x", Self.plain) == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "^[]x" @1:1-1:5

            """)
    }

    /// `[](x)` is an inline link, and the shortcut reference `[undef]` after it matches no definition, so it stays text.
    @Test("an undefined label after an inline attribute is text after a link")
    func undefinedLabelAfterLinkIsText() {
        #expect(tree("^[](x)[undef]", Self.plain) == """
            document @1:1-1:14
              paragraph @1:1-1:14
                text "^" @1:1-1:2
                link "x" "" @1:2-1:7
                text "[undef]" @1:7-1:14

            """)
    }

    /// `[](x)` is an inline link, and the undefined shortcut reference after it stays text along with what follows.
    @Test("an undefined label and text after an inline attribute are text after a link")
    func undefinedLabelAndTextAfterLinkAreText() {
        #expect(tree("^[](x)[undef]y", Self.plain) == """
            document @1:1-1:15
              paragraph @1:1-1:15
                text "^" @1:1-1:2
                link "x" "" @1:2-1:7
                text "[undef]y" @1:7-1:15

            """)
    }

    /// A line that starts with `^` is not a definition, so `[lbl]` after the inline link `[](x)` matches nothing and
    /// stays text.
    @Test("an attribute definition does not resolve a label after an inline attribute")
    func definitionDoesNotResolveLabelAfterLink() {
        #expect(tree("^[lbl]: color: blue\n\n^[](x)[lbl]", Self.plain) == """
            document @1:1-3:12
              paragraph @1:1-1:20
                text "^[lbl]: color: blue" @1:1-1:20
              paragraph @3:1-3:12
                text "^" @3:1-3:2
                link "x" "" @3:2-3:7
                text "[lbl]" @3:7-3:12

            """)
    }

    // MARK: - Multi-line content

    /// `[a](` newline `b)` is an inline link whose destination follows a line ending inside the block quote.
    @Test("a cross-line inline attribute in a block quote is a link")
    func crossLineAttributeInBlockQuoteIsLink() {
        #expect(tree("> ^[a](\n> b)", Self.plain) == """
            document @1:1-2:5
              block_quote @1:1-2:5
                paragraph @1:3-2:5
                  text "^" @1:3-1:4
                  link "b" "" @1:4-2:5
                    text "a" @1:5-1:6

            """)
    }

    /// `[a](` newline `b)` is an inline link whose destination follows a line ending inside the list item.
    @Test("a cross-line inline attribute in a list item is a link")
    func crossLineAttributeInListItemIsLink() {
        #expect(tree("- ^[a](\n  b)", Self.plain) == """
            document @1:1-2:5
              list bullet '-' tight @1:1-2:5
                item @1:1-2:5
                  paragraph @1:3-2:5
                    text "^" @1:3-1:4
                    link "b" "" @1:4-2:5
                      text "a" @1:5-1:6

            """)
    }

    // MARK: - NUL replacement

    /// A NUL becomes U+FFFD before parsing, so `[x](a` NUL `b)` is an inline link whose destination holds U+FFFD.
    @Test("a NUL in an inline attribute is a U+FFFD in a link destination")
    func nulInInlineAttributeIsLinkDestination() {
        #expect(tree("^[x](a\u{0}b)", Self.plain) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^" @1:1-1:2
                link "a\u{FFFD}b" "" @1:2-1:10
                  text "x" @1:3-1:4

            """)
    }

    /// A NUL becomes U+FFFD before parsing, and a line that starts with `^` is not a definition, so it stays paragraph
    /// text.
    @Test("a NUL in an attribute definition is a U+FFFD in paragraph text")
    func nulInDefinitionIsParagraphText() {
        #expect(tree("^[label]: a\u{0}b\n\n^[content][label]", Self.plain) == """
            document @1:1-3:18
              paragraph @1:1-1:14
                text "^[label]: a\u{FFFD}b" @1:1-1:14
              paragraph @3:1-3:18
                text "^[content][label]" @3:1-3:18

            """)
    }

    // MARK: - Unclosed opener

    /// An unclosed `[` is text, and it joins the `^` before it.
    @Test("a lone attribute opener is text")
    func loneOpenerIsText() {
        #expect(tree("^[", Self.plain) == """
            document @1:1-1:3
              paragraph @1:1-1:3
                text "^[" @1:1-1:3

            """)
    }

    /// An unclosed `[` is text, and it joins the text around it.
    @Test("text starting with an attribute opener is text")
    func textStartingWithOpenerIsText() {
        #expect(tree("^[x", Self.plain) == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "^[x" @1:1-1:4

            """)
    }

    // MARK: - Autolinks

    /// A GFM extended autolink is not recognized while a `[` link bracket is open, so the URL after `^[` stays text.
    @Test("a URL after an unclosed attribute opener is text")
    func urlAfterOpenerIsText() {
        #expect(tree("^[http://t", [.sourcePosition, .gfmAutolink]) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "^[http://t" @1:1-1:11

            """)
    }

    // MARK: - Footnotes

    /// The footnote-shaped `[^[]]` matches no footnote definition, so it is text, and the `[…]()` around it is an
    /// inline link with that text.
    @Test("a footnote-shaped bracket holding `^[` is link text")
    func nestedCaretBracketIsLinkText() {
        #expect(tree("[[^[]]]()", Self.footnotes) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "" "" @1:1-1:10
                  text "[^[]]" @1:2-1:7

            """)
    }

    /// A footnote reference whose label matches no definition is text.
    @Test("a footnote-shaped bracket holding `^[` is text")
    func caretBracketIsText() {
        #expect(tree("[^[]]", Self.footnotes) == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "[^[]]" @1:1-1:6

            """)
    }

    /// A footnote reference whose label matches no definition is text, and so is the text around it.
    @Test("a footnote-shaped bracket holding `^[` keeps the text after it")
    func caretBracketKeepsTrailingText() {
        #expect(tree("x[^[]]y", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "x[^[]]y" @1:1-1:8

            """)
    }

    /// Brackets followed by no link destination and holding an undefined footnote label are text.
    @Test("nested footnote-shaped brackets without a destination are text")
    func nestedCaretBracketWithoutParensIsText() {
        #expect(tree("[[^[]]]", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "[[^[]]]" @1:1-1:8

            """)
    }

    /// `[^[]]()` is an inline link whose text is `^[]`.
    @Test("a footnote-shaped bracket followed by parentheses is a link")
    func caretBracketWithParensIsLink() {
        #expect(tree("[^[]]()", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "" "" @1:1-1:8
                  text "^[]" @1:2-1:5

            """)
    }

    /// The unclosed first `[` is text, and `[^[]]()` after it is an inline link whose text is `^[]`.
    @Test("a footnote-shaped bracket followed by parentheses after a bracket is a link")
    func prefixedCaretBracketWithParensIsLink() {
        #expect(tree("[[^[]]()", Self.footnotes) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "[" @1:1-1:2
                link "" "" @1:2-1:9
                  text "^[]" @1:3-1:6

            """)
    }

    /// Unclosed and unmatched brackets are text.
    @Test("an unclosed footnote-shaped bracket is text")
    func unclosedCaretBracketIsText() {
        #expect(tree("[^[]", Self.footnotes) == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "[^[]" @1:1-1:5

            """)
    }

    /// `[]()` is an inline link with empty text, and the unclosed `[^` before it is text.
    @Test("an empty inline attribute after an unclosed bracket is an empty link")
    func emptyInlineFormAfterBracketIsLink() {
        #expect(tree("[^[]()", Self.footnotes) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "[^" @1:1-1:3
                link "" "" @1:3-1:7

            """)
    }

    /// `[]()` is an inline link, which deactivates the enclosing `[`, so its `]` is text and no footnote forms.
    @Test("an empty inline attribute inside a footnote-shaped bracket is a link between text")
    func emptyInlineFormInsideBracketIsLink() {
        #expect(tree("[^[]()]", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "[^" @1:1-1:3
                link "" "" @1:3-1:7
                text "]" @1:7-1:8

            """)
    }

    /// `[x](y)` is an inline link, which deactivates the enclosing `[`, so its `]` is text and no footnote forms.
    @Test("an inline attribute with text inside a footnote-shaped bracket is a link between text")
    func inlineFormInsideBracketIsLink() {
        #expect(tree("[^[x](y)]", Self.footnotes) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "[^" @1:1-1:3
                link "y" "" @1:3-1:9
                  text "x" @1:4-1:5
                text "]" @1:9-1:10

            """)
    }

    /// A footnote definition's label ends at its first `]`, so `[^[]:` defines the label `[`, which the reference
    /// `[^[]]` (label `[]`) doesn't match; the reference is text and the unreferenced definition is dropped.
    @Test("a footnote-shaped bracket holding `^[` doesn't resolve to a `[` definition")
    func caretBracketDoesNotResolveToBracketDefinition() {
        // A definition label may not hold an unescaped `[`, as a link label may not (spec "Links"), so here
        // `[^[]: note` is paragraph text.
        #expect(tree("[^[]: note\n\n[^[]]", Self.footnotes) == """
            document @1:1-3:6
              paragraph @1:1-1:11
                text "[^[]: note" @1:1-1:11
              paragraph @3:1-3:6
                text "[^[]]" @3:1-3:6

            """)
    }

    /// A footnote reference whose label matches no definition is text.
    @Test("a footnote-shaped bracket holding an empty bracket and text is text")
    func caretBracketWithTextIsText() {
        #expect(tree("[^[]y]", Self.footnotes) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "[^[]y]" @1:1-1:7

            """)
    }

    /// An undefined footnote reference is text, and so is the text around it.
    @Test("text after a footnote-shaped bracket holding `^[` is kept")
    func plainTextAfterCaretBracketIsKept() {
        #expect(tree("x[^[]]y", Self.footnotesAutolink) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "x[^[]]y" @1:1-1:8

            """)
    }

    /// An undefined footnote reference is text, and `f@.f` is no extended email autolink because its domain starts
    /// with a period (spec "Autolinks (extension)").
    @Test("an email-shaped run with an empty first domain segment after a footnote-shaped bracket holding `^[` is text")
    func emailAfterCaretBracketAutolinksWithoutEmptyText() {
        #expect(tree("[^[]]f@.f", Self.footnotesAutolink) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "[^[]]f@.f" @1:1-1:10

            """)
    }

    /// `f@.f` is no extended email autolink because its domain starts with a period (spec "Autolinks (extension)"),
    /// and the undefined footnote reference after it is text.
    @Test("an email-shaped run with an empty first domain segment before a footnote-shaped bracket holding `^[` is text")
    func textAfterEmailAndCaretBracketIsKeptWithoutEmptyText() {
        #expect(tree("f@.f[^[]]y", Self.footnotesAutolink) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "f@.f[^[]]y" @1:1-1:11

            """)
    }
}
