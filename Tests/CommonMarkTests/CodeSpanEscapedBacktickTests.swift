/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// An escaped backtick is literal, and the rest of its backtick string is a backtick string of its own, which may open
// a code span (Backslash escapes, Code spans).
@Suite("Code span openers around an escaped backtick")
struct CodeSpanEscapedBacktickTests {

    @Test("no code span forms when the only later run is longer")
    func literalBackticks() {
        #expect(TreeDump.dump("`\\``", options: []) == """
            document
              paragraph
                text "```"

            """)
    }

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
