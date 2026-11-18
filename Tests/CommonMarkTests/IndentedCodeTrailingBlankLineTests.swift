/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Indented code trailing whitespace-only line")
struct IndentedCodeTrailingBlankLineTests {

    @Test("a trailing whitespace-only line is dropped from the content")
    func trailingWhitespaceLineDropped() {
        #expect(TreeDump.dump("\t a\n\t  \n", options: []) == """
            document
              code_block "" " a\\n"

            """)
    }
}
