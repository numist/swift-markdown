/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Blank lines in a long chain of open list items or footnote definitions.
///
/// A blank line continues a footnote definition and a list item that holds a block, and closes a list item without a
/// block (List items) and a block quote (Block quotes), so a run of blank lines keeps the chain open down to the first
/// block it closes. The chains end in a block quote, an empty list item, a list item holding a paragraph and a
/// paragraph. The blank lines are empty, hold spaces, or hold tabs that continue some of the footnote definitions, and
/// several follow each other, so later ones meet the same open blocks.
@Suite("Blank lines in a long chain of open containers")
struct BlankLinesInOpenContainerChainTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let expected: String

        init(_ name: String, _ source: String, _ expected: String) {
            self.name = name
            self.source = source
            self.expected = expected
        }

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            "block quote in the innermost of ten footnote definitions",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:>x\n\n\ny\n",
            """
            document @1:1-6:2
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @6:1-6:2
                text "y" @6:1-6:2
              footnote_definition "a" @3:46-5:1
                block_quote @3:51-3:53
                  paragraph @3:52-3:53
                    text "x" @3:52-3:53

            """
        ),
        Case(
            "empty list item in the innermost of ten footnote definitions",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:-\n\n\nx\n",
            """
            document @1:1-6:2
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @6:1-6:2
                text "x" @6:1-6:2
              footnote_definition "a" @3:46-5:1
                list bullet '-' tight @3:51-5:1
                  item @3:51-3:52

            """
        ),
        Case(
            "list item holding a paragraph in the innermost of ten footnote definitions",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:- a\n\n\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:46-5:1
                list bullet '-' tight @3:51-5:1
                  item @3:51-5:1
                    paragraph @3:53-3:54
                      text "a" @3:53-3:54

            """
        ),
        Case(
            "twelve footnote definitions, blank lines of tabs that continue some of them",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:x\n\n\t\n\t\t\n\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:56-7:1
                paragraph @3:61-3:62
                  text "x" @3:61-3:62

            """
        ),
        Case(
            "twelve footnote definitions, three empty lines",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:x\n\n\n\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:56-6:1
                paragraph @3:61-3:62
                  text "x" @3:61-3:62

            """
        ),
        Case(
            "twelve footnote definitions, empty lines around a line of spaces that continues the outermost",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:x\n\n\n    \n\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:56-7:1
                paragraph @3:61-3:62
                  text "x" @3:61-3:62

            """
        ),
        Case(
            "ten nested list items holding a paragraph",
            "- - - - - - - - - - x\n\n\ny\n",
            """
            document @1:1-4:2
              list bullet '-' tight @1:1-3:1
                item @1:1-3:1
                  list bullet '-' tight @1:3-3:1
                    item @1:3-3:1
                      list bullet '-' tight @1:5-3:1
                        item @1:5-3:1
                          list bullet '-' tight @1:7-3:1
                            item @1:7-3:1
                              list bullet '-' tight @1:9-3:1
                                item @1:9-3:1
                                  list bullet '-' tight @1:11-3:1
                                    item @1:11-3:1
                                      list bullet '-' tight @1:13-3:1
                                        item @1:13-3:1
                                          list bullet '-' tight @1:15-3:1
                                            item @1:15-3:1
                                              list bullet '-' tight @1:17-3:1
                                                item @1:17-3:1
                                                  list bullet '-' tight @1:19-3:1
                                                    item @1:19-3:1
                                                      paragraph @1:21-1:22
                                                        text "x" @1:21-1:22
              paragraph @4:1-4:2
                text "y" @4:1-4:2

            """
        ),
        Case(
            "eleven nested list items, the innermost without a block",
            "- + - + - + - + - + -\n\n\nx\n",
            """
            document @1:1-4:2
              list bullet '-' tight @1:1-3:1
                item @1:1-3:1
                  list bullet '+' tight @1:3-3:1
                    item @1:3-3:1
                      list bullet '-' tight @1:5-3:1
                        item @1:5-3:1
                          list bullet '+' tight @1:7-3:1
                            item @1:7-3:1
                              list bullet '-' tight @1:9-3:1
                                item @1:9-3:1
                                  list bullet '+' tight @1:11-3:1
                                    item @1:11-3:1
                                      list bullet '-' tight @1:13-3:1
                                        item @1:13-3:1
                                          list bullet '+' tight @1:15-3:1
                                            item @1:15-3:1
                                              list bullet '-' tight @1:17-3:1
                                                item @1:17-3:1
                                                  list bullet '+' tight @1:19-3:1
                                                    item @1:19-3:1
                                                      list bullet '-' tight @1:21-3:1
                                                        item @1:21-1:22
              paragraph @4:1-4:2
                text "x" @4:1-4:2

            """
        ),
        Case(
            "eleven nested list items, the innermost without a block, a line of spaces",
            "- + - + - + - + - + -\n  \n\nx\n",
            """
            document @1:1-4:2
              list bullet '-' tight @1:1-3:1
                item @1:1-3:1
                  list bullet '+' tight @1:3-3:1
                    item @1:3-3:1
                      list bullet '-' tight @1:5-3:1
                        item @1:5-3:1
                          list bullet '+' tight @1:7-3:1
                            item @1:7-3:1
                              list bullet '-' tight @1:9-3:1
                                item @1:9-3:1
                                  list bullet '+' tight @1:11-3:1
                                    item @1:11-3:1
                                      list bullet '-' tight @1:13-3:1
                                        item @1:13-3:1
                                          list bullet '+' tight @1:15-3:1
                                            item @1:15-3:1
                                              list bullet '-' tight @1:17-3:1
                                                item @1:17-3:1
                                                  list bullet '+' tight @1:19-3:1
                                                    item @1:19-3:1
                                                      list bullet '-' tight @1:21-3:1
                                                        item @1:21-1:22
              paragraph @4:1-4:2
                text "x" @4:1-4:2

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
