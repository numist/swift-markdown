/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline constructs whose label or title continues onto the next line of a block quote paragraph, past the
/// continuation line's `>` marker.
@Suite("Labels and titles across a block quote line")
struct BlockQuoteLineJoinScanTests {

    /// A link label may contain a line ending (spec "Links"), so an inline attribute's reference label continues
    /// onto the next line and matches the definition whose label is the same after normalization.
    @Test("an inline attribute's reference label continues onto the next line")
    func attributeReferenceLabel() {
        #expect(TreeDump.dump("> x ^[a][b\n> c]\n\n^[b c]: k", options: [.attributes, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:10
              block_quote @1:1-2:5
                paragraph @1:3-2:5
                  text "x " @1:3-1:5
                  attribute "k" @1:5-2:5
                    text "a" @1:7-1:8

            """)
    }

    /// A link title may span lines (spec "Links"), and a backslash before punctuation in it is an escape (spec
    /// "Backslash escapes").
    @Test("a link title with an escaped quote continues onto the next line")
    func linkTitleWithEscape() {
        #expect(TreeDump.dump("> x [a](b \"c\n> d\\\"e\")", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:9
              block_quote @1:1-2:9
                paragraph @1:3-2:9
                  text "x " @1:3-1:5
                  link "b" "c\\nd\\"e" @1:5-2:9
                    text "a" @1:6-1:7

            """)
    }

    /// A link title that is never closed is no title (spec "Links"), so the bracket and parenthesis stay text.
    @Test("an unclosed link title continuing onto the next line forms no link")
    func unclosedLinkTitle() {
        #expect(TreeDump.dump("> x [a](b \"c\n> d)", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-2:5
              block_quote @1:1-2:5
                paragraph @1:3-2:5
                  text "x [a](b \\"c" @1:3-1:13
                  softbreak @-
                  text "d)" @2:3-2:5

            """)
    }
}
