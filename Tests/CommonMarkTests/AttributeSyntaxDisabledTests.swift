/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Attribute syntax without the attributes option")
struct AttributeSyntaxDisabledTests {

    private static let plain: MarkdownDocument.ParseOptions = [.sourcePosition]
    private static let footnotes: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]
    private static let footnotesAutolink: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes, .gfmAutolink]

    private func tree(_ source: String, _ options: MarkdownDocument.ParseOptions) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    @Test("an inline attribute whose attributes contain a space is text")
    func inlineFormIsText() {
        #expect(tree("^[hello](color: red)", Self.plain) == """
            document @1:1-1:21
              paragraph @1:1-1:21
                text "^[hello](color: red)" @1:1-1:21

            """)
    }

    @Test("an empty inline attribute is text followed by an empty link")
    func emptyInlineFormIsLink() {
        #expect(tree("^[](attr)", Self.plain) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^" @1:1-1:2
                link "attr" "" @1:2-1:10

            """)
    }

    @Test("attributes with whitespace between them are text")
    func attributesWithWhitespaceAreText() {
        #expect(tree("^[x](color: red, weight: bold)", Self.plain) == """
            document @1:1-1:31
              paragraph @1:1-1:31
                text "^[x](color: red, weight: bold)" @1:1-1:31

            """)
    }

    // The destination ends at the space, where its `(` is still unbalanced (Links).
    @Test("attributes with balanced parentheses and spaces are text")
    func attributesWithParensAreText() {
        #expect(tree("^[x](rgb(255, \"t\"))", Self.plain) == """
            document @1:1-1:20
              paragraph @1:1-1:20
                text "^[x](rgb(255, \\"t\\"))" @1:1-1:20

            """)
    }

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

    @Test("an attribute opener with no attributes is text")
    func bareBracketIsText() {
        #expect(tree("^[content]", Self.plain) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "^[content]" @1:1-1:11

            """)
    }

    @Test("an attribute reference with an undefined label is text")
    func undefinedReferenceIsText() {
        #expect(tree("^[content][unknown]", Self.plain) == """
            document @1:1-1:20
              paragraph @1:1-1:20
                text "^[content][unknown]" @1:1-1:20

            """)
    }

    @Test("an attribute definition is a paragraph")
    func definitionIsParagraph() {
        #expect(tree("^[label]: blue\n\n^[content][label]", Self.plain) == """
            document @1:1-3:18
              paragraph @1:1-1:15
                text "^[label]: blue" @1:1-1:15
              paragraph @3:1-3:18
                text "^[content][label]" @3:1-3:18

            """)
    }

    @Test("an attribute definition whose label spans a soft line break is a paragraph")
    func crossLineDefinitionIsParagraph() {
        #expect(tree("^[la\nbel]: blue\n\n^[content][la bel]", Self.plain) == """
            document @1:1-4:19
              paragraph @1:1-2:11
                text "^[la" @1:1-1:5
                softbreak @-
                text "bel]: blue" @2:1-2:11
              paragraph @4:1-4:19
                text "^[content][la bel]" @4:1-4:19

            """)
    }

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

    @Test("an empty inline attribute whose parentheses span a line ending is an empty link")
    func attributeParenthesesSpanningLineEndingIsLink() {
        #expect(tree(" ^[](\n)", Self.plain) == """
            document @1:1-2:2
              paragraph @1:2-2:2
                text "^" @1:2-1:3
                link "" "" @1:3-2:2

            """)
    }

    @Test("a single-line empty inline attribute is an empty link")
    func singleLineAttributeIsLink() {
        #expect(tree("^[](x)", Self.plain) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "^" @1:1-1:2
                link "x" "" @1:2-1:7

            """)
    }

    @Test("an indented empty inline attribute is an empty link")
    func indentedAttributeIsLink() {
        #expect(tree(" ^[](x)", Self.plain) == """
            document @1:1-1:8
              paragraph @1:2-1:8
                text "^" @1:2-1:3
                link "x" "" @1:3-1:8

            """)
    }

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

    // A link label holds at least one character other than whitespace (Links), so `[]: /u` defines nothing and `[][]`
    // is no reference link.
    @Test("an empty attribute followed by empty brackets keeps every bracket")
    func emptyBracketPairsAreText() {
        #expect(tree("[]: /u\n\n^[][]", Self.plain) == """
            document @1:1-3:6
              paragraph @1:1-1:7
                text "[]: /u" @1:1-1:7
              paragraph @3:1-3:6
                text "^[][]" @3:1-3:6

            """)
    }

    @Test("a lone empty attribute is text")
    func loneEmptyBracketIsText() {
        #expect(tree("^[]", Self.plain) == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "^[]" @1:1-1:4

            """)
    }

    @Test("an empty attribute followed by text is text")
    func emptyBracketThenTextIsText() {
        #expect(tree("^[]x", Self.plain) == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "^[]x" @1:1-1:5

            """)
    }

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

    @Test("a lone attribute opener is text")
    func loneOpenerIsText() {
        #expect(tree("^[", Self.plain) == """
            document @1:1-1:3
              paragraph @1:1-1:3
                text "^[" @1:1-1:3

            """)
    }

    @Test("text starting with an attribute opener is text")
    func textStartingWithOpenerIsText() {
        #expect(tree("^[x", Self.plain) == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "^[x" @1:1-1:4

            """)
    }

    // An unclosed `[` suppresses an extended url or www autolink after it.
    @Test("a URL after an unclosed attribute opener is text")
    func urlAfterOpenerIsText() {
        #expect(tree("^[http://t", [.sourcePosition, .gfmAutolink]) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "^[http://t" @1:1-1:11

            """)
    }

    @Test("a footnote-shaped bracket holding `^[` is link text")
    func nestedCaretBracketIsLinkText() {
        #expect(tree("[[^[]]]()", Self.footnotes) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                link "" "" @1:1-1:10
                  text "[^[]]" @1:2-1:7

            """)
    }

    @Test("a footnote-shaped bracket holding `^[` is text")
    func caretBracketIsText() {
        #expect(tree("[^[]]", Self.footnotes) == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "[^[]]" @1:1-1:6

            """)
    }

    @Test("a footnote-shaped bracket holding `^[` keeps the text after it")
    func caretBracketKeepsTrailingText() {
        #expect(tree("x[^[]]y", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "x[^[]]y" @1:1-1:8

            """)
    }

    @Test("nested footnote-shaped brackets without a destination are text")
    func nestedCaretBracketWithoutParensIsText() {
        #expect(tree("[[^[]]]", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "[[^[]]]" @1:1-1:8

            """)
    }

    @Test("a footnote-shaped bracket followed by parentheses is a link")
    func caretBracketWithParensIsLink() {
        #expect(tree("[^[]]()", Self.footnotes) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                link "" "" @1:1-1:8
                  text "^[]" @1:2-1:5

            """)
    }

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

    @Test("an unclosed footnote-shaped bracket is text")
    func unclosedCaretBracketIsText() {
        #expect(tree("[^[]", Self.footnotes) == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "[^[]" @1:1-1:5

            """)
    }

    @Test("an empty inline attribute after an unclosed bracket is an empty link")
    func emptyInlineFormAfterBracketIsLink() {
        #expect(tree("[^[]()", Self.footnotes) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "[^" @1:1-1:3
                link "" "" @1:3-1:7

            """)
    }

    @Test("an empty inline attribute inside a footnote-shaped bracket is a link between text")
    func emptyInlineFormInsideBracketIsLink() {
        #expect(tree("[^[]()](/u)", Self.footnotes) == """
            document @1:1-1:12
              paragraph @1:1-1:12
                text "[^" @1:1-1:3
                link "" "" @1:3-1:7
                text "](/u)" @1:7-1:12

            """)
    }

    @Test("an inline attribute with text inside a footnote-shaped bracket is a link between text")
    func inlineFormInsideBracketIsLink() {
        #expect(tree("[^[x](y)](/u)", Self.footnotes) == """
            document @1:1-1:14
              paragraph @1:1-1:14
                text "[^" @1:1-1:3
                link "y" "" @1:3-1:9
                  text "x" @1:4-1:5
                text "](/u)" @1:9-1:14

            """)
    }

    // A footnote label, like a link label (Links), may not contain an unescaped `[`.
    @Test("a footnote definition whose label holds `[` is paragraph text")
    func footnoteDefinitionLabelWithBracketIsParagraph() {
        #expect(tree("[^[]: note\n\n[^[]]", Self.footnotes) == """
            document @1:1-3:6
              paragraph @1:1-1:11
                text "[^[]: note" @1:1-1:11
              paragraph @3:1-3:6
                text "[^[]]" @3:1-3:6

            """)
    }

    @Test("a footnote-shaped bracket holding an empty bracket and text is text")
    func caretBracketWithTextIsText() {
        #expect(tree("[^[]y]", Self.footnotes) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "[^[]y]" @1:1-1:7

            """)
    }

    @Test("an email with an empty first domain segment after a footnote-shaped bracket holding `^[` autolinks")
    func emailWithEmptyDomainSegmentAfterCaretBracketAutolinks() {
        #expect(tree("[^[]]f@.f", Self.footnotesAutolink) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "[^[]]" @1:1-1:6
                link "mailto:f@.f" "" @1:6-1:10
                  text "f@.f" @1:6-1:10

            """)
    }

    @Test("an email with an empty first domain segment before a footnote-shaped bracket holding `^[` autolinks")
    func emailWithEmptyDomainSegmentBeforeCaretBracketAutolinks() {
        #expect(tree("f@.f[^[]]y", Self.footnotesAutolink) == """
            document @1:1-1:11
              paragraph @1:1-1:11
                link "mailto:f@.f" "" @1:1-1:5
                  text "f@.f" @1:1-1:5
                text "[^[]]y" @1:5-1:11

            """)
    }
}
