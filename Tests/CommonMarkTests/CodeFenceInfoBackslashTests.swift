/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A fenced code block info string `\a&amp;`: a backslash before a non-punctuation character is a literal backslash
/// (CommonMark §2.4), while the entity reference after it is decoded.
@Suite("Code fence info string with a literal backslash")
struct CodeFenceInfoBackslashTests {

    @Test(
        "a backslash before a letter stays literal and the entity decodes",
        arguments: [MarkdownDocument.ParseOptions(), [.cmarkBugCompatibility]]
    )
    func literalBackslash(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("```\\a&amp;\nx\n```\n", options: mode) == """
            document
              code_block "\\\\a&" "x\\n"

            """)
    }
}
