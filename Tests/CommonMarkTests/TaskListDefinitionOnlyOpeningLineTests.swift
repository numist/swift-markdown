/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Without `.tasklist`, `[ ] [a]: /u` does not begin with a link reference definition (Link reference
/// definitions), so it is the item's first paragraph and a later `[x]` is text.
@Suite("List item whose opening line is a checkbox before a definition")
struct TaskListDefinitionOnlyOpeningLineTests {

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

    @Test("without tasklist, a later short paragraph is kept whole")
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
            "- [ ] [a]: /u\n\n  [x]\nh|h\n  -|-\n",     // lazy header line
            "- [ ] [a]: /u\n\n  [x]\n  h|h\n  -|-\n",   // indented header line
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

/// `[ ] [a]: /u` does not begin with a link reference definition, so it is the item's first paragraph,
/// which begins with a task list item marker (Task list items (extension)); the later paragraph's
/// `[x]` is text.
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
