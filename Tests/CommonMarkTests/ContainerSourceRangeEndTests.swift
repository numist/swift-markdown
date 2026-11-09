/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A container block's source range ends just past its last content byte: the end of its last child, or of its own
/// marker (a block quote's last `>`, a list item's marker, a footnote definition's `[^label]:`) where that is later.
/// Whitespace and blank lines after its content are not part of it. A link reference definition or a task list item
/// marker is content even though it leaves no child, and a fenced code block's or HTML block's blank lines are its
/// content, while an indented code block's trailing blank lines are not (Indented code blocks).
@Suite("Container source range ends")
struct ContainerSourceRangeEndTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = []) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    @Test("a list item and its list end at the item's last content byte, before blank lines")
    func itemBeforeBlankLines() {
        #expect(tree("- a\n\n\nb") == """
            document @1:1-4:2
              list bullet '-' tight @1:1-1:4
                item @1:1-1:4
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
              paragraph @4:1-4:2
                text "b" @4:1-4:2

            """)
    }

    @Test("a list item ending the document ends before its trailing whitespace and blank lines")
    func itemAtDocumentEnd() {
        #expect(tree("1. a\n\n   b  \n\n\n") == """
            document @1:1-5:1
              list ordered start=1 delim=period loose @1:1-3:5
                item @1:1-3:5
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  paragraph @3:4-3:5
                    text "b" @3:4-3:5

            """)
    }

    @Test("an empty list item ends past its marker, and a list ending in one ends there")
    func emptyItems() {
        #expect(tree("- a\n-  \n\nb") == """
            document @1:1-4:2
              list bullet '-' tight @1:1-2:2
                item @1:1-1:4
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                item @2:1-2:2
              paragraph @4:1-4:2
                text "b" @4:1-4:2

            """)
        #expect(tree("10.\n\nb") == """
            document @1:1-3:2
              list ordered start=10 delim=period tight @1:1-1:4
                item @1:1-1:4
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """)
    }

    @Test("nested lists end at the innermost item's last content byte")
    func nestedLists() {
        #expect(tree("- a\n  - b\n\n\nc") == """
            document @1:1-5:2
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  list bullet '-' tight @2:3-2:6
                    item @2:3-2:6
                      paragraph @2:5-2:6
                        text "b" @2:5-2:6
              paragraph @5:1-5:2
                text "c" @5:1-5:2

            """)
    }

    @Test("a block quote ends before trailing whitespace, and at a later line's `>`")
    func blockQuote() {
        #expect(tree("> a  \n\nb") == """
            document @1:1-3:2
              block_quote @1:1-1:4
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """)
        #expect(tree("- > a\n  >  \n\nb") == """
            document @1:1-4:2
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  block_quote @1:3-2:4
                    paragraph @1:5-1:6
                      text "a" @1:5-1:6
              paragraph @4:1-4:2
                text "b" @4:1-4:2

            """)
    }

    @Test("a fenced code block's or HTML block's blank lines are content, so its item ends on the last of them")
    func fencedCodeAndHTMLBlankLines() {
        #expect(tree("- ~~~\n  a\n\n\nb") == """
            document @1:1-5:2
              list bullet '-' tight @1:1-4:1
                item @1:1-4:1
                  code_block "" "a\\n\\n\\n" @1:3-4:1
              paragraph @5:1-5:2
                text "b" @5:1-5:2

            """)
        #expect(tree("- <pre>\n\n\nb") == """
            document @1:1-4:2
              list bullet '-' tight @1:1-3:1
                item @1:1-3:1
                  html_block "<pre>\\n\\n\\n" @1:3-3:1
              paragraph @4:1-4:2
                text "b" @4:1-4:2

            """)
    }

    @Test("an indented code block's trailing blank lines are not content, so its item ends at its last line")
    func indentedCodeBlankLines() {
        #expect(tree("-     code\n\n\nb") == """
            document @1:1-4:2
              list bullet '-' tight @1:1-1:11
                item @1:1-1:11
                  code_block "" "code\\n" @1:7-1:11
              paragraph @4:1-4:2
                text "b" @4:1-4:2

            """)
    }

    @Test("a link reference definition is content, though it leaves no block")
    func definitionOnly() {
        #expect(tree("- [a]: /u\n\nb") == """
            document @1:1-3:2
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """)
        #expect(tree("> [a]: /u  \n") == """
            document @1:1-1:12
              block_quote @1:1-1:10

            """)
    }

    @Test("a task list item marker is content, though it leaves no block")
    func taskItemMarkerOnly() {
        #expect(tree("- [ ]  \n\nb", options: .tasklist) == """
            document @1:1-3:2
              list bullet '-' tight @1:1-1:6
                tasklist unchecked @1:1-1:6
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """)
    }

    @Test("a footnote definition ends at its last content byte, before blank lines")
    func footnoteDefinition() {
        #expect(tree("[^a]: A\n\nb[^a]", options: .footnotes) == """
            document @1:1-3:6
              paragraph @3:1-3:6
                text "b" @3:1-3:2
                footnote_reference "1" @3:2-3:6
              footnote_definition "a" @1:1-1:8
                paragraph @1:7-1:8
                  text "A" @1:7-1:8

            """)
        #expect(tree("b[^a]\n\n[^a]: A\n\n    B  \n\n\n", options: .footnotes) == """
            document @1:1-7:1
              paragraph @1:1-1:6
                text "b" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              footnote_definition "a" @3:1-5:6
                paragraph @3:7-3:8
                  text "A" @3:7-3:8
                paragraph @5:5-5:6
                  text "B" @5:5-5:6

            """)
    }

    @Test("an empty footnote definition ends past its `[^label]:`")
    func emptyFootnoteDefinition() {
        #expect(tree("[^a]:  \n\nb[^a]", options: .footnotes) == """
            document @1:1-3:6
              paragraph @3:1-3:6
                text "b" @3:1-3:2
                footnote_reference "1" @3:2-3:6
              footnote_definition "a" @1:1-1:6

            """)
    }
}
