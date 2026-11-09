/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Indented code blocks followed by blank lines.
///
/// Blank lines following an indented code block are not included in it (Indented code blocks), so the block ends at the
/// end of its last line that is not blank. Blank lines between its lines are part of it. The blank lines are empty,
/// hold fewer than four columns of whitespace, more than four columns, or a tab, and the block closes at a line that
/// is not indented, at a line that does not continue its container, or at the end of the document. Each is tried at
/// the top level, in a block quote, in a bullet and an ordered list item, in a footnote definition and in a block
/// quote in a list item. A block closed by the line right after its last line, and one whose last line ends with
/// spaces, end at the end of their last line.
@Suite("An indented code block ends at its last line that is not blank")
struct IndentedCodeTrailingBlankRangeTests {

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
            "top level, an empty line, closed by a line that is not indented",
            "    a\n\nb\n",
            """
            document @1:1-3:2
              code_block "" "a\\n" @1:5-1:6
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """
        ),
        Case(
            "top level, a line of more than four columns of spaces, closed by a line that is not indented",
            "    a\n      \nb\n",
            """
            document @1:1-3:2
              code_block "" "a\\n" @1:5-1:6
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """
        ),
        Case(
            "top level, a line of fewer than four columns of spaces, at the end of the document",
            "    a\n  \n",
            """
            document @1:1-2:3
              code_block "" "a\\n" @1:5-1:6

            """
        ),
        Case(
            "top level, a tab, at the end of the document",
            "    a\n\t\n",
            """
            document @1:1-2:2
              code_block "" "a\\n" @1:5-1:6

            """
        ),
        Case(
            "top level, several blank lines",
            "    a\n\n    \n\t\nb\n",
            """
            document @1:1-5:2
              code_block "" "a\\n" @1:5-1:6
              paragraph @5:1-5:2
                text "b" @5:1-5:2

            """
        ),
        Case(
            "top level, a blank line between two lines",
            "    a\n\n    b\n",
            """
            document @1:1-3:6
              code_block "" "a\\n\\nb\\n" @1:5-3:6

            """
        ),
        Case(
            "top level, a blank line between two lines, then a blank line",
            "    a\n\n    b\n\n",
            """
            document @1:1-4:1
              code_block "" "a\\n\\nb\\n" @1:5-3:6

            """
        ),
        Case(
            "top level, a last line ending with spaces, then a blank line",
            "    a  \n\nb\n",
            """
            document @1:1-3:2
              code_block "" "a  \\n" @1:5-1:8
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """
        ),
        Case(
            "top level, closed by the next line",
            "    a\nb\n",
            """
            document @1:1-2:2
              code_block "" "a\\n" @1:5-1:6
              paragraph @2:1-2:2
                text "b" @2:1-2:2

            """
        ),
        Case(
            "block quote, a blank line, closed by a line that does not continue the block quote",
            ">     a\n>\nb\n",
            """
            document @1:1-3:2
              block_quote @1:1-2:2
                code_block "" "a\\n" @1:7-1:8
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """
        ),
        Case(
            "block quote, more than four columns of spaces, at the end of the document",
            ">     a\n>     \n",
            """
            document @1:1-2:7
              block_quote @1:1-2:2
                code_block "" "a\\n" @1:7-1:8

            """
        ),
        Case(
            "bullet item, an empty line, closed by a line that does not continue the item",
            "-     a\n\nb\n",
            """
            document @1:1-3:2
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  code_block "" "a\\n" @1:7-1:8
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """
        ),
        Case(
            "bullet item, a split tab and a line of tabs and spaces, at the end of the document",
            "+ \t\tB\r\t\t  ",
            """
            document @1:1-2:5
              list bullet '+' tight @1:1-1:6
                item @1:1-1:6
                  code_block "" "  B\\n" @1:4-1:6

            """
        ),
        Case(
            "ordered item, fewer than four columns of spaces, at the end of the document",
            "1.     a\n   \n",
            """
            document @1:1-2:4
              list ordered start=1 delim=period tight @1:1-1:9
                item @1:1-1:9
                  code_block "" "a\\n" @1:8-1:9

            """
        ),
        Case(
            "footnote definition, an empty line, closed by a line that does not continue the definition",
            "[^a]\n\n[^a]: x\n\n        a\n\nb\n",
            """
            document @1:1-7:2
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              paragraph @7:1-7:2
                text "b" @7:1-7:2
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                code_block "" "a\\n" @5:9-5:10

            """
        ),
        Case(
            "block quote in a list item, a blank line, at the end of the document",
            "- >     a\n  >\n",
            """
            document @1:1-2:4
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  block_quote @1:3-2:4
                    code_block "" "a\\n" @1:9-1:10

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
