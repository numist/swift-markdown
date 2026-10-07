/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Footnote parsing")
struct FootnoteParsingTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    @Test
    func simpleReferenceAndDefinition() {
        #expect(TreeDump.dump("see [^a]\n\n[^a]: note\n", options: Self.options) == """
            document
              paragraph
                text "see "
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "note"

            """)
    }

    /// A footnote definition is a block container: a paragraph inside it continues lazily across a
    /// following non-indented line (cmark: def prefix fails, the open paragraph continues).
    @Test
    func definitionLazyContinuation() {
        #expect(TreeDump.dump("[^a]: text\nlazy line\n\nsee [^a]\n", options: Self.options) == """
            document
              paragraph
                text "see "
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "text"
                  softbreak
                  text "lazy line"

            """)
    }
}
