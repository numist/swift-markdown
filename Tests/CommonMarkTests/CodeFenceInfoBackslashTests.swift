/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// In a fenced code block's info string, a backslash before a non-punctuation character is a literal backslash
/// (Backslash escapes), while an entity reference is decoded (Entity and numeric character references).
@Suite("Code fence info string with a literal backslash")
struct CodeFenceInfoBackslashTests {

    @Test("a backslash before a letter stays literal and the entity decodes")
    func literalBackslash() {
        #expect(TreeDump.dump("```\\a&amp;\nx\n```\n", options: []) == """
            document
              code_block "\\\\a&" "x\\n"

            """)
    }
}
