/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Footnote reference on a lazy continuation line")
struct LazyLineFootnoteReferenceTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes,
    ]

    @Test func footnoteReferenceResolves() {
        #expect(TreeDump.dump("- > a\n  2\u{0} [x] [^n]\n\n[^n]: z\n", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "a"
                      softbreak
                      text "2\u{FFFD} [x] "
                      footnote_reference "1"
              footnote_definition "n"
                paragraph
                  text "z"

            """)
    }
}
