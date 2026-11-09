/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of raw HTML that spans a line ending, such as `<foo\nbar>`. The end is half-open, one column past the
/// closing `>`, as for every other node.
@Suite("Multi-line inline HTML source ranges")
struct InlineHTMLMultilineEndTests {

    @Test("a two-line inline HTML span keeps the half-open end")
    func twoLineSpanHalfOpen() {
        #expect(TreeDump.dump("<foo\nbar>", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:5
              paragraph @1:1-2:5
                html_inline "<foo\\nbar>" @1:1-2:5

            """)
    }

    @Test("a mid-text two-line inline HTML span keeps the half-open end")
    func midTextTwoLineSpanHalfOpen() {
        #expect(TreeDump.dump("x<a\nb>y", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              paragraph @1:1-2:4
                text "x" @1:1-1:2
                html_inline "<a\\nb>" @1:2-2:3
                text "y" @2:3-2:4

            """)
    }

    @Test("a single-line inline HTML span keeps the half-open end")
    func singleLineSpanHalfOpen() {
        #expect(TreeDump.dump("a <foo> b", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "a " @1:1-1:3
                html_inline "<foo>" @1:3-1:8
                text " b" @1:8-1:10

            """)
    }
}
