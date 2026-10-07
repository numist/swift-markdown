/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A lazy continuation line of a block quote inside a list item, holding a NUL and a footnote reference: the NUL is
/// U+FFFD and the footnote reference resolves (spec "Insecure characters"; GFM "Footnotes").
@Suite("Footnote reference on a lazy line")
struct LazyLineFootnoteReferenceTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes,
    ]

    /// Flag-off (spec-correct): the item's first block is a block quote, not a paragraph (GFM task list
    /// items), so the item has no checkbox and the lazy line keeps its `2` prefix ahead of the footnote
    /// reference, where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    @Test func footnoteReferenceFlagOff() {
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
