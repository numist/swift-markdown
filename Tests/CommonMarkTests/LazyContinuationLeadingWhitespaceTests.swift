/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph's raw content drops each line's initial whitespace (Paragraphs), including that of a lazy continuation
/// line, so a code span crossing onto one holds no whitespace from it.
@Suite("Leading whitespace of a lazy continuation line in a code span")
struct LazyContinuationLeadingWhitespaceTests {

    @Test("two leading spaces on a block quote's lazy continuation line are stripped")
    func codeSpanOnBlockQuoteLazyLineAfterTwoSpaces() {
        #expect(TreeDump.dump("> `x\n  y`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:5
              block_quote @1:1-2:5
                paragraph @1:3-2:5
                  code "x y" @1:3-2:5

            """)
    }

    @Test("the leading space on a list item's lazy continuation line is stripped")
    func codeSpanOnListItemLazyLine() {
        #expect(TreeDump.dump("- `x\n y`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:4
              list bullet '-' tight @1:1-2:4
                item @1:1-2:4
                  paragraph @1:3-2:4
                    code "x y" @1:3-2:4

            """)
    }

    @Test("the leading space on a block quote's lazy continuation line is stripped")
    func codeSpanOnBlockQuoteLazyLine() {
        #expect(TreeDump.dump("> `x\n y`", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:4
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  code "x y" @1:3-2:4

            """)
    }

    @Test("the leading space before plain text on a lazy continuation line is stripped")
    func textOnBlockQuoteLazyLine() {
        #expect(TreeDump.dump("> a\n b", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:3
              block_quote @1:1-2:3
                paragraph @1:3-2:3
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:2-2:3

            """)
    }
}
