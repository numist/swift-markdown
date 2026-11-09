/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// With tables enabled, a paragraph line holding `|` could be a table's header row (Tables). When no delimiter row
/// follows, the lines stay a paragraph and each line's text has the source range of its own line.
@Suite("Source ranges of the lines of a paragraph holding a pipe")
struct PipeParagraphLineRangeTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .tables, .strikethrough, .tasklist, .tableSpans]

    @Test("a pipe on an interior line spans 2:1-2:2")
    func interiorLinePipe() {
        #expect(TreeDump.dump("t\n|\n b", options: Self.options, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                text "t" @1:1-1:2
                softbreak @-
                text "|" @2:1-2:2
                softbreak @-
                text "b" @3:2-3:3

            """)
    }

    /// A `|` on line 1 has no delimiter row after it, so the paragraph continues.
    @Test("an interior line after a first-line pipe spans 2:1-2:4")
    func interiorLineAfterFirstLinePipe() {
        #expect(TreeDump.dump("|foo\nbar\n baz", options: Self.options, sourceRanges: true) == """
            document @1:1-3:5
              paragraph @1:1-3:5
                text "|foo" @1:1-1:5
                softbreak @-
                text "bar" @2:1-2:4
                softbreak @-
                text "baz" @3:2-3:5

            """)
    }
}
