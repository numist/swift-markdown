/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Fenced code blocks closed because a later line does not continue a container they are in.
///
/// A fenced code block ends with its closing fence, at the end of the document, or at the end of the containing block
/// (Fenced code blocks). When a line fails a container's continuation, the code block closes with that container, so
/// it ends just past its last content line's content, at the start of that line when it held only indentation or a
/// container's prefix, or past its opening fence's info string or fence when it has no content lines, and never extends
/// past its container. A code block closed by its closing fence ends past that fence, and
/// one open at the end of the document ends on the last line.
@Suite("A fenced code block ends on its last line when its container closes")
struct FencedCodeClosedContainerRangeTests {

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
            "block quote ends right after the opening fence",
            "> ```\nx\n",
            """
            document @1:1-3:1
              block_quote @1:1-1:6
                code_block "" "" @1:3-1:6
              paragraph @2:1-2:2
                text "x" @2:1-2:2

            """
        ),
        Case(
            "block quote ends after a content line",
            "> ```\n> a\nx\n",
            """
            document @1:1-4:1
              block_quote @1:1-2:4
                code_block "" "a\\n" @1:3-2:4
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """
        ),
        Case(
            "block quote ends after a blank content line",
            "> ```\n>\nx\n",
            """
            document @1:1-4:1
              block_quote @1:1-2:2
                code_block "" "\\n" @1:3-2:1
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """
        ),
        Case(
            "block quote ends at a blank line",
            "> ```\n> a\n\nx\n",
            """
            document @1:1-5:1
              block_quote @1:1-2:4
                code_block "" "a\\n" @1:3-2:4
              paragraph @4:1-4:2
                text "x" @4:1-4:2

            """
        ),
        Case(
            "block quote, closed by its closing fence",
            "> ```\n> a\n> ```\nx\n",
            """
            document @1:1-5:1
              block_quote @1:1-3:6
                code_block "" "a\\n" @1:3-3:6
              paragraph @4:1-4:2
                text "x" @4:1-4:2

            """
        ),
        Case(
            "block quote, open at the end of the document",
            "> ```\n> a\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                code_block "" "a\\n" @1:3-2:4

            """
        ),
        Case(
            "bullet item ends right after the opening fence",
            "- ```\nx\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "" @1:3-1:6
              paragraph @2:1-2:2
                text "x" @2:1-2:2

            """
        ),
        Case(
            "bullet item ends after a content line",
            "- ```\n  a\nx\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  code_block "" "a\\n" @1:3-2:4
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """
        ),
        Case(
            "bullet item ends after a blank content line",
            "- ```\n\nx\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-2:1
                item @1:1-2:1
                  code_block "" "\\n" @1:3-2:1
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """
        ),
        Case(
            "bullet item ends at a sibling item",
            "- ```\n  a\n- b\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:4
                item @1:1-2:4
                  code_block "" "a\\n" @1:3-2:4
                item @3:1-3:4
                  paragraph @3:3-3:4
                    text "b" @3:3-3:4

            """
        ),
        Case(
            "bullet item, closed by its closing fence",
            "- ```\n  a\n  ```\nx\n",
            """
            document @1:1-5:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  code_block "" "a\\n" @1:3-3:6
              paragraph @4:1-4:2
                text "x" @4:1-4:2

            """
        ),
        Case(
            "bullet item, open at the end of the document",
            "- ```\n  a\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  code_block "" "a\\n" @1:3-2:4

            """
        ),
        Case(
            "ordered item ends right after the opening fence",
            "1. ```\nx\n",
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-1:7
                item @1:1-1:7
                  code_block "" "" @1:4-1:7
              paragraph @2:1-2:2
                text "x" @2:1-2:2

            """
        ),
        Case(
            "ordered item ends after a content line",
            "1. ```\n   a\nx\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-2:5
                item @1:1-2:5
                  code_block "" "a\\n" @1:4-2:5
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """
        ),
        Case(
            "ordered item ends at a sibling item",
            "1. ```\n   a\n2. b\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:5
                item @1:1-2:5
                  code_block "" "a\\n" @1:4-2:5
                item @3:1-3:5
                  paragraph @3:4-3:5
                    text "b" @3:4-3:5

            """
        ),
        Case(
            "footnote definition ends right after the opening fence",
            "[^a]\n\n[^a]: ```\nx\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @4:1-4:2
                text "x" @4:1-4:2
              footnote_definition "a" @3:1-3:10
                code_block "" "" @3:7-3:10

            """
        ),
        Case(
            "footnote definition ends after a content line",
            "[^a]\n\n[^a]: ```\n    a\nx\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @5:1-5:2
                text "x" @5:1-5:2
              footnote_definition "a" @3:1-4:6
                code_block "" "a\\n" @3:7-4:6

            """
        ),
        Case(
            "footnote definition ends after a blank content line",
            "[^a]\n\n[^a]: ```\n\nx\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @5:1-5:2
                text "x" @5:1-5:2
              footnote_definition "a" @3:1-4:1
                code_block "" "\\n" @3:7-4:1

            """
        ),
        Case(
            "footnote definition, closed by its closing fence",
            "[^a]\n\n[^a]: ```\n    a\n    ```\nx\n",
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @6:1-6:2
                text "x" @6:1-6:2
              footnote_definition "a" @3:1-5:8
                code_block "" "a\\n" @3:7-5:8

            """
        ),
        Case(
            "block quote in an item ends after a content line",
            "- > ```\n  > a\n  x\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:4
                item @1:1-3:4
                  block_quote @1:3-2:6
                    code_block "" "a\\n" @1:5-2:6
                  paragraph @3:3-3:4
                    text "x" @3:3-3:4

            """
        ),
        Case(
            "item in a block quote ends after a content line",
            "> - ```\n>   a\n> x\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:4
                list bullet '-' tight @1:3-2:6
                  item @1:3-2:6
                    code_block "" "a\\n" @1:5-2:6
                paragraph @3:3-3:4
                  text "x" @3:3-3:4

            """
        ),
        Case(
            "block quote in a block quote ends after a content line",
            "> > ```\n> > a\n> x\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:4
                block_quote @1:3-2:6
                  code_block "" "a\\n" @1:5-2:6
                paragraph @3:3-3:4
                  text "x" @3:3-3:4

            """
        ),
        Case(
            "footnote definition in a block quote ends after a content line",
            "[^a]\n\n> [^a]: ```\n>     a\n> x\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:4
                paragraph @5:3-5:4
                  text "x" @5:3-5:4
              footnote_definition "a" @3:3-4:8
                code_block "" "a\\n" @3:9-4:8

            """
        ),
        Case(
            "item in a block quote ends at a blank line",
            "> - ```\n>   a\n\nx\n",
            """
            document @1:1-5:1
              block_quote @1:1-2:6
                list bullet '-' tight @1:3-2:6
                  item @1:3-2:6
                    code_block "" "a\\n" @1:5-2:6
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
