/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of footnote references. A reference spans the bracketed text it replaces, from its opener to just
/// past its `]`. Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Source ranges of footnote references")
struct FootnoteReferenceSourceRangeTests {

    private static let opts: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = opts) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    @Test("a reference spans its brackets")
    func reference() {
        #expect(tree("x [^a] y\n\n[^a]: z") == """
            document @1:1-3:8
              paragraph @1:1-1:9
                text "x " @1:1-1:3
                footnote_reference "1" @1:3-1:7
                text " y" @1:7-1:9
              footnote_definition "a" @3:1-3:8
                paragraph @3:7-3:8
                  text "z" @3:7-3:8

            """)
    }

    /// `![^a]` doesn't open an image, so the `!` stays text and the reference spans `[^a]`.
    @Test("an image-shaped reference spans its brackets after the `!`")
    func imageShapedReference() {
        #expect(tree("![^a]\n\n[^a]: z") == """
            document @1:1-3:8
              paragraph @1:1-1:6
                text "!" @1:1-1:2
                footnote_reference "1" @1:2-1:6
              footnote_definition "a" @3:1-3:8
                paragraph @3:7-3:8
                  text "z" @3:7-3:8

            """)
    }

    @Test("a reference in its own definition spans its brackets")
    func referenceInItsOwnDefinition() {
        #expect(tree("[^b]:[^b]") == """
            document @1:1-1:10
              footnote_definition "b" @1:1-1:10
                paragraph @1:6-1:10
                  footnote_reference "1" @1:6-1:10

            """)
    }

    /// A footnote reference's label is all the text between its brackets, so `abcdef xxxxx` matches no definition and
    /// the bracket stays text.
    @Test("a bracket whose label spans a line break and matches no definition is text")
    func crossLineUnmatchedLabelIsText() {
        #expect(tree("[^abcdef\nxxxxx]\n\n[^abc]: d") == """
            document @1:1-4:10
              paragraph @1:1-2:7
                text "[^abcdef" @1:1-1:9
                softbreak @-
                text "xxxxx]" @2:1-2:7

            """)
    }

    /// A backslash-escaped caret is a literal `^` (Backslash escapes), so the bracket is not a footnote reference.
    @Test("an escaped-caret bracket is text")
    func escapedCaretBracketIsText() {
        #expect(tree("[\\^abcdef\nxxxxx]\n\n[^abc]: d") == """
            document @1:1-4:10
              paragraph @1:1-2:7
                text "[^abcdef" @1:1-1:10
                softbreak @-
                text "xxxxx]" @2:1-2:7

            """)
    }

    /// A backslash-escaped caret is a literal `^` (Backslash escapes), so `![\^…]` is neither an image nor a footnote
    /// reference.
    @Test("an image-shaped escaped-caret bracket is text")
    func imageShapedEscapedCaretBracketIsText() {
        #expect(tree("![\\^abcdef\nxxxxx]\n\n[^abc]: d") == """
            document @1:1-4:10
              paragraph @1:1-2:7
                text "![^abcdef" @1:1-1:11
                softbreak @-
                text "xxxxx]" @2:1-2:7

            """)
    }
}
