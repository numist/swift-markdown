/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of a strikethrough (Strikethrough (extension)) whose opening and closing tildes may sit
/// on different lines. The range ends just past the closing tildes, on their own line.
@Suite("Multi-line strikethrough source ranges")
struct MultiLineStrikethroughEndTests {

    @Test("a two-line strikethrough ends on the closer's line")
    func twoLine() {
        #expect(TreeDump.dump("~~a\nb~~", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              paragraph @1:1-2:4
                strikethrough @1:1-2:4
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2

            """)
    }

    @Test("a three-line strikethrough ends on the closer's line")
    func threeLine() {
        #expect(TreeDump.dump("~~a\nbb\ncc~~", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              paragraph @1:1-3:5
                strikethrough @1:1-3:5
                  text "a" @1:3-1:4
                  softbreak @-
                  text "bb" @2:1-2:3
                  softbreak @-
                  text "cc" @3:1-3:3

            """)
    }

    @Test("a two-line single-tilde strikethrough ends on the closer's line")
    func singleTilde() {
        #expect(TreeDump.dump("~a\nb~", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                strikethrough @1:1-2:3
                  text "a" @1:2-1:3
                  softbreak @-
                  text "b" @2:1-2:2

            """)
    }

    @Test("a single-line strikethrough spans opener through closer")
    func singleLine() {
        #expect(TreeDump.dump("~~a~~", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-1:6
              paragraph @1:1-1:6
                strikethrough @1:1-1:6
                  text "a" @1:3-1:4

            """)
    }

    @Test("a strikethrough closing before a soft line break stays on its line")
    func closesBeforeSoftBreak() {
        #expect(TreeDump.dump("~~ab~~\ncd", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                strikethrough @1:1-1:7
                  text "ab" @1:3-1:5
                softbreak @-
                text "cd" @2:1-2:3

            """)
    }

    @Test("a two-line strikethrough nested in emphasis ends on the closer's line")
    func nestedInEmphasis() {
        #expect(TreeDump.dump("*~~a\nb~~*", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:5
              paragraph @1:1-2:5
                emph @1:1-2:5
                  strikethrough @1:2-2:4
                    text "a" @1:4-1:5
                    softbreak @-
                    text "b" @2:1-2:2

            """)
    }

    @Test("a strikethrough crossing a backslash hard line break ends on the closer's line")
    func backslashHardBreak() {
        #expect(TreeDump.dump("~~a\\\nb~~", options: [.strikethrough, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              paragraph @1:1-2:4
                strikethrough @1:1-2:4
                  text "a" @1:3-1:4
                  linebreak @-
                  text "b" @2:1-2:2

            """)
    }
}
