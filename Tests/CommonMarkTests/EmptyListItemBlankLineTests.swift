/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A list item can begin with at most one blank line (List items), and a line holding only spaces or tabs is a blank
/// line (Characters and lines), however far it is indented. So an item whose first line is empty ends at the next
/// such line, and indented content after it is a paragraph outside the list.
@Suite("Empty list item followed by a blank line")
struct EmptyListItemBlankLineTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: .sourcePosition, sourceRanges: true)
    }

    @Test("an empty line ends the item")
    func emptyLine() {
        #expect(tree("-\n\n  foo\n") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-1:2
                item @1:1-1:2
              paragraph @3:3-3:6
                text "foo" @3:3-3:6

            """)
    }

    @Test("a line of spaces reaching the content column ends the item")
    func spacesLine() {
        #expect(tree("-\n  \n  foo\n") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-1:2
                item @1:1-1:2
              paragraph @3:3-3:6
                text "foo" @3:3-3:6

            """)
    }

    @Test("a line holding a tab ends the item")
    func tabLine() {
        #expect(tree("-\n\t\n  foo\n") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-1:2
                item @1:1-1:2
              paragraph @3:3-3:6
                text "foo" @3:3-3:6

            """)
    }

    @Test("a nested empty item ends at a line of spaces reaching its content column")
    func nestedEmptyItem() {
        #expect(tree("- -\n    \n    foo\n") == """
            document @1:1-3:8
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  list bullet '-' tight @1:3-1:4
                    item @1:3-1:4
                  paragraph @3:5-3:8
                    text "foo" @3:5-3:8

            """)
    }
}
