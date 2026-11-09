/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Each inline of a multi-line paragraph has a source range on its own line, whether or not a line's initial
/// whitespace is stripped (Paragraphs).
@Suite("Inline source ranges on the later lines of a paragraph")
struct ParagraphLaterLineInlineRangeTests {

    @Test("text on an interior line lies on that line")
    func interiorLineText() {
        #expect(TreeDump.dump("a\nb\n c", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                text "a" @1:1-1:2
                softbreak @-
                text "b" @2:1-2:2
                softbreak @-
                text "c" @3:2-3:3

            """)
    }

    @Test("four-line paragraph keeps the final indented line's column")
    func fourLineFinalIndentedLine() {
        #expect(TreeDump.dump("a\nb\nc\n d", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-4:3
              paragraph @1:1-4:3
                text "a" @1:1-1:2
                softbreak @-
                text "b" @2:1-2:2
                softbreak @-
                text "c" @3:1-3:2
                softbreak @-
                text "d" @4:2-4:3

            """)
    }

    @Test("single-line emphasis on an interior line lies on that line")
    func interiorLineEmphasis() {
        #expect(TreeDump.dump("a\n*b*\n c", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                text "a" @1:1-1:2
                softbreak @-
                emph @2:1-2:4
                  text "b" @2:2-2:3
                softbreak @-
                text "c" @3:2-3:3

            """)
    }

    @Test("emphasis across a line ending ends on its closer's line")
    func multiLineEmphasis() {
        #expect(TreeDump.dump("*a\nb*\n c", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:3
              paragraph @1:1-3:3
                emph @1:1-2:3
                  text "a" @1:2-1:3
                  softbreak @-
                  text "b" @2:1-2:2
                softbreak @-
                text "c" @3:2-3:3

            """)
    }
}
