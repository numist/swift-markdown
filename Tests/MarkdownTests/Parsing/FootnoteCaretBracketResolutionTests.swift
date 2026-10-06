/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Footnotes) import Markdown
import Testing

/// Definition lookup for a footnote-shaped bracket whose caret is immediately followed by `[`
/// (`[^[…]`).
///
/// Ground truth is cmark-gfm. Its inline footnote branch (`handle_close_bracket`, swift-cmark
/// `src/inlines.c`) captures that bracket's label from the static `"^["` string the inline-attribute
/// opener produced, so a captured label of two or more bytes is `[`, a NUL, and whatever follows.
/// `cmark_map_lookup` (`src/map.c`) compares normalized labels with `strcmp`, which stops at that NUL,
/// so the reference resolves to a definition labelled `[` whatever the bracket holds - unless the
/// captured length exceeds the 1000-byte label cap. Without a `[` definition the bracket collapses to a
/// literal `[^[`. Without `.cmarkBugCompatibility` none of these brackets is a footnote reference.
@Suite("Footnote caret-bracket resolution")
struct FootnoteCaretBracketResolutionTests {

    private static func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var options: ParseOptions = .footnotes
        if cmarkBugCompatible {
            options.insert(.cmarkBugCompatibility)
        }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static let resolvedToBracketDefinition = "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"[\" index: 1\n└─ FootnoteDefinition label: \"[\"\n   └─ Paragraph\n      └─ Text \"n\""

    @Test(arguments: [
        "[^[]]\n\n[^[]: n",
        // The definition may precede the reference.
        "[^[]: n\n\n[^[]]",
        // Text inside or after the inner brackets doesn't change the lookup key.
        "[^[a]]\n\n[^[]: n",
        "[^[]a]\n\n[^[]: n",
        // A captured length of two measured across a line break, from per-line columns.
        "[^[]\nabcd]\n\n[^[]: n",
        "[^[\nabcd]]\n\n[^[]: n",
        // The longest captured label within the cap: 1000 bytes.
        "[^[" + String(repeating: "a", count: 998) + "]]\n\n[^[]: n",
    ])
    func resolvesToBracketDefinition(_ markdown: String) {
        #expect(Self.surface(markdown) == Self.resolvedToBracketDefinition)
    }

    @Test
    func imageShapedOpenerKeepsItsBang() {
        #expect(Self.surface("![^[]]\n\n[^[]: n")
            == "Document\n├─ Paragraph\n│  ├─ Text \"!\"\n│  └─ FootnoteReference label: \"[\" index: 1\n└─ FootnoteDefinition label: \"[\"\n   └─ Paragraph\n      └─ Text \"n\"")
    }

    @Test
    func enclosingBracketsStayLiteral() {
        #expect(Self.surface("[[^[]]]\n\n[^[]: n")
            == "Document\n├─ Paragraph\n│  ├─ Text \"[\"\n│  ├─ FootnoteReference label: \"[\" index: 1\n│  └─ Text \"]\"\n└─ FootnoteDefinition label: \"[\"\n   └─ Paragraph\n      └─ Text \"n\"")
    }

    @Test
    func enclosingLinkHoldsTheReference() {
        #expect(Self.surface("[[^[]]](/u)\n\n[^[]: n")
            == "Document\n├─ Paragraph\n│  └─ Link destination: \"/u\"\n│     └─ FootnoteReference label: \"[\" index: 1\n└─ FootnoteDefinition label: \"[\"\n   └─ Paragraph\n      └─ Text \"n\"")
    }

    @Test
    func numberedAfterAnEarlierReference() {
        #expect(Self.surface("[^a] [^[x]]\n\n[^a]: m\n\n[^[]: n")
            == "Document\n├─ Paragraph\n│  ├─ FootnoteReference label: \"a\" index: 1\n│  ├─ Text \" \"\n│  └─ FootnoteReference label: \"[\" index: 2\n├─ FootnoteDefinition label: \"a\"\n│  └─ Paragraph\n│     └─ Text \"m\"\n└─ FootnoteDefinition label: \"[\"\n   └─ Paragraph\n      └─ Text \"n\"")
    }

    /// A definition whose own content is the only reference to it is still referenced, so it's kept.
    @Test
    func definitionReferencingItselfIsKept() {
        #expect(Self.surface("[^[]:[^[]]")
            == "Document\n└─ FootnoteDefinition label: \"[\"\n   └─ Paragraph\n      └─ FootnoteReference label: \"[\" index: 1")
    }

    @Test
    func capturedLabelOverCapCollapses() {
        #expect(Self.surface("[^[" + String(repeating: "a", count: 999) + "]]\n\n[^[]: n")
            == "Document\n└─ Paragraph\n   └─ Text \"[^[\"")
    }

    @Test
    func withoutBracketDefinitionCollapses() {
        #expect(Self.surface("[^[]]\n\n[^[a]: n") == "Document\n└─ Paragraph\n   └─ Text \"[^[\"")
    }

    @Test
    func withoutCompatibilityBracketStaysLiteral() {
        #expect(Self.surface("[^[]]\n\n[^[]: n", cmarkBugCompatible: false)
            == "Document\n└─ Paragraph\n   └─ Text \"[^[]]\"")
        #expect(Self.surface("[^[]:[^[]]", cmarkBugCompatible: false) == "Document")
    }
}
