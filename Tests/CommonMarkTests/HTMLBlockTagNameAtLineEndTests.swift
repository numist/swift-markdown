/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A type-6 HTML block start whose tag name runs to the end of the line, `<div` with nothing after it. The tag name may be
/// followed by whitespace, `>`, `/>` or the line end (cmark's `html_block_start` scanner), so the line opens an HTML block.
@Suite("HTML block tag name at the line end")
struct HTMLBlockTagNameAtLineEndTests {

    @Test("a tag name ending the line opens an HTML block")
    func opensHTMLBlock() {
        #expect(TreeDump.dump("<div\n", options: []) == """
            document
              html_block "<div\\n"

            """)
    }
}
