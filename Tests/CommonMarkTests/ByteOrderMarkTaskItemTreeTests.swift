/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A byte order mark at the start of a document is not content, so a list item on the first line is a task list item
/// exactly when it would be without the mark (Task list items (extension)). Line 1's columns count the mark's three
/// bytes, so with the mark a range on line 1 lies three columns later, and the document still starts at 1:1.
@Suite("Task list items on the first line after a byte order mark")
struct ByteOrderMarkTaskItemTreeTests {

    static let options: MarkdownDocument.ParseOptions = [.tasklist, .sourcePosition]

    /// A document without the mark, its tree, and its tree with the mark.
    static let cases: [(markdown: String, tree: String, treeWithMark: String)] = [
        ("- [x] a", """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                tasklist checked @1:1-1:8
                  paragraph @1:7-1:8
                    text "a" @1:7-1:8

            """, """
            document @1:1-1:11
              list bullet '-' tight @1:4-1:11
                tasklist checked @1:4-1:11
                  paragraph @1:10-1:11
                    text "a" @1:10-1:11

            """),
        ("- [ ] a", """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                tasklist unchecked @1:1-1:8
                  paragraph @1:7-1:8
                    text "a" @1:7-1:8

            """, """
            document @1:1-1:11
              list bullet '-' tight @1:4-1:11
                tasklist unchecked @1:4-1:11
                  paragraph @1:10-1:11
                    text "a" @1:10-1:11

            """),
        ("* [x] a", """
            document @1:1-1:8
              list bullet '*' tight @1:1-1:8
                tasklist checked @1:1-1:8
                  paragraph @1:7-1:8
                    text "a" @1:7-1:8

            """, """
            document @1:1-1:11
              list bullet '*' tight @1:4-1:11
                tasklist checked @1:4-1:11
                  paragraph @1:10-1:11
                    text "a" @1:10-1:11

            """),
        ("1. [x] a", """
            document @1:1-1:9
              list ordered start=1 delim=period tight @1:1-1:9
                tasklist checked @1:1-1:9
                  paragraph @1:8-1:9
                    text "a" @1:8-1:9

            """, """
            document @1:1-1:12
              list ordered start=1 delim=period tight @1:4-1:12
                tasklist checked @1:4-1:12
                  paragraph @1:11-1:12
                    text "a" @1:11-1:12

            """),
        ("  - [x] a", """
            document @1:1-1:10
              list bullet '-' tight @1:3-1:10
                tasklist checked @1:3-1:10
                  paragraph @1:9-1:10
                    text "a" @1:9-1:10

            """, """
            document @1:1-1:13
              list bullet '-' tight @1:6-1:13
                tasklist checked @1:6-1:13
                  paragraph @1:12-1:13
                    text "a" @1:12-1:13

            """),
        ("- [x] a\n- [x] b", """
            document @1:1-2:8
              list bullet '-' tight @1:1-2:8
                tasklist checked @1:1-1:8
                  paragraph @1:7-1:8
                    text "a" @1:7-1:8
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "b" @2:7-2:8

            """, """
            document @1:1-2:8
              list bullet '-' tight @1:4-2:8
                tasklist checked @1:4-1:11
                  paragraph @1:10-1:11
                    text "a" @1:10-1:11
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "b" @2:7-2:8

            """),
        ("- a\n- [x] b", """
            document @1:1-2:8
              list bullet '-' tight @1:1-2:8
                item @1:1-1:4
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "b" @2:7-2:8

            """, """
            document @1:1-2:8
              list bullet '-' tight @1:4-2:8
                item @1:4-1:7
                  paragraph @1:6-1:7
                    text "a" @1:6-1:7
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "b" @2:7-2:8

            """),
        ("\n- [x] a", """
            document @1:1-2:8
              list bullet '-' tight @2:1-2:8
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "a" @2:7-2:8

            """, """
            document @1:1-2:8
              list bullet '-' tight @2:1-2:8
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "a" @2:7-2:8

            """),
        ("a\n- [x] b", """
            document @1:1-2:8
              paragraph @1:1-1:2
                text "a" @1:1-1:2
              list bullet '-' tight @2:1-2:8
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "b" @2:7-2:8

            """, """
            document @1:1-2:8
              paragraph @1:4-1:5
                text "a" @1:4-1:5
              list bullet '-' tight @2:1-2:8
                tasklist checked @2:1-2:8
                  paragraph @2:7-2:8
                    text "b" @2:7-2:8

            """),
    ]

    @Test("without the mark", arguments: cases)
    func withoutByteOrderMark(_ testCase: (markdown: String, tree: String, treeWithMark: String)) {
        #expect(!testCase.markdown.hasPrefix("\u{FEFF}"))
        #expect(TreeDump.dump(testCase.markdown, options: Self.options, sourceRanges: true) == testCase.tree, "\(testCase.markdown.debugDescription)")
    }

    @Test("with the mark", arguments: cases)
    func withByteOrderMark(_ testCase: (markdown: String, tree: String, treeWithMark: String)) {
        let markdown = "\u{FEFF}" + testCase.markdown
        #expect(Array(markdown.utf8.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(TreeDump.dump(markdown, options: Self.options, sourceRanges: true) == testCase.treeWithMark, "\(markdown.debugDescription)")
    }
}
