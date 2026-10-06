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
        CmarkTreeDump.dump(source, options: options, sourceRanges: true)
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

    /// With `.cmarkBugCompatibility`, a reference whose `]` is on a later line resolves by the label bytes cmark
    /// captures (`abc`), and spans from its `[` on line 1 to just past its `]` on line 2. cmark-gfm starts it at
    /// `@2:1`, the start of the closing line.
    @Test("a reference resolved across a line break spans both lines")
    func crossLineReference() {
        #expect(tree("[^abcdef\nxxxxx]\n\n[^abc]: d", options: Self.opts.union(.cmarkBugCompatibility)) == """
            document @1:1-4:10
              paragraph @1:1-2:7
                footnote_reference "1" @1:1-2:7
              footnote_definition "abc" @4:1-4:10
                paragraph @4:9-4:10
                  text "d" @4:9-4:10

            """)
    }

    /// With `.cmarkBugCompatibility`, an escaped caret reference resolves by the label bytes cmark captures past the
    /// backslash (`abc`), and spans from its `[` to just past its `]`. cmark-gfm starts it at `@2:1`, the start of
    /// the closing line.
    @Test("an escaped-caret reference spans its brackets")
    func escapedCaretReference() {
        #expect(tree("[\\^abcdef\nxxxxx]\n\n[^abc]: d", options: Self.opts.union(.cmarkBugCompatibility)) == """
            document @1:1-4:10
              paragraph @1:1-2:7
                footnote_reference "1" @1:1-2:7
              footnote_definition "abc" @4:1-4:10
                paragraph @4:9-4:10
                  text "d" @4:9-4:10

            """)
    }

    /// The `![` opener of an escaped-caret reference is consumed whole, so the reference spans from the `!`.
    @Test("an image-shaped escaped-caret reference spans from its `!`")
    func imageShapedEscapedCaretReference() {
        #expect(tree("![\\^abcdef\nxxxxx]\n\n[^abc]: d", options: Self.opts.union(.cmarkBugCompatibility)) == """
            document @1:1-4:10
              paragraph @1:1-2:7
                footnote_reference "1" @1:1-2:7
              footnote_definition "abc" @4:1-4:10
                paragraph @4:9-4:10
                  text "d" @4:9-4:10

            """)
    }
}
