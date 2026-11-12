/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An unindented lazy continuation line's text starts at its first byte, column 1.
@Suite("Lazy continuation line columns")
struct LazyContinuationLineColumnTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test("a middle lazy continuation line in a list item starts at column 1")
    func middleLineInListItem() {
        #expect(TreeDump.dump("- e\nc\ng", options: Self.options, sourceRanges: true) == """
            document @1:1-3:2
              list bullet '-' tight @1:1-3:2
                item @1:1-3:2
                  paragraph @1:3-3:2
                    text "e" @1:3-1:4
                    softbreak @-
                    text "c" @2:1-2:2
                    softbreak @-
                    text "g" @3:1-3:2

            """)
    }

    @Test("the last lazy continuation line in a list item starts at column 1")
    func lastLineInListItem() {
        #expect(TreeDump.dump("- e\nc", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-2:2
                item @1:1-2:2
                  paragraph @1:3-2:2
                    text "e" @1:3-1:4
                    softbreak @-
                    text "c" @2:1-2:2

            """)
        #expect(TreeDump.dump("- e\ncccccccccc", options: Self.options, sourceRanges: true) == """
            document @1:1-2:11
              list bullet '-' tight @1:1-2:11
                item @1:1-2:11
                  paragraph @1:3-2:11
                    text "e" @1:3-1:4
                    softbreak @-
                    text "cccccccccc" @2:1-2:11

            """)
    }
}
