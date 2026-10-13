/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Backtick openers after a backslash-escaped backtick (CommonMark §6.1, §6.3).
///
/// An escaped backtick is literal, and the backticks after it in the same run form an opener of their own, shorter
/// than the run a closer search from an earlier opener passed.
@Suite("Code span openers around an escaped backtick")
struct CodeSpanEscapedBacktickTests {

    /// The first opener finds no single backtick after it, and the backtick after the escaped one finds none either.
    @Test("no code span forms when the only later run is longer")
    func literalBackticks() {
        #expect(TreeDump.dump("`\\``", options: []) == """
            document
              paragraph
                text "```"

            """)
    }

    /// The first opener finds no single backtick after it; the two backticks after the escaped one close on `` `` ``.
    @Test("the rest of an escaped run opens a span that closes later")
    func restOfEscapedRunOpens() {
        #expect(TreeDump.dump("` \\```x``", options: []) == """
            document
              paragraph
                text "` `"
                code "x"

            """)
    }
}
