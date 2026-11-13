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
/// block it closes.
@Suite("Blank lines in a long chain of open containers")
struct BlankLinesInOpenContainerChainTests {

    static let cases: [TreeDumpCase] = [
        TreeDumpCase(
            "block quote in the innermost of ten footnote definitions",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:>x\n\n\n" + String(repeating: " ", count: 40) + ">y\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:46-6:43
                block_quote @3:51-3:53
                  paragraph @3:52-3:53
                    text "x" @3:52-3:53
                block_quote @6:41-6:43
                  paragraph @6:42-6:43
                    text "y" @6:42-6:43

            """
        ),
        TreeDumpCase(
            "empty list item in the innermost of ten footnote definitions",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:-\n\n\n" + String(repeating: " ", count: 42) + "x\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:46-6:44
                list bullet '-' tight @3:51-3:52
                  item @3:51-3:52
                paragraph @6:43-6:44
                  text "x" @6:43-6:44

            """
        ),
        TreeDumpCase(
            "list item holding a paragraph in the innermost of ten footnote definitions",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:- a\n\n\n" + String(repeating: " ", count: 42) + "b\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:46-6:44
                list bullet '-' loose @3:51-6:44
                  item @3:51-6:44
                    paragraph @3:53-3:54
                      text "a" @3:53-3:54
                    paragraph @6:43-6:44
                      text "b" @6:43-6:44

            """
        ),
        TreeDumpCase(
            "blank lines of tabs keep twelve footnote definitions open",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:x\n\n\t\n\t\t\n\n" + String(repeating: "\t", count: 12) + "y\n",
            """
            document @1:1-9:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:56-8:14
                paragraph @3:61-3:62
                  text "x" @3:61-3:62
                paragraph @8:13-8:14
                  text "y" @8:13-8:14

            """
        ),
        TreeDumpCase(
            "twelve footnote definitions, three empty lines",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:x\n\n\n\n" + String(repeating: " ", count: 48) + "y\n",
            """
            document @1:1-8:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:56-7:50
                paragraph @3:61-3:62
                  text "x" @3:61-3:62
                paragraph @7:49-7:50
                  text "y" @7:49-7:50

            """
        ),
        TreeDumpCase(
            "empty lines around a line of spaces keep twelve footnote definitions open",
            "[^a]\n\n[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^b]:[^a]:x\n\n\n    \n\n" + String(repeating: " ", count: 48) + "y\n",
            """
            document @1:1-9:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:56-8:50
                paragraph @3:61-3:62
                  text "x" @3:61-3:62
                paragraph @8:49-8:50
                  text "y" @8:49-8:50

            """
        ),
        TreeDumpCase(
            "ten nested list items holding a paragraph",
            "- - - - - - - - - - x\n\n\n" + String(repeating: " ", count: 20) + "y\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:22
                item @1:1-4:22
                  list bullet '-' tight @1:3-4:22
                    item @1:3-4:22
                      list bullet '-' tight @1:5-4:22
                        item @1:5-4:22
                          list bullet '-' tight @1:7-4:22
                            item @1:7-4:22
                              list bullet '-' tight @1:9-4:22
                                item @1:9-4:22
                                  list bullet '-' tight @1:11-4:22
                                    item @1:11-4:22
                                      list bullet '-' tight @1:13-4:22
                                        item @1:13-4:22
                                          list bullet '-' tight @1:15-4:22
                                            item @1:15-4:22
                                              list bullet '-' tight @1:17-4:22
                                                item @1:17-4:22
                                                  list bullet '-' loose @1:19-4:22
                                                    item @1:19-4:22
                                                      paragraph @1:21-1:22
                                                        text "x" @1:21-1:22
                                                      paragraph @4:21-4:22
                                                        text "y" @4:21-4:22

            """
        ),
        TreeDumpCase(
            "eleven nested list items, the innermost without a block",
            "- + - + - + - + - + -\n\n\n" + String(repeating: " ", count: 22) + "x\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:24
                item @1:1-4:24
                  list bullet '+' tight @1:3-4:24
                    item @1:3-4:24
                      list bullet '-' tight @1:5-4:24
                        item @1:5-4:24
                          list bullet '+' tight @1:7-4:24
                            item @1:7-4:24
                              list bullet '-' tight @1:9-4:24
                                item @1:9-4:24
                                  list bullet '+' tight @1:11-4:24
                                    item @1:11-4:24
                                      list bullet '-' tight @1:13-4:24
                                        item @1:13-4:24
                                          list bullet '+' tight @1:15-4:24
                                            item @1:15-4:24
                                              list bullet '-' tight @1:17-4:24
                                                item @1:17-4:24
                                                  list bullet '+' loose @1:19-4:24
                                                    item @1:19-4:24
                                                      list bullet '-' tight @1:21-1:22
                                                        item @1:21-1:22
                                                      paragraph @4:23-4:24
                                                        text "x" @4:23-4:24

            """
        ),
        TreeDumpCase(
            "eleven nested list items, the innermost without a block, a line of spaces",
            "- + - + - + - + - + -\n  \n\n" + String(repeating: " ", count: 22) + "x\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:24
                item @1:1-4:24
                  list bullet '+' tight @1:3-4:24
                    item @1:3-4:24
                      list bullet '-' tight @1:5-4:24
                        item @1:5-4:24
                          list bullet '+' tight @1:7-4:24
                            item @1:7-4:24
                              list bullet '-' tight @1:9-4:24
                                item @1:9-4:24
                                  list bullet '+' tight @1:11-4:24
                                    item @1:11-4:24
                                      list bullet '-' tight @1:13-4:24
                                        item @1:13-4:24
                                          list bullet '+' tight @1:15-4:24
                                            item @1:15-4:24
                                              list bullet '-' tight @1:17-4:24
                                                item @1:17-4:24
                                                  list bullet '+' loose @1:19-4:24
                                                    item @1:19-4:24
                                                      list bullet '-' tight @1:21-1:22
                                                        item @1:21-1:22
                                                      paragraph @4:23-4:24
                                                        text "x" @4:23-4:24

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: TreeDumpCase) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
