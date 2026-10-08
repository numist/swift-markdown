/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The opening line of a footnote definition with nothing after its label is not a blank line, so a list item holding
/// such a definition leaves its list tight when no blank line separates its items or blocks (Lists). An unreferenced
/// definition does not appear in the tree.
@Suite("List tightness around a footnote definition with an empty opening line")
struct FootnoteDefinitionEmptyOpeningLineTightnessTests {

    @Test("a definition with nothing after its label, followed by the next item")
    func emptyOpeningLineBeforeNextItem() {
        #expect(TreeDump.dump("- [^b]:\n- c\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("a definition with only a space after its label, followed by the next item")
    func whitespaceOpeningLineBeforeNextItem() {
        #expect(TreeDump.dump("- [^b]: \n- c\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("a definition with an empty opening line, followed by a paragraph of the same item")
    func emptyOpeningLineThenItemParagraph() {
        #expect(TreeDump.dump("- [^b]:\n  x\n- c\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("a definition with an empty opening line, followed by a line indented less than the definition's continuation lines")
    func emptyOpeningLineThenDeeperParagraph() {
        #expect(TreeDump.dump("- [^b]:\n    x\n- c\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("an ordered list in the same shape")
    func orderedList() {
        #expect(TreeDump.dump("1. [^b]:\n2. c\n", options: [.footnotes]) == """
            document
              list ordered start=1 delim=period tight
                item
                item
                  paragraph
                    text "c"

            """)
    }

    @Test("a definition with an empty opening line as the only item")
    func onlyItem() {
        #expect(TreeDump.dump("- [^b]:\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test("a definition with an empty opening line in the last item")
    func lastItem() {
        #expect(TreeDump.dump("- a\n- [^b]:\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                item

            """)
    }

    @Test("a definition with an empty opening line before a list")
    func outsideList() {
        #expect(TreeDump.dump("[^b]:\n\n- a\n- c\n", options: [.footnotes]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                item
                  paragraph
                    text "c"

            """)
    }
}
