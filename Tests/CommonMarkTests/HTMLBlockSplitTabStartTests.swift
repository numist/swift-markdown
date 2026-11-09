/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// HTML blocks whose first line begins with the remaining columns of a tab that a container's prefix partly consumes.
///
/// Per Tabs, when a container's prefix consumes only part of a tab, the tab's remaining columns are indentation, and an
/// HTML block keeps its line's indentation as content, so those columns become leading spaces: `>→<div>` gives
/// `  <div>`. Those spaces stand for the split tab, so the block starts at the tab's byte. Where the prefix splits no
/// tab, the block starts at the first space of the indentation it keeps, or at its `<` if it keeps none.
@Suite("An HTML block that begins with a split tab's columns starts at the tab")
struct HTMLBlockSplitTabStartTests {

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
            "block quote, type 6, first line",
            ">\t<div>\n",
            """
            document @1:1-1:8
              block_quote @1:1-1:8
                html_block "  <div>\\n" @1:2-1:8

            """
        ),
        Case(
            "block quote, type 6, interrupting a paragraph",
            "> a\n>\t<div>\n",
            """
            document @1:1-2:8
              block_quote @1:1-2:8
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
                html_block "  <div>\\n" @2:2-2:8

            """
        ),
        Case(
            "block quote, type 7, after a blank line",
            ">\n>\t<a>\n",
            """
            document @1:1-2:6
              block_quote @1:1-2:6
                html_block "  <a>\\n" @2:2-2:6

            """
        ),
        Case(
            "block quote, type 2, ending on its first line",
            ">\t<!-- x -->\n",
            """
            document @1:1-1:13
              block_quote @1:1-1:13
                html_block "  <!-- x -->\\n" @1:2-1:13

            """
        ),
        Case(
            "block quote, type 1, open at the end of the document",
            ">\t<pre>\n> x\n",
            """
            document @1:1-2:4
              block_quote @1:1-2:4
                html_block "  <pre>\\nx\\n" @1:2-2:4

            """
        ),
        Case(
            "block quote in a block quote, type 6",
            ">>\t<div>\n",
            """
            document @1:1-1:9
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block " <div>\\n" @1:3-1:9

            """
        ),
        Case(
            "bullet item content column, type 6",
            "- a\n\n \t<div>\n",
            """
            document @1:1-3:8
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <div>\\n" @3:2-3:8

            """
        ),
        Case(
            "ordered item content column, type 6",
            "1. a\n\n\t<div>\n",
            """
            document @1:1-3:7
              list ordered start=1 delim=period loose @1:1-3:7
                item @1:1-3:7
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <div>\\n" @3:1-3:7

            """
        ),
        Case(
            "footnote definition content column in a block quote, type 6",
            "[^a]\n\n> [^a]: x\n>\n>    \t<div>\n",
            """
            document @1:1-5:12
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <div>\\n" @5:6-5:12

            """
        ),
        Case(
            "block quote after a list item, type 4",
            "- ```\n>\t<!AD\n",
            """
            document @1:1-2:7
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              block_quote @2:1-2:7
                html_block "  <!AD\\n" @2:2-2:7

            """
        ),
        Case(
            "block quote marker followed by a space",
            "> <div>\n",
            """
            document @1:1-1:8
              block_quote @1:1-1:8
                html_block "<div>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote marker followed by spaces",
            ">   <div>\n",
            """
            document @1:1-1:10
              block_quote @1:1-1:10
                html_block "  <div>\\n" @1:3-1:10

            """
        ),
        Case(
            "a tab that stands for one column after a block quote marker in a list item",
            "- >\t<div>\n",
            """
            document @1:1-1:10
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
                  block_quote @1:3-1:10
                    html_block "<div>\\n" @1:5-1:10

            """
        ),
        Case(
            "spaces at the top level",
            "  <div>\n",
            """
            document @1:1-1:8
              html_block "  <div>\\n" @1:1-1:8

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
