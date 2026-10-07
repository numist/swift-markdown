/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Footnote labels follow the link label rules (Links): unescaped square brackets are not
/// allowed inside them, and a reference matches a definition when their labels are equal after
/// normalization, which collapses whitespace, line endings included.
@Suite("Footnote labels")
struct FootnoteLabelTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    @Test
    func definitionLabelWithEscapedBracket() {
        #expect(TreeDump.dump("[^\\]]: x\n\n[^\\]]", options: Self.options, sourceRanges: true) == """
            document @1:1-3:6
              paragraph @3:1-3:6
                footnote_reference "1" @3:1-3:6
              footnote_definition "\\\\]" @1:1-2:1
                paragraph @1:8-1:9
                  text "x" @1:8-1:9

            """)
    }

    @Test
    func referenceLabelSpanningLineEnding() {
        #expect(TreeDump.dump("[^\na]\n\n[^a]: x", options: Self.options, sourceRanges: true) == """
            document @1:1-4:8
              paragraph @1:1-2:3
                footnote_reference "1" @1:1-2:3
              footnote_definition "a" @4:1-4:8
                paragraph @4:7-4:8
                  text "x" @4:7-4:8

            """)
    }

    @Test
    func unresolvedReferenceLabelSpanningLineEndingIsText() {
        #expect(TreeDump.dump("[^\na]", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                text "[^" @1:1-1:3
                softbreak @-
                text "a]" @2:1-2:3

            """)
    }
}
