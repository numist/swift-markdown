/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A link label (Links) directly after the `]` that closes an `^[` opener belongs to the inline attribute. When the
/// label names an attribute definition the attribute takes that definition's attributes. Otherwise `^[…]` stays text
/// and the label is dropped; the text's source range spans the dropped label.
@Suite("Inline attributes with a label that names no attribute definition")
struct AttributeUnresolvedLabelTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: [.sourcePosition, .attributes], sourceRanges: true)
    }

    @Test("an unresolved full label is dropped")
    func unresolvedLabel() {
        #expect(tree("^[x][b]") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "^[x]" @1:1-1:8

            """)
    }

    @Test("a resolved full label forms an attribute")
    func resolvedLabel() {
        #expect(tree("^[b]: c\n\n^[x][b]") == """
            document @1:1-3:8
              paragraph @3:1-3:8
                attribute "c" @3:1-3:8
                  text "x" @3:3-3:4

            """)
    }

    @Test("text after an unresolved label joins the attribute's text")
    func textAfterUnresolvedLabel() {
        #expect(tree("^[x][b] y") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^[x] y" @1:1-1:10

            """)
    }

    @Test("text after a resolved label follows the attribute")
    func textAfterResolvedLabel() {
        #expect(tree("^[b]: c\n\n^[x][b] y") == """
            document @1:1-3:10
              paragraph @3:1-3:10
                attribute "c" @3:1-3:8
                  text "x" @3:3-3:4
                text " y" @3:8-3:10

            """)
    }

    /// An inline attribute has no collapsed form, so `[]` names no definition even when the bracket text does.
    @Test("a collapsed label is dropped")
    func collapsedLabel() {
        #expect(tree("^[x][]") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "^[x]" @1:1-1:7

            """)
        #expect(tree("^[x]: c\n\n^[x][]") == """
            document @1:1-3:7
              paragraph @3:1-3:7
                text "^[x]" @3:1-3:7

            """)
    }

    @Test("a blank label is dropped")
    func blankLabel() {
        #expect(tree("^[x][ ]") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "^[x]" @1:1-1:8

            """)
    }

    /// An inline attribute has no shortcut form, so bracket text naming a definition is still text.
    @Test("bracket text with no label after it stays text")
    func noLabel() {
        #expect(tree("^[x]: c\n\n^[x]") == """
            document @1:1-3:5
              paragraph @3:1-3:5
                text "^[x]" @3:1-3:5

            """)
    }

    @Test("bracket text naming a definition forms an attribute with a full label")
    func bracketTextAsFullLabel() {
        #expect(tree("^[x]: c\n\n^[x][x]") == """
            document @1:1-3:8
              paragraph @3:1-3:8
                attribute "c" @3:1-3:8
                  text "x" @3:3-3:4

            """)
    }

    /// A label's content is not parsed as inlines.
    @Test("an unresolved label holding inline syntax is dropped")
    func unresolvedLabelWithInlineSyntax() {
        #expect(tree("^[x][*b*]") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^[x]" @1:1-1:10

            """)
        #expect(tree("^[x][`b`]") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^[x]" @1:1-1:10

            """)
    }

    @Test("a resolved label holding inline syntax forms an attribute")
    func resolvedLabelWithInlineSyntax() {
        #expect(tree("^[*b*]: c\n\n^[x][*b*]") == """
            document @1:1-3:10
              paragraph @3:1-3:10
                attribute "c" @3:1-3:10
                  text "x" @3:3-3:4

            """)
    }

    @Test("an unresolved label holding an escaped bracket is dropped")
    func unresolvedLabelWithEscapedBracket() {
        #expect(tree(#"^[x][b\]]"#) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^[x]" @1:1-1:10

            """)
    }

    @Test("an escaped bracket after the attribute's text starts no label")
    func escapedBracketAfterText() {
        #expect(tree(#"^[x]\[b]"#) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "^[x][b]" @1:1-1:9

            """)
    }

    /// A link label may span a line ending, so the dropped label takes the line ending with it.
    @Test("an unresolved label spanning a line ending is dropped")
    func unresolvedLabelSpanningLineEnding() {
        #expect(tree("^[x][b\nc] y") == """
            document @1:1-2:5
              paragraph @1:1-2:5
                text "^[x] y" @1:1-2:5

            """)
    }

    @Test("a resolved label spanning a line ending forms an attribute")
    func resolvedLabelSpanningLineEnding() {
        #expect(tree("^[b c]: d\n\n^[x][b\nc] y") == """
            document @1:1-4:5
              paragraph @3:1-4:5
                attribute "d" @3:1-4:3
                  text "x" @3:3-3:4
                text " y" @4:3-4:5

            """)
    }

    @Test("a second label after an unresolved one is parsed as text")
    func labelAfterUnresolvedLabel() {
        #expect(tree("^[x][b][c]\n\n^[c]: d") == """
            document @1:1-3:8
              paragraph @1:1-1:11
                text "^[x][c]" @1:1-1:11

            """)
        #expect(tree("^[x][b][c]\n\n[c]: /u") == """
            document @1:1-3:8
              paragraph @1:1-1:11
                text "^[x]" @1:1-1:8
                link "/u" "" @1:8-1:11
                  text "c" @1:9-1:10

            """)
    }

    @Test("a label after a resolved one is parsed as text")
    func labelAfterResolvedLabel() {
        #expect(tree("^[x][c][b]\n\n^[c]: d") == """
            document @1:1-3:8
              paragraph @1:1-1:11
                attribute "d" @1:1-1:8
                  text "x" @1:3-1:4
                text "[b]" @1:8-1:11

            """)
    }

    @Test("an attribute after an unresolved label forms")
    func attributeAfterUnresolvedLabel() {
        #expect(tree("^[x][b]^[y][c]\n\n^[c]: d") == """
            document @1:1-3:8
              paragraph @1:1-1:15
                text "^[x]" @1:1-1:8
                attribute "d" @1:8-1:15
                  text "y" @1:10-1:11

            """)
    }

    /// Link definitions and attribute definitions are separate, so a label naming only a link definition names no
    /// attribute definition.
    @Test("a label naming only a link definition is dropped")
    func labelNamingLinkDefinition() {
        #expect(tree("[b]: /u\n\n^[x][b]") == """
            document @1:1-3:8
              paragraph @3:1-3:8
                text "^[x]" @3:1-3:8

            """)
        #expect(tree("[b]: /u\n\n[x][b]") == """
            document @1:1-3:7
              paragraph @3:1-3:7
                link "/u" "" @3:1-3:7
                  text "x" @3:2-3:3

            """)
    }

    @Test("an unresolved label is dropped before an inline link can follow it")
    func inlineLinkTailAfterUnresolvedLabel() {
        #expect(tree("^[x][b](c)") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "^[x](c)" @1:1-1:11

            """)
    }

    @Test("an empty attribute's unresolved label is dropped")
    func emptyTextUnresolvedLabel() {
        #expect(tree("^[][b]") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "^[]" @1:1-1:7

            """)
    }

    /// The `]` that closes the attribute's text is the text node's content, and its source range runs on to the end of
    /// the dropped label.
    @Test("the closing bracket's text spans the dropped label")
    func closingBracketTextSpansLabel() {
        #expect(tree("^[*x*][b]") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^[" @1:1-1:3
                emph @1:3-1:6
                  text "x" @1:4-1:5
                text "]" @1:6-1:10

            """)
    }

    @Test("an unresolved label inside link text is dropped")
    func unresolvedLabelInLinkText() {
        #expect(tree("[a ^[x][b] c](/u)") == """
            document @1:1-1:18
              paragraph @1:1-1:18
                link "/u" "" @1:1-1:18
                  text "a ^[x] c" @1:2-1:13

            """)
    }

    @Test("a resolved label inside link text forms an attribute")
    func resolvedLabelInLinkText() {
        #expect(tree("^[b]: d\n\n[a ^[x][b] c](/u)") == """
            document @1:1-3:18
              paragraph @3:1-3:18
                link "/u" "" @3:1-3:18
                  text "a " @3:2-3:4
                  attribute "d" @3:4-3:11
                    text "x" @3:6-3:7
                  text " c" @3:11-3:13

            """)
    }

    @Test("an unresolved label after a link in the attribute's text is dropped")
    func unresolvedLabelAfterLinkInText() {
        #expect(tree("^[[a](/u)][b]") == """
            document @1:1-1:14
              paragraph @1:1-1:14
                text "^[" @1:1-1:3
                link "/u" "" @1:3-1:10
                  text "a" @1:4-1:5
                text "]" @1:10-1:14

            """)
    }

    @Test("a resolved label after a link in the attribute's text forms an attribute")
    func resolvedLabelAfterLinkInText() {
        #expect(tree("^[b]: d\n\n^[[a](/u)][b]") == """
            document @1:1-3:14
              paragraph @3:1-3:14
                attribute "d" @3:1-3:14
                  link "/u" "" @3:3-3:10
                    text "a" @3:4-3:5

            """)
    }

    @Test("an unresolved label in a block quote is dropped")
    func unresolvedLabelInBlockQuote() {
        #expect(tree("> ^[x][b] y") == """
            document @1:1-1:12
              block_quote @1:1-1:12
                paragraph @1:3-1:12
                  text "^[x] y" @1:3-1:12

            """)
    }

    @Test("a resolved label in a block quote forms an attribute")
    func resolvedLabelInBlockQuote() {
        #expect(tree("^[b]: d\n\n> ^[x][b] y") == """
            document @1:1-3:12
              block_quote @3:1-3:12
                paragraph @3:3-3:12
                  attribute "d" @3:3-3:10
                    text "x" @3:5-3:6
                  text " y" @3:10-3:12

            """)
    }

    @Test("an unresolved label in a list item is dropped")
    func unresolvedLabelInListItem() {
        #expect(tree("- ^[x][b]") == """
            document @1:1-1:10
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
                  paragraph @1:3-1:10
                    text "^[x]" @1:3-1:10

            """)
    }

    @Test("a resolved label in a list item forms an attribute")
    func resolvedLabelInListItem() {
        #expect(tree("^[b]: d\n\n- ^[x][b]") == """
            document @1:1-3:10
              list bullet '-' tight @3:1-3:10
                item @3:1-3:10
                  paragraph @3:3-3:10
                    attribute "d" @3:3-3:10
                      text "x" @3:5-3:6

            """)
    }

    @Test("an unresolved label in a table cell is dropped")
    func unresolvedLabelInTableCell() {
        #expect(TreeDump.dump("| a |\n|---|\n| ^[x][b] |", options: [.sourcePosition, .attributes, .tables], sourceRanges: true) == """
            document @1:1-3:12
              table @1:1-3:12
                table_header @1:1-1:6
                  table_cell align=none colspan=1 rowspan=1 @1:2-1:5
                    text "a" @1:3-1:4
                table_row @3:1-3:12
                  table_cell align=none colspan=1 rowspan=1 @3:2-3:11
                    text "^[x]" @3:3-3:10

            """)
    }

    @Test("a resolved label in a table cell forms an attribute")
    func resolvedLabelInTableCell() {
        #expect(TreeDump.dump("^[b]: d\n\n| a |\n|---|\n| ^[x][b] |", options: [.sourcePosition, .attributes, .tables], sourceRanges: true) == """
            document @1:1-5:12
              table @3:1-5:12
                table_header @3:1-3:6
                  table_cell align=none colspan=1 rowspan=1 @3:2-3:5
                    text "a" @3:3-3:4
                table_row @5:1-5:12
                  table_cell align=none colspan=1 rowspan=1 @5:2-5:11
                    attribute "d" @5:3-5:10
                      text "x" @5:5-5:6

            """)
    }

    /// Labels match under the Unicode case fold (Links): `ß` folds to `ss`, and dotless `ı` folds to itself.
    @Test("a label matching a definition under the case fold forms an attribute")
    func labelMatchingUnderCaseFold() {
        #expect(tree("^[ß]: c\n\n^[x][SS]") == """
            document @1:1-3:9
              paragraph @3:1-3:9
                attribute "c" @3:1-3:9
                  text "x" @3:3-3:4

            """)
    }

    @Test("a label differing from a definition under the case fold is dropped")
    func labelDifferingUnderCaseFold() {
        #expect(tree("^[ı]: c\n\n^[x][I]") == """
            document @1:1-3:8
              paragraph @3:1-3:8
                text "^[x]" @3:1-3:8

            """)
    }

    @Test("with attributes off, the bracket text and label form a link or stay text")
    func attributesOff() {
        #expect(TreeDump.dump("[b]: /u\n\n^[x][b]", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:8
              paragraph @3:1-3:8
                text "^" @3:1-3:2
                link "/u" "" @3:2-3:8
                  text "x" @3:3-3:4

            """)
        #expect(TreeDump.dump("^[x][b]", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "^[x][b]" @1:1-1:8

            """)
    }
}
