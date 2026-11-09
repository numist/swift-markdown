/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The indentation an opening code fence's content lines lose, measured in columns.
///
/// When the fence is indented N columns, up to N columns of indentation are removed from each content line (Fenced code
/// blocks), with tabs expanded to a tab stop of 4 (Tabs). The fence's indentation is measured from its container's
/// content column, so a tab after a block quote marker, part of which is the marker's optional space, counts only its
/// remaining columns, and a tab after the marker's space counts to the next tab stop. A content line's tab that crosses
/// the N-column boundary keeps its remaining columns as spaces, and a tab past the boundary is content. Fences indented
/// only with spaces, or after a tab that stands for one column, lose the same indentation in bytes and columns.
@Suite("Fenced code content loses the fence's indentation in columns")
struct FencedCodeColumnIndentTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let expected: String
        let fenceOffset: Int

        init(_ name: String, _ source: String, offset fenceOffset: Int, _ expected: String) {
            self.name = name
            self.source = source
            self.fenceOffset = fenceOffset
            self.expected = expected
        }

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            "a tab partly consumed by a block quote marker, content after the same tab",
            ">\t```\n>\tx\n",
            offset: 2,
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                code_block "" "x\\n" @1:3-2:4

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker, content indented three columns",
            ">\t```\n>    x\n",
            offset: 2,
            """
            document @1:1-3:1
              block_quote @1:1-2:7
                code_block "" " x\\n" @1:3-2:7

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker, content not indented",
            ">\t```\n> x\n",
            offset: 2,
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                code_block "" "x\\n" @1:3-2:4

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker, content with a second tab",
            ">\t```\n>\t\tx\n",
            offset: 2,
            """
            document @1:1-3:1
              block_quote @1:1-2:5
                code_block "" "\\tx\\n" @1:3-2:5

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker and a space, content tab crossing the boundary",
            ">\t ```\n>\t\tx\n",
            offset: 3,
            """
            document @1:1-3:1
              block_quote @1:1-2:5
                code_block "" "   x\\n" @1:4-2:5

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker and a space, content indented past the boundary",
            ">\t ```\n>\t  x\n",
            offset: 3,
            """
            document @1:1-3:1
              block_quote @1:1-2:6
                code_block "" " x\\n" @1:4-2:6

            """
        ),
        Case(
            "a tab after a block quote marker's space, content after the same tab",
            "> \t```\n> \tx\n",
            offset: 2,
            """
            document @1:1-3:1
              block_quote @1:1-2:5
                code_block "" "x\\n" @1:4-2:5

            """
        ),
        Case(
            "a tab after a block quote marker's space, content after a partly consumed tab",
            "> \t```\n>\tx\n",
            offset: 2,
            """
            document @1:1-3:1
              block_quote @1:1-2:4
                code_block "" "x\\n" @1:4-2:4

            """
        ),
        Case(
            "a tab after a bullet item's content column",
            "- a\n\n  \t```\n  \tx\n",
            offset: 2,
            """
            document @1:1-5:1
              list bullet '-' loose @1:1-4:5
                item @1:1-4:5
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  code_block "" "x\\n" @3:4-4:5

            """
        ),
        Case(
            "a tab standing for one column after an ordered item's content column",
            "1. a\n\n   \t```\n   \tx\n",
            offset: 1,
            """
            document @1:1-5:1
              list ordered start=1 delim=period loose @1:1-4:6
                item @1:1-4:6
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  code_block "" "x\\n" @3:5-4:6

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker in a block quote",
            ">>\t```\n>>\tx\n",
            offset: 1,
            """
            document @1:1-3:1
              block_quote @1:1-2:5
                block_quote @1:2-2:5
                  code_block "" "x\\n" @1:4-2:5

            """
        ),
        Case(
            "a tab partly consumed by a footnote definition's content column in a block quote",
            "[^a]\n\n> [^a]: x\n>\n>    \t```\n>    \ty\n",
            offset: 2,
            """
            document @1:1-7:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-6:8
              footnote_definition "a" @3:3-6:8
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                code_block "" "y\\n" @5:7-6:8

            """
        ),
        Case(
            "a tab partly consumed by a block quote marker in an ordered item",
            "1. >\t```\n   >\tx\n",
            offset: 3,
            """
            document @1:1-3:1
              list ordered start=1 delim=period tight @1:1-2:7
                item @1:1-2:7
                  block_quote @1:4-2:7
                    code_block "" "x\\n" @1:6-2:7

            """
        ),
        Case(
            "spaces at the top level",
            "  ```\n  x\n   y\n z\n",
            offset: 2,
            """
            document @1:1-5:1
              code_block "" "x\\n y\\nz\\n" @1:3-4:3

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
        let codeBlockKinds = MarkdownDocument.withParsedDocument(c.source, options: [.footnotes]) { doc in
            dfs(doc).map(\.kind).filter { if case .codeBlock = $0 { true } else { false } }.map(TreeDump.describe)
        }
        #expect(codeBlockKinds == ["code_block fenced fence='`' length=3 offset=\(c.fenceOffset)"])
    }
}
