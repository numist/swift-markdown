/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for lines that open or continue many nested containers.
///
/// Each container marker on a line is placed by its column, which a tab makes depend on everything before it on the
/// line. Measuring each marker's column from the start of the line makes a line of `n` nested markers cost `n`
/// measurements of up to `n` bytes each.
@Suite("Lines of nested container markers parse in linear time")
struct NestedContainerLineParseTimeTests {

    @Test("nested block quotes hold their paragraph")
    func blockQuoteTree() {
        #expect(TreeDump.dump(">>\t> a", options: []) == """
            document
              block_quote
                block_quote
                  block_quote
                    paragraph
                      text "a"

            """)
    }

    /// A quote opened after a tab starts at its `>`, whatever the tab expands to.
    @Test("nested block quotes after tabs start at their markers")
    func blockQuoteRanges() {
        #expect(TreeDump.dump(">\t>\t> a", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-1:8
              block_quote @1:1-1:8
                block_quote @1:3-1:8
                  block_quote @1:5-1:8
                    paragraph @1:7-1:8
                      text "a" @1:7-1:8

            """)
    }
}
