/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Containers opened on a line before a list marker")
struct ContainersOpenedOnLineLimitTests {

    private func limits(_ maxContainers: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxContainersOpenedOnLineBeforeListMarker = maxContainers
        return limits
    }

    @Test("a bullet list marker opens an item after the limit's count of items but not after one more")
    func bulletBoundary() {
        #expect(TreeDump.dump("+ + + + x", options: [], limits: limits(3)) == """
            document
              list bullet '+' tight
                item
                  list bullet '+' tight
                    item
                      list bullet '+' tight
                        item
                          list bullet '+' tight
                            item
                              paragraph
                                text "x"

            """)
        #expect(TreeDump.dump("+ + + + + x", options: [], limits: limits(3)) == """
            document
              list bullet '+' tight
                item
                  list bullet '+' tight
                    item
                      list bullet '+' tight
                        item
                          list bullet '+' tight
                            item
                              paragraph
                                text "+ x"

            """)
    }

    @Test("an ordered list marker opens an item after the limit's count of items but not after one more")
    func orderedBoundary() {
        #expect(TreeDump.dump("1. 1. 1. 1. x", options: [], limits: limits(3)) == """
            document
              list ordered start=1 delim=period tight
                item
                  list ordered start=1 delim=period tight
                    item
                      list ordered start=1 delim=period tight
                        item
                          list ordered start=1 delim=period tight
                            item
                              paragraph
                                text "x"

            """)
        #expect(TreeDump.dump("1. 1. 1. 1. 1. x", options: [], limits: limits(3)) == """
            document
              list ordered start=1 delim=period tight
                item
                  list ordered start=1 delim=period tight
                    item
                      list ordered start=1 delim=period tight
                        item
                          list ordered start=1 delim=period tight
                            item
                              paragraph
                                text "1. x"

            """)
    }

    @Test("block quotes opened on the line count toward the limit")
    func blockQuotesCount() {
        #expect(TreeDump.dump("> > > - x", options: [], limits: limits(3)) == """
            document
              block_quote
                block_quote
                  block_quote
                    list bullet '-' tight
                      item
                        paragraph
                          text "x"

            """)
        #expect(TreeDump.dump("> > > > - x", options: [], limits: limits(3)) == """
            document
              block_quote
                block_quote
                  block_quote
                    block_quote
                      paragraph
                        text "- x"

            """)
    }

    @Test("a block quote opens past the limit")
    func blockQuotesOpenPastLimit() {
        #expect(TreeDump.dump("> > > > > x", options: [], limits: limits(3)) == """
            document
              block_quote
                block_quote
                  block_quote
                    block_quote
                      block_quote
                        paragraph
                          text "x"

            """)
        #expect(TreeDump.dump("+ + + > > x", options: [], limits: limits(3)) == """
            document
              list bullet '+' tight
                item
                  list bullet '+' tight
                    item
                      list bullet '+' tight
                        item
                          block_quote
                            block_quote
                              paragraph
                                text "x"

            """)
    }

    @Test("a thematic break forms past the limit")
    func thematicBreakPastLimit() {
        #expect(TreeDump.dump("> > > > - - -", options: [], limits: limits(3)) == """
            document
              block_quote
                block_quote
                  block_quote
                    block_quote
                      thematic_break

            """)
    }

    @Test("containers a line continues don't count toward the limit")
    func continuedContainersDoNotCount() {
        #expect(TreeDump.dump("> > > > x\n> > > > - y", options: [], limits: limits(3)) == """
            document
              block_quote
                block_quote
                  block_quote
                    block_quote
                      paragraph
                        text "x"
                      list bullet '-' tight
                        item
                          paragraph
                            text "y"

            """)
        #expect(TreeDump.dump("+ + + + x\n        + + + + y", options: [], limits: limits(3)) == """
            document
              list bullet '+' tight
                item
                  list bullet '+' tight
                    item
                      list bullet '+' tight
                        item
                          list bullet '+' tight
                            item
                              paragraph
                                text "x"
                              list bullet '+' tight
                                item
                                  list bullet '+' tight
                                    item
                                      list bullet '+' tight
                                        item
                                          list bullet '+' tight
                                            item
                                              paragraph
                                                text "y"

            """)
    }

    @Test("a marker refused after block quotes that interrupt a paragraph is paragraph text")
    func refusedAfterInterruptingQuotes() {
        #expect(TreeDump.dump("> a\n> > > > > - y", options: [], limits: limits(3)) == """
            document
              block_quote
                paragraph
                  text "a"
                block_quote
                  block_quote
                    block_quote
                      block_quote
                        paragraph
                          text "- y"

            """)
    }

    @Test("a footnote definition opens after the limit's count of containers but not after one more")
    func footnoteDefinitionBoundary() {
        #expect(TreeDump.dump("a[^1]\n\n> > > [^1]: x", options: [.footnotes], limits: limits(3)) == """
            document
              paragraph
                text "a"
                footnote_reference "1"
              block_quote
                block_quote
                  block_quote
              footnote_definition "1"
                paragraph
                  text "x"

            """)
        #expect(TreeDump.dump("a[^1]\n\n> > > > [^1]: x", options: [.footnotes], limits: limits(3)) == """
            document
              paragraph
                text "a"
                link "x" ""
                  text "^1"
              block_quote
                block_quote
                  block_quote
                    block_quote

            """)
    }

    @Test("a footnote definition opened on the line counts toward the limit")
    func footnoteDefinitionCounts() {
        #expect(TreeDump.dump("a[^1]\n\n> > [^1]: - y", options: [.footnotes], limits: limits(3)) == """
            document
              paragraph
                text "a"
                footnote_reference "1"
              block_quote
                block_quote
              footnote_definition "1"
                list bullet '-' tight
                  item
                    paragraph
                      text "y"

            """)
        #expect(TreeDump.dump("a[^1]\n\n> > > [^1]: - y", options: [.footnotes], limits: limits(3)) == """
            document
              paragraph
                text "a"
                footnote_reference "1"
              block_quote
                block_quote
                  block_quote
              footnote_definition "1"
                paragraph
                  text "- y"

            """)
        #expect(TreeDump.dump("a[^1] [^2]\n\n> > > [^1]: [^2]: x", options: [.footnotes], limits: limits(3)) == """
            document
              paragraph
                text "a"
                footnote_reference "1"
                text " "
                link "x" ""
                  text "^2"
              block_quote
                block_quote
                  block_quote
              footnote_definition "1"

            """)
    }

    @Test("a limit of zero recognizes a list marker or a footnote definition only where the line has opened no container")
    func limitOfZero() {
        #expect(TreeDump.dump("- x", options: [], limits: limits(0)) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "x"

            """)
        #expect(TreeDump.dump("a\n- x", options: [], limits: limits(0)) == """
            document
              paragraph
                text "a"
              list bullet '-' tight
                item
                  paragraph
                    text "x"

            """)
        #expect(TreeDump.dump("- - x", options: [], limits: limits(0)) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "- x"

            """)
        #expect(TreeDump.dump("> - x", options: [], limits: limits(0)) == """
            document
              block_quote
                paragraph
                  text "- x"

            """)
        #expect(TreeDump.dump("a[^1]\n\n[^1]: x", options: [.footnotes], limits: limits(0)) == """
            document
              paragraph
                text "a"
                footnote_reference "1"
              footnote_definition "1"
                paragraph
                  text "x"

            """)
        #expect(TreeDump.dump("a[^1]\n\n> [^1]: x", options: [.footnotes], limits: limits(0)) == """
            document
              paragraph
                text "a"
                link "x" ""
                  text "^1"
              block_quote

            """)
    }

    @Test("a negative limit recognizes no list marker or footnote definition", arguments: [-1, Int.min])
    func negativeLimit(_ maxContainers: Int) {
        #expect(TreeDump.dump("- x", options: [], limits: limits(maxContainers)) == """
            document
              paragraph
                text "- x"

            """)
        #expect(TreeDump.dump("a\n- x", options: [], limits: limits(maxContainers)) == """
            document
              paragraph
                text "a"
                softbreak
                text "- x"

            """)
        #expect(TreeDump.dump("> - x", options: [], limits: limits(maxContainers)) == """
            document
              block_quote
                paragraph
                  text "- x"

            """)
        #expect(TreeDump.dump("a[^1]\n\n[^1]: x", options: [.footnotes], limits: limits(maxContainers)) == """
            document
              paragraph
                text "a"
                link "x" ""
                  text "^1"

            """)
        #expect(TreeDump.dump("a[^1]\n\nb\n[^1]: x", options: [.footnotes], limits: limits(maxContainers)) == """
            document
              paragraph
                text "a[^1]"
              paragraph
                text "b"
                softbreak
                text "[^1]: x"

            """)
    }

    @Test("the default limits open a list item and a footnote definition after any number of containers on the line")
    func defaultLimits() {
        #expect(TreeDump.dump("+ + + + x", options: []) == """
            document
              list bullet '+' tight
                item
                  list bullet '+' tight
                    item
                      list bullet '+' tight
                        item
                          list bullet '+' tight
                            item
                              paragraph
                                text "x"

            """)
        #expect(TreeDump.dump("a[^1]\n\n> > > [^1]: x", options: [.footnotes]) == """
            document
              paragraph
                text "a"
                footnote_reference "1"
              block_quote
                block_quote
                  block_quote
              footnote_definition "1"
                paragraph
                  text "x"

            """)
    }
}
