/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A task item's checkbox belongs to the item's opening line: cmark-gfm consumes it as the item opens
/// (`open_tasklist_item`, extensions/tasklist.c). When that line's paragraph holds nothing but a reference
/// definition, the paragraph disappears and a later paragraph becomes the item's first child, but that
/// paragraph's leading `[x]` is ordinary text and the item keeps the opening line's unchecked state.
@Suite("Task item whose opening paragraph is only a reference definition")
struct TaskListDefinitionOnlyOpeningLineTests {

    private static let compatibilityModes: [MarkdownDocument.ParseOptions] = [[], [.cmarkBugCompatibility]]

    @Test("a later paragraph's leading checkbox stays text", arguments: compatibilityModes)
    func laterCheckboxStaysText(mode: MarkdownDocument.ParseOptions) throws {
        #expect(try CmarkTreeDump.dump("- [ ] [a]: /u\n\n  [x]\n", options: mode.union(.tasklist)) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "[x]"

            """)
    }

    @Test("without tasklist, both paragraphs are text", arguments: compatibilityModes)
    func laterCheckboxWithoutTasklist(mode: MarkdownDocument.ParseOptions) throws {
        #expect(try CmarkTreeDump.dump("- [ ] [a]: /u\n\n  [x]\n", options: mode) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "[ ] [a]: /u"
                  paragraph
                    text "[x]"

            """)
    }

    @Test("a later checkbox followed by text stays text", arguments: compatibilityModes)
    func laterCheckboxWithTextStaysText(mode: MarkdownDocument.ParseOptions) throws {
        #expect(try CmarkTreeDump.dump("- [ ] [a]: /u\n\n  [x] foo\n", options: mode.union(.tasklist)) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "[x] foo"

            """)
    }

    @Test("without tasklist, a later checkbox followed by text stays text", arguments: compatibilityModes)
    func laterCheckboxWithTextWithoutTasklist(mode: MarkdownDocument.ParseOptions) throws {
        #expect(try CmarkTreeDump.dump("- [ ] [a]: /u\n\n  [x] foo\n", options: mode) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "[ ] [a]: /u"
                  paragraph
                    text "[x] foo"

            """)
    }

    @Test("a later paragraph shorter than a checkbox is kept whole", arguments: compatibilityModes)
    func laterShortParagraph(mode: MarkdownDocument.ParseOptions) throws {
        #expect(try CmarkTreeDump.dump("- [ ] [a]: /u\n\n  ab\n", options: mode.union(.tasklist)) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "ab"

            """)
    }

    @Test("without tasklist, a later short paragraph is kept whole", arguments: compatibilityModes)
    func laterShortParagraphWithoutTasklist(mode: MarkdownDocument.ParseOptions) throws {
        #expect(try CmarkTreeDump.dump("- [ ] [a]: /u\n\n  ab\n", options: mode) == """
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
        "a later checkbox line before a table stays a paragraph",
        arguments: compatibilityModes, [
            "- [ ] [a]: /u\n\n  [x]\nh|h\n  -|-\n",     // lazy header line
            "- [ ] [a]: /u\n\n  [x]\n  h|h\n  -|-\n",   // indented header line
        ]
    )
    func laterCheckboxBeforeTable(mode: MarkdownDocument.ParseOptions, source: String) throws {
        #expect(try CmarkTreeDump.dump(source, options: mode.union([.tasklist, .tables])) == """
            document
              list bullet '-' tight
                tasklist unchecked
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

    @Test(
        "without tasklist, a later checkbox line before a table stays a paragraph",
        arguments: compatibilityModes, [
            "- [ ] [a]: /u\n\n  [x]\nh|h\n  -|-\n",     // lazy header line
            "- [ ] [a]: /u\n\n  [x]\n  h|h\n  -|-\n",   // indented header line
        ]
    )
    func laterCheckboxBeforeTableWithoutTasklist(mode: MarkdownDocument.ParseOptions, source: String) throws {
        #expect(try CmarkTreeDump.dump(source, options: mode.union(.tables)) == """
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
