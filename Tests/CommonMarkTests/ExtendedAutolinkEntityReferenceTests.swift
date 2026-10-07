/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Entity reference after an extended autolink domain")
struct ExtendedAutolinkEntityReferenceTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink]

    /// An entity reference after an extended autolink's domain stays literal in the autolink.
    @Test
    func testGFMExtendedAutolinkWithoutBugCompatibility() {
        #expect(CmarkTreeDump.dump("http://a.a&amp;b", options: Self.options) == """
            document
              paragraph
                link "http://a.a&amp;b" ""
                  text "http://a.a&amp;b"

            """)
    }
}
