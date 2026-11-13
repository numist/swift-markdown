/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Where an HTML block's source range ends.
///
/// An HTML block of types 1 to 5 continues until a line that meets its end condition, and that line is the last line
/// of the block (HTML blocks), so the block ends at the end of that line, including text after the end condition and
/// trailing spaces. A block that ends otherwise ends at the end of its last line, or at the start of that line when it
/// holds only a container's prefix.
@Suite("An HTML block ends on the line that meets its end condition")
struct HTMLBlockEndConditionLineRangeTests {

    static let cases: [TreeDumpCase] = [
        TreeDumpCase(
            "top level, type 1, after a line",
            "<pre>\nfoo\n</pre>\n",
            """
            document @1:1-4:1
              html_block "<pre>\\nfoo\\n</pre>\\n" @1:1-3:7

            """
        ),
        TreeDumpCase(
            "top level, type 1, on the next line, then a paragraph",
            "<pre>\n</pre>\nfoo\n",
            """
            document @1:1-4:1
              html_block "<pre>\\n</pre>\\n" @1:1-2:7
              paragraph @3:1-3:4
                text "foo" @3:1-3:4

            """
        ),
        TreeDumpCase(
            "top level, type 1, with trailing spaces",
            "<pre>\n</pre>  \n",
            """
            document @1:1-3:1
              html_block "<pre>\\n</pre>  \\n" @1:1-2:9

            """
        ),
        TreeDumpCase(
            "top level, type 2, after a blank line, then a paragraph",
            "<!--\n\nx -->\nfoo\n",
            """
            document @1:1-5:1
              html_block "<!--\\n\\nx -->\\n" @1:1-3:6
              paragraph @4:1-4:4
                text "foo" @4:1-4:4

            """
        ),
        TreeDumpCase(
            "top level, type 3, with text after the end condition, then a paragraph",
            "<?php\necho 1; ?> trailing\nfoo\n",
            """
            document @1:1-4:1
              html_block "<?php\\necho 1; ?> trailing\\n" @1:1-2:20
              paragraph @3:1-3:4
                text "foo" @3:1-3:4

            """
        ),
        TreeDumpCase(
            "top level, type 4, on the next line, then a paragraph",
            "<!DOCTYPE\nhtml>\nfoo\n",
            """
            document @1:1-4:1
              html_block "<!DOCTYPE\\nhtml>\\n" @1:1-2:6
              paragraph @3:1-3:4
                text "foo" @3:1-3:4

            """
        ),
        TreeDumpCase(
            "top level, type 5, after a line, then a paragraph",
            "<![CDATA[\nx\n]]>\nfoo\n",
            """
            document @1:1-5:1
              html_block "<![CDATA[\\nx\\n]]>\\n" @1:1-3:4
              paragraph @4:1-4:4
                text "foo" @4:1-4:4

            """
        ),
        TreeDumpCase(
            "block quote, type 1, after a line",
            "> <pre>\n> x\n> </pre>\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:9
                html_block "<pre>\\nx\\n</pre>\\n" @1:3-3:9

            """
        ),
        TreeDumpCase(
            "block quote, type 1, after a tab split by the marker",
            ">\t<pre>\n>\t</pre>\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:9
                html_block "  <pre>\\n  </pre>\\n" @1:2-2:9

            """
        ),
        TreeDumpCase(
            "bullet item, type 2, on the next line, then a paragraph",
            "- <!--\n  x -->\n  foo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  html_block "<!--\\nx -->\\n" @1:3-2:8
                  paragraph @3:3-3:6
                    text "foo" @3:3-3:6

            """
        ),
        TreeDumpCase(
            "ordered item, type 3, on the next line, then a paragraph",
            "1. <?\n   ?>\n   foo\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period tight @1:1-3:7
                item @1:1-3:7
                  html_block "<?\\n?>\\n" @1:4-2:6
                  paragraph @3:4-3:7
                    text "foo" @3:4-3:7

            """
        ),
        TreeDumpCase(
            "footnote definition, type 1, on the next line",
            "[^a]\n\n[^a]: <pre>\n    </pre>\n",
            """
            document @1:1-5:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-4:11
                html_block "<pre>\\n</pre>\\n" @3:7-4:11

            """
        ),
        TreeDumpCase(
            "block quote in a list item, type 5, on the next line, then a paragraph",
            "- > <![CDATA[\n  > ]]>\n  > foo\n",
            """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:8
                item @1:1-3:8
                  block_quote @1:3-3:8
                    html_block "<![CDATA[\\n]]>\\n" @1:5-2:8
                    paragraph @3:5-3:8
                      text "foo" @3:5-3:8

            """
        ),
        TreeDumpCase(
            "list item in a block quote, type 4, on the next line, then a paragraph",
            "> - <!X\n>   >\n>   foo\n",
            """
            document @1:1-4:1
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    html_block "<!X\\n>\\n" @1:5-2:6
                    paragraph @3:5-3:8
                      text "foo" @3:5-3:8

            """
        ),
        TreeDumpCase(
            "top level, type 1, on its first line",
            "<pre>x</pre>\nfoo\n",
            """
            document @1:1-3:1
              html_block "<pre>x</pre>\\n" @1:1-1:13
              paragraph @2:1-2:4
                text "foo" @2:1-2:4

            """
        ),
        TreeDumpCase(
            "top level, type 6, ended by a blank line",
            "<div>\nx\n\nfoo\n",
            """
            document @1:1-5:1
              html_block "<div>\\nx\\n" @1:1-2:2
              paragraph @4:1-4:4
                text "foo" @4:1-4:4

            """
        ),
        TreeDumpCase(
            "block quote, type 1, ended by a line that does not continue the block quote",
            "> <pre>\n> x\nfoo\n",
            """
            document @1:1-4:1
              block_quote @1:1-2:4
                html_block "<pre>\\nx\\n" @1:3-2:4
              paragraph @3:1-3:4
                text "foo" @3:1-3:4

            """
        ),
        TreeDumpCase(
            "top level, type 1, open at the end of the document",
            "<pre>\nx\n",
            """
            document @1:1-3:1
              html_block "<pre>\\nx\\n" @1:1-2:2

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: TreeDumpCase) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
