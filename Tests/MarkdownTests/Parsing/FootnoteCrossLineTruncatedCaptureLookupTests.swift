/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Footnotes) import Markdown
import Testing

/// Definition lookup for a footnote-shaped bracket whose `]` lands on a later line, when cmark's
/// column-derived byte cut of the label splits a multi-byte scalar.
///
/// Ground truth is cmark-gfm. Its lookup key is the raw cut, case-folded by
/// `cmark_utf8proc_case_fold` (swift-cmark `src/utf8.c`), which replaces *each* byte of the truncated
/// scalar with its own U+FFFD. So a cut keeping two bytes of a three-byte scalar resolves to a
/// definition labelled `��`, not `�`, even though the unresolved bracket displays a single U+FFFD.
/// Without `.cmarkBugCompatibility` a footnote reference never spans a line, so the bracket stays
/// literal text around a soft break.
@Suite("Footnote cross-line truncated capture lookup")
struct FootnoteCrossLineTruncatedCaptureLookupTests {

    private static func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var options: ParseOptions = .footnotes
        if cmarkBugCompatible {
            options.insert(.cmarkBugCompatibility)
        }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static func resolved(_ label: String) -> String {
        "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"\(label)\" index: 1\n└─ FootnoteDefinition label: \"\(label)\"\n   └─ Paragraph\n      └─ Text \"n\""
    }

    @Test(arguments: [
        // Two bytes of U+2003 EM SPACE.
        ("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", "\u{FFFD}\u{FFFD}"),
        // Three bytes of U+1F600.
        ("[^\u{1F600}\nxxxxx]\n\n[^\u{FFFD}\u{FFFD}\u{FFFD}]: n", "\u{FFFD}\u{FFFD}\u{FFFD}"),
        // A complete scalar before two bytes of U+20AC.
        ("[^a\u{20AC}\nxxxxx]\n\n[^a\u{FFFD}\u{FFFD}]: n", "a\u{FFFD}\u{FFFD}"),
        // The escaped-caret form captures from just past the `^`.
        ("[\\^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", "\u{FFFD}\u{FFFD}"),
        // One byte of a scalar folds to a single U+FFFD.
        ("[^\u{FFFD}\nxxx]\n\n[^\u{FFFD}]: n", "\u{FFFD}"),
    ])
    func truncatedCaptureResolvesOneReplacementPerByte(_ markdown: String, _ label: String) {
        #expect(Self.surface(markdown) == Self.resolved(label))
    }

    @Test
    func truncatedCaptureMissesSingleReplacementDefinition() {
        #expect(Self.surface("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}]: n") == "Document\n└─ Paragraph\n   └─ Text \"[^\u{FFFD}]\"")
    }

    /// A definition whose own content is the cross-line bracket, continued lazily: the continuation
    /// line's leading space counts toward the cut, which keeps two bytes of the U+FFFD.
    @Test
    func lazyContinuationCaptureMissesItsOwnDefinition() {
        #expect(Self.surface("[^\u{0}]:[^\u{FFFD}\n \u{FFFD}]") == "Document")
    }

    @Test
    func withoutCompatibilityBracketStaysLiteral() {
        #expect(Self.surface("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}\u{FFFD}]: n", cmarkBugCompatible: false)
            == "Document\n└─ Paragraph\n   ├─ Text \"[^\u{2003}\"\n   ├─ SoftBreak\n   └─ Text \"xxxx]\"")
        #expect(Self.surface("[^\u{2003}\nxxxx]\n\n[^\u{FFFD}]: n", cmarkBugCompatible: false)
            == "Document\n└─ Paragraph\n   ├─ Text \"[^\u{2003}\"\n   ├─ SoftBreak\n   └─ Text \"xxxx]\"")
    }
}
