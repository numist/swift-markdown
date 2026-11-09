/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A code span spanning lines whose opening backtick string is on a lazy continuation line starts at that
/// backtick's own column.
@Suite("Multi-line code span opening on a lazy continuation line")
struct CodeSpanLazyContinuationRangeTests {

    @Test("code span opening on a block quote lazy continuation line is @2:1-3:2")
    func blockQuoteLazy() {
        #expect(TreeDump.dump("> o\n`\n`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:2
              block_quote @1:1-3:2
                paragraph @1:3-3:2
                  text "o" @1:3-1:4
                  softbreak @-
                  code " " @2:1-3:2

            """)
    }

    @Test("three-line code span on block quote lazy continuation lines is @2:1-4:2")
    func threeLineBlockQuoteLazy() {
        #expect(TreeDump.dump("> o\n`\nx\n`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-4:2
              block_quote @1:1-4:2
                paragraph @1:3-4:2
                  text "o" @1:3-1:4
                  softbreak @-
                  code "x" @2:1-4:2

            """)
    }

    @Test("code span opening on a list item lazy continuation line is @2:1-3:2")
    func listItemLazy() {
        #expect(TreeDump.dump("- o\n`\n`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:2
              list bullet '-' tight @1:1-3:2
                item @1:1-3:2
                  paragraph @1:3-3:2
                    text "o" @1:3-1:4
                    softbreak @-
                    code " " @2:1-3:2

            """)
    }

    @Test("code span opening after `> ` and closing on a lazy continuation line is @2:3-3:2")
    func matchedThenLazy() {
        #expect(TreeDump.dump("> o\n> `\n`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:2
              block_quote @1:1-3:2
                paragraph @1:3-3:2
                  text "o" @1:3-1:4
                  softbreak @-
                  code " " @2:3-3:2

            """)
    }

    @Test("top-level multi-line code span is @2:1-3:2")
    func topLevel() {
        #expect(TreeDump.dump("o\n`\n`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:2
              paragraph @1:1-3:2
                text "o" @1:1-1:2
                softbreak @-
                code " " @2:1-3:2

            """)
    }
}
