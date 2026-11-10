/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of text on a paragraph continuation line indented to its list item's content column.
@Suite("Text source range on an indented continuation line")
struct IndentedContinuationTextRangeTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test("text on an indented continuation line starts at its own source column")
    func indentedContinuationKeepsSourceColumn() {
        #expect(TreeDump.dump(" - b\n   c\n  d", options: Self.options, sourceRanges: true) == """
            document @1:1-3:4
              list bullet '-' tight @1:2-3:4
                item @1:2-3:4
                  paragraph @1:4-3:4
                    text "b" @1:4-1:5
                    softbreak @-
                    text "c" @2:4-2:5
                    softbreak @-
                    text "d" @3:3-3:4

            """)
    }
}
