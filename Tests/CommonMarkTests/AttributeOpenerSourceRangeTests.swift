/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of text holding an inline-attribute opener `^[` that never closes. The opener stays literal text,
/// and the text spans it. Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Source ranges of an unclosed inline-attribute opener")
struct AttributeOpenerSourceRangeTests {

    private func tree(_ source: String) -> String {
        CmarkTreeDump.dump(source, options: [.sourcePosition], sourceRanges: true)
    }

    @Test("a lone opener's text spans it")
    func loneOpener() {
        #expect(tree("^[") == """
            document @1:1-1:3
              paragraph @1:1-1:3
                text "^[" @1:1-1:3

            """)
    }

    @Test("text that starts with an opener starts at it")
    func textStartingWithOpener() {
        #expect(tree("^[x") == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "^[x" @1:1-1:4

            """)
    }
}
