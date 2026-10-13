/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A task list item whose first paragraph holds only its task list item marker.
///
/// The marker's line is not blank, so it opens a paragraph, the item's first block (List items), and the item does
/// not begin with a blank line. Blank lines after it keep the item open for a following line indented to its content
/// column, and a blank line between that paragraph and the next block makes the list loose (Lists).
@Suite("Task list item whose first paragraph is only its checkbox")
struct TaskItemCheckboxOnlyFirstBlockTests {

    static let options: MarkdownDocument.ParseOptions = [.tasklist]

    @Test(
        "a block after blank lines belongs to the item",
        arguments: [
            ("- [ ] \n\n\n  b\n", """
                document
                  list bullet '-' loose
                    tasklist unchecked
                      paragraph
                        text "b"

                """),
            ("- [x] \n\n\n  b\n", """
                document
                  list bullet '-' loose
                    tasklist checked
                      paragraph
                        text "b"

                """),
            ("- [ ] \n\n  b\n", """
                document
                  list bullet '-' loose
                    tasklist unchecked
                      paragraph
                        text "b"

                """),
            ("- [X]\t\n\n  b\n", """
                document
                  list bullet '-' loose
                    tasklist checked
                      paragraph
                        text "b"

                """),
            ("- a\n- [ ] \n\n\n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "a"
                    tasklist unchecked
                      paragraph
                        text "b"

                """),
            ("- a\n  - [ ] \n\n\n    b\n", """
                document
                  list bullet '-' tight
                    item
                      paragraph
                        text "a"
                      list bullet '-' loose
                        tasklist unchecked
                          paragraph
                            text "b"

                """),
            ("- a\n  - [x] \n\n    b\n", """
                document
                  list bullet '-' tight
                    item
                      paragraph
                        text "a"
                      list bullet '-' loose
                        tasklist checked
                          paragraph
                            text "b"

                """),
            ("> - [ ] \n>\n>\n>   b\n", """
                document
                  block_quote
                    list bullet '-' loose
                      tasklist unchecked
                        paragraph
                          text "b"

                """),
            ("> - [x] \n>\n>   b\n", """
                document
                  block_quote
                    list bullet '-' loose
                      tasklist checked
                        paragraph
                          text "b"

                """),
            ("1. [ ] \n\n\n   b\n", """
                document
                  list ordered start=1 delim=period loose
                    tasklist unchecked
                      paragraph
                        text "b"

                """),
            ("1. [x] \n\n   b\n", """
                document
                  list ordered start=1 delim=period loose
                    tasklist checked
                      paragraph
                        text "b"

                """),
            ("- [ ] \n \n \n  b\n", """
                document
                  list bullet '-' loose
                    tasklist unchecked
                      paragraph
                        text "b"

                """),
        ]
    )
    func blockAfterBlankLines(_ markdown: String, _ expected: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == expected, "\(markdown.debugDescription)")
    }

    @Test(
        "a line continuing the checkbox's paragraph leaves the list tight",
        arguments: [
            ("- [ ] \n  b\n", "tasklist unchecked"),
            ("- [x] \n  b\n", "tasklist checked"),
        ]
    )
    func continuationLineIsTight(_ markdown: String, _ item: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == """
            document
              list bullet '-' tight
                \(item)
                  paragraph
                    text "b"

            """, "\(markdown.debugDescription)")
    }

    @Test(
        "a nested checkbox-only item continued on the next line is tight",
        arguments: ["- a\n  - [ ] \n    b\n"]
    )
    func nestedContinuationLineIsTight(_ markdown: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                  list bullet '-' tight
                    tasklist unchecked
                      paragraph
                        text "b"

            """)
    }

    @Test(
        "a following item after blank lines loosens the list",
        arguments: ["- [ ] \n\n- b\n", "- [ ] \n\n\n- b\n"]
    )
    func followingItemAfterBlankLines(_ markdown: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == """
            document
              list bullet '-' loose
                tasklist unchecked
                item
                  paragraph
                    text "b"

            """, "\(markdown.debugDescription)")
    }

    @Test("a following item on the next line leaves the list tight")
    func followingItemOnNextLineIsTight() {
        #expect(TreeDump.dump("- [ ] \n- b\n", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist unchecked
                item
                  paragraph
                    text "b"

            """)
    }

    @Test(
        "a checkbox as the item's only content leaves the list tight",
        arguments: [
            ("- [ ] \n", "tasklist unchecked"),
            ("- [ ] \n\n", "tasklist unchecked"),
            ("- [ ] \n\n\n", "tasklist unchecked"),
            ("- [x] \n", "tasklist checked"),
            ("- [x] \n\n\n", "tasklist checked"),
        ]
    )
    func checkboxOnly(_ markdown: String, _ item: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == """
            document
              list bullet '-' tight
                \(item)

            """, "\(markdown.debugDescription)")
    }

    @Test(
        "an unindented line after the blank lines follows the list",
        arguments: ["- [ ] \n\nb\n", "- [ ] \n\n\nb\n"]
    )
    func unindentedLineFollowsList(_ markdown: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == """
            document
              list bullet '-' tight
                tasklist unchecked
              paragraph
                text "b"

            """, "\(markdown.debugDescription)")
    }
}
