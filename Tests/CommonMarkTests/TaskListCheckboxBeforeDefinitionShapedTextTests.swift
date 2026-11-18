/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("List item whose opening line is a checkbox before definition-shaped text")
struct TaskListCheckboxBeforeDefinitionShapedTextTests {

    @Test("without tasklist, both paragraphs are text")
    func laterCheckboxWithoutTasklist() {
        #expect(TreeDump.dump("- [ ] [a]: /u\n\n  [x]\n", options: []) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "[ ] [a]: /u"
                  paragraph
                    text "[x]"

            """)
    }

    @Test("without tasklist, a later checkbox followed by text stays text")
    func laterCheckboxWithTextWithoutTasklist() {
        #expect(TreeDump.dump("- [ ] [a]: /u\n\n  [x] foo\n", options: []) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "[ ] [a]: /u"
                  paragraph
                    text "[x] foo"

            """)
    }

    @Test("without tasklist, a later short paragraph is text")
    func laterShortParagraphWithoutTasklist() {
        #expect(TreeDump.dump("- [ ] [a]: /u\n\n  ab\n", options: []) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "[ ] [a]: /u"
                  paragraph
                    text "ab"

            """)
    }

    @Test(
        "without tasklist, a later checkbox line before a table stays a paragraph",
        arguments: [
            "- [ ] [a]: /u\n\n  [x]\nh|h\n  -|-\n",
            "- [ ] [a]: /u\n\n  [x]\n  h|h\n  -|-\n",
        ]
    )
    func laterCheckboxBeforeTableWithoutTasklist(source: String) {
        #expect(TreeDump.dump(source, options: .tables) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "[ ] [a]: /u"
                  paragraph
                    text "[x]"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "h"
                      table_cell align=none colspan=1 rowspan=1
                        text "h"

            """)
    }
}

// `[ ] [a]: /u` does not begin with a link reference definition, so `[a]: /u` is the text of the item's first
// paragraph.
@Suite("Task list item whose first paragraph holds a definition-shaped remainder")
struct TaskListDefinitionShapedRemainderTests {
    @Test("a later paragraph's leading checkbox is text")
    func laterCheckboxIsText() {
        #expect(TreeDump.dump("- [ ] [a]: /u\n\n  [x] foo\n", options: .tasklist) == """
            document
              list bullet '-' loose
                tasklist unchecked
                  paragraph
                    text "[a]: /u"
                  paragraph
                    text "[x] foo"

            """)
    }

    @Test("a later checkbox line before a table is a paragraph")
    func laterCheckboxBeforeTable() {
        #expect(TreeDump.dump("- [ ] [a]: /u\n\n  [x]\n  h|h\n  -|-\n", options: [.tasklist, .tables]) == """
            document
              list bullet '-' loose
                tasklist unchecked
                  paragraph
                    text "[a]: /u"
                  paragraph
                    text "[x]"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "h"
                      table_cell align=none colspan=1 rowspan=1
                        text "h"

            """)
    }
}
