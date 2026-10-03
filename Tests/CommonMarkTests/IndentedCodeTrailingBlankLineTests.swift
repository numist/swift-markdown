/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An indented code block whose last line holds only whitespace beyond the code indent. Trailing blank lines are not
/// part of an indented code block (CommonMark §4.4), so the whitespace-only line is dropped from the body.
@Suite("Indented code trailing whitespace-only line")
struct IndentedCodeTrailingBlankLineTests {

    @Test("a trailing whitespace-only line is dropped from the body")
    func trailingWhitespaceLineDropped() throws {
        #expect(try CmarkTreeDump.dump("\t a\n\t  \n", options: []) == """
            document
              code_block "" " a\\n"

            """)
    }
}
