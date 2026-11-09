/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A code span that crosses a line ending ends just past its closing backtick string, on the line that
/// holds it.
@Suite("Code span across a line ending: end of source range")
struct CrossLineCodeSpanEndRangeTests {

    @Test("a two-line code span ends after its closing backtick")
    func codeSpanEndsAfterClosingBacktick() {
        #expect(TreeDump.dump("`a\nb`", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                code "a b" @1:1-2:3

            """)
    }

    @Test("a two-line code span closed after leading whitespace ends after its closing backtick")
    func codeSpanAfterLeadingWhitespaceEndsAfterClosingBacktick() {
        #expect(TreeDump.dump(" `\n `x", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              paragraph @1:2-2:4
                code " " @1:2-2:3
                text "x" @2:3-2:4

            """)
    }

    // MARK: - Text after the code span

    @Test("text after a two-line code span starts on the closing line")
    func followingTextOnClosingLine() {
        #expect(TreeDump.dump("`\n`8", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                code " " @1:1-2:2
                text "8" @2:2-2:3

            """)
    }
}
