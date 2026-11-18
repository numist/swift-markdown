/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Code span opening backtick limit")
struct CodeSpanOpeningBacktickLimitTests {

    private func limits(_ maxBackticks: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxCodeSpanOpeningBackticks = maxBackticks
        return limits
    }

    @Test("a backtick string opens a code span at the limit but not past it")
    func boundary() {
        #expect(TreeDump.dump("```a```", options: [], limits: limits(3)) == """
            document
              paragraph
                code "a"

            """)
        #expect(TreeDump.dump("````a````", options: [], limits: limits(3)) == """
            document
              paragraph
                text "````a````"

            """)
    }

    @Test("the default limits parse a long backtick string as a code span")
    func defaultLimits() {
        #expect(TreeDump.dump("````a````", options: []) == """
            document
              paragraph
                code "a"

            """)
    }

    @Test("a code span within the limit follows a backtick string past it")
    func spanAfterLongString() {
        #expect(TreeDump.dump("````a``b``", options: [], limits: limits(3)) == """
            document
              paragraph
                text "````a"
                code "b"

            """)
        #expect(TreeDump.dump("````a```` ```b```", options: [], limits: limits(3)) == """
            document
              paragraph
                text "````a```` "
                code "b"

            """)
    }

    @Test("a backtick string past the limit after an unclosed opener stays text")
    func longStringAfterUnclosedOpener() {
        #expect(TreeDump.dump("``a ````b```` ```c```", options: [], limits: limits(3)) == """
            document
              paragraph
                text "``a ````b```` "
                code "c"

            """)
    }

    @Test("a code span across lines opens at the limit but not past it")
    func acrossLines() {
        #expect(TreeDump.dump("x ```a\nb```", options: [], limits: limits(3)) == """
            document
              paragraph
                text "x "
                code "a b"

            """)
        #expect(TreeDump.dump("x ````a\nb````", options: [], limits: limits(3)) == """
            document
              paragraph
                text "x ````a"
                softbreak
                text "b````"

            """)
    }

    @Test("a limit of 0 or below opens no code span", arguments: [0, -1, Int.min])
    func nonPositiveLimit(_ maxBackticks: Int) {
        #expect(TreeDump.dump("`a`", options: [], limits: limits(maxBackticks)) == """
            document
              paragraph
                text "`a`"

            """)
    }
}
