/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// HTML blocks of types 1 to 5 whose end condition is on a later line than their start condition.
///
/// An HTML block of types 1 to 5 continues until a line that meets its end condition, and that line is the last line
/// of the block (HTML blocks), so the block ends at the end of that line, including text after the end condition and
/// trailing spaces. A block that ends otherwise ends at the end of its last line.
@Suite("An HTML block ends on the line that meets its end condition")
struct HTMLBlockEndConditionLineRangeTests {

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
            "top level, type 1, after a line",
            "<pre>\nfoo\n</pre>\n",
            """
            document @1:1-3:7
              html_block "<pre>\\nfoo\\n</pre>\\n" @1:1-3:7

            """
        ),
        Case(
            "top level, type 1, on the next line, then a paragraph",
            "<pre>\n</pre>\nfoo\n",
            """
            document @1:1-3:4
              html_block "<pre>\\n</pre>\\n" @1:1-2:7
              paragraph @3:1-3:4
                text "foo" @3:1-3:4

            """
        ),
        Case(
            "top level, type 1, with trailing spaces",
            "<pre>\n</pre>  \n",
            """
            document @1:1-2:9
              html_block "<pre>\\n</pre>  \\n" @1:1-2:9

            """
        ),
        Case(
            "top level, type 2, after a blank line",
            "<!--\n\nx -->\n",
            """
            document @1:1-3:6
              html_block "<!--\\n\\nx -->\\n" @1:1-3:6

            """
        ),
        Case(
            "top level, type 3, with text after the end condition",
            "<?php\necho 1; ?> trailing\n",
            """
            document @1:1-2:20
              html_block "<?php\\necho 1; ?> trailing\\n" @1:1-2:20

            """
        ),
        Case(
            "top level, type 4, on the next line",
            "<!DOCTYPE\nhtml>\n",
            """
            document @1:1-2:6
              html_block "<!DOCTYPE\\nhtml>\\n" @1:1-2:6

            """
        ),
        Case(
            "top level, type 5, after a line",
            "<![CDATA[\nx\n]]>\n",
            """
            document @1:1-3:4
              html_block "<![CDATA[\\nx\\n]]>\\n" @1:1-3:4

            """
        ),
        Case(
            "block quote, type 1, after a line",
            "> <pre>\n> x\n> </pre>\n",
            """
            document @1:1-3:9
              block_quote @1:1-3:9
                html_block "<pre>\\nx\\n</pre>\\n" @1:3-3:9

            """
        ),
        Case(
            "block quote, type 1, after a tab split by the marker",
            ">\t<pre>\n>\t</pre>\n",
            """
            document @1:1-2:9
              block_quote @1:1-2:9
                html_block "  <pre>\\n  </pre>\\n" @1:2-2:9

            """
        ),
        Case(
            "bullet item, type 2, on the next line",
            "- <!--\n  x -->\n",
            """
            document @1:1-2:8
              list bullet '-' tight @1:1-2:8
                item @1:1-2:8
                  html_block "<!--\\nx -->\\n" @1:3-2:8

            """
        ),
        Case(
            "ordered item, type 3, on the next line",
            "1. <?\n   ?>\n",
            """
            document @1:1-2:6
              list ordered start=1 delim=period tight @1:1-2:6
                item @1:1-2:6
                  html_block "<?\\n?>\\n" @1:4-2:6

            """
        ),
        Case(
            "footnote definition, type 1, on the next line",
            "[^a]\n\n[^a]: <pre>\n    </pre>\n",
            """
            document @1:1-4:11
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-4:11
                html_block "<pre>\\n</pre>\\n" @3:7-4:11

            """
        ),
        Case(
            "block quote in a list item, type 5, on the next line",
            "- > <![CDATA[\n  > ]]>\n",
            """
            document @1:1-2:8
              list bullet '-' tight @1:1-2:8
                item @1:1-2:8
                  block_quote @1:3-2:8
                    html_block "<![CDATA[\\n]]>\\n" @1:5-2:8

            """
        ),
        Case(
            "list item in a block quote, type 4, on the next line",
            "> - <!X\n>   >\n",
            """
            document @1:1-2:6
              block_quote @1:1-2:6
                list bullet '-' tight @1:3-2:6
                  item @1:3-2:6
                    html_block "<!X\\n>\\n" @1:5-2:6

            """
        ),
        Case(
            "top level, type 1, on its first line",
            "<pre>x</pre>\nfoo\n",
            """
            document @1:1-2:4
              html_block "<pre>x</pre>\\n" @1:1-1:13
              paragraph @2:1-2:4
                text "foo" @2:1-2:4

            """
        ),
        Case(
            "top level, type 6, ended by a blank line",
            "<div>\nx\n\nfoo\n",
            """
            document @1:1-4:4
              html_block "<div>\\nx\\n" @1:1-2:2
              paragraph @4:1-4:4
                text "foo" @4:1-4:4

            """
        ),
        Case(
            "block quote, type 1, ended by a line that does not continue the block quote",
            "> <pre>\n> x\nfoo\n",
            """
            document @1:1-3:4
              block_quote @1:1-2:4
                html_block "<pre>\\nx\\n" @1:3-2:4
              paragraph @3:1-3:4
                text "foo" @3:1-3:4

            """
        ),
        Case(
            "top level, type 1, open at the end of the document",
            "<pre>\nx\n",
            """
            document @1:1-2:2
              html_block "<pre>\\nx\\n" @1:1-2:2

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
