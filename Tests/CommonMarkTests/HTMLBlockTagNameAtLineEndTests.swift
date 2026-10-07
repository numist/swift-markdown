/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Under HTML block start condition 6 (HTML blocks) the tag name may be followed by the end of the line, so `<div` alone
/// on a line opens an HTML block.
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
