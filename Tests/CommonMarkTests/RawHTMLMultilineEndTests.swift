/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of raw HTML that spans a line ending, such as `<foo\nbar>`.
@Suite("Source ranges of raw HTML across a line ending")
struct RawHTMLMultilineEndTests {

    @Test("raw HTML across a line ending ends just past its `>`")
    func twoLineEndsPastBracket() {
        #expect(TreeDump.dump("<foo\nbar>", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:5
              paragraph @1:1-2:5
                html_inline "<foo\\nbar>" @1:1-2:5

            """)
    }

    @Test("raw HTML across a line ending between text ends just past its `>`")
    func midTextTwoLineEndsPastBracket() {
        #expect(TreeDump.dump("x<a\nb>y", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              paragraph @1:1-2:4
                text "x" @1:1-1:2
                html_inline "<a\\nb>" @1:2-2:3
                text "y" @2:3-2:4

            """)
    }

    @Test("single-line raw HTML ends just past its `>`")
    func singleLineEndsPastBracket() {
        #expect(TreeDump.dump("a <foo> b", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "a " @1:1-1:3
                html_inline "<foo>" @1:3-1:8
                text " b" @1:8-1:10

            """)
    }
}
