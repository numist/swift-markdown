/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Coverage for close-bracket / reference scanning over **multi-segment** inline content.
///
/// A paragraph whose lines aren't source-contiguous (a block-quote body, a list-item body, or a
/// lazy continuation) is parsed directly from a segment list, addressed by *virtual* offsets that
/// don't index any single buffer. The link/reference scanners (`matchLinkLabel`,
/// `matchLinkDestination`, `matchLinkTitle`) read a `Chunk` with raw single-buffer `readByte`, so
/// feeding them virtual offsets used to index the wrong buffer out of bounds and trap. These tests
/// pin the fix: the scans read real bytes in bounds (no crash) and produce the correct surface -
/// including a shortcut reference that genuinely resolves inside multi-segment content.
@Suite("Multi-segment link/reference scanning")
struct MultiSegmentLinkLabelTests {

    private struct Inlines {
        var kinds: [MarkdownNode.Kind] = []
        var texts: [String] = []
        var hasLink = false
        var linkURL: String?
        var linkText: String?
        var attributeStrings: [String] = []
    }

    /// The inline children of `paragraph`, flattened to the fields the assertions below check. Reads
    /// each node's string content (`literal`/`url`/`attributes`), which forces the arena/source
    /// materialization that a straddling multi-segment chunk would trap on - so a regression that
    /// forms a node over an unrepresentable range fails loudly here rather than silently.
    private static func paragraphInlines(_ paragraph: borrowing MarkdownNode) -> Inlines {
        var result = Inlines()
        paragraph.children.forEach { inline in
            result.kinds.append(inline.kind)
            if inline.kind == .text, let literal = inline.literal() {
                result.texts.append(literal)
            }
            if inline.kind == .attribute, let attrs = inline.attributes() {
                result.attributeStrings.append(attrs)
            }
            if inline.kind == .link {
                result.hasLink = true
                result.linkURL = inline.url()
                inline.children.forEach { child in
                    if child.kind == .text, result.linkText == nil {
                        result.linkText = child.literal()
                    }
                }
            }
        }
        return result
    }

    /// The inlines of the first `.paragraph` anywhere in the tree (descends through the block-quote /
    /// list / item wrappers these inputs produce; those never nest deeper than three levels).
    private static func firstParagraphInlines(_ doc: borrowing MarkdownDocument) -> Inlines {
        var result = Inlines()
        var found = false
        doc.root.children.forEach { a in
            if found { return }
            if a.kind == .paragraph { result = paragraphInlines(a); found = true; return }
            a.children.forEach { b in
                if found { return }
                if b.kind == .paragraph { result = paragraphInlines(b); found = true; return }
                b.children.forEach { c in
                    if found { return }
                    if c.kind == .paragraph { result = paragraphInlines(c); found = true }
                }
            }
        }
        return result
    }

    @Test("block-quote lazy continuation with empty brackets is literal text (no crash)")
    func blockQuoteEmptyBrackets() throws {
        try MarkdownDocument.withParsedDocument(">a\n[]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["a", "[]b"])
            #expect(!inlines.hasLink)
        }
    }

    @Test("list-item lazy continuation with empty brackets is literal text (no crash)")
    func listItemEmptyBrackets() throws {
        try MarkdownDocument.withParsedDocument("- a\n[]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["a", "[]b"])
            #expect(!inlines.hasLink)
        }
    }

    @Test("block-quote lazy continuation with full brackets and no definition is literal text (no crash)")
    func blockQuoteFullBracketsNoDefinition() throws {
        try MarkdownDocument.withParsedDocument(">a\n[x]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["a", "[x]b"])
            #expect(!inlines.hasLink)
        }
    }

    /// A shortcut reference inside multi-segment content that DOES resolve: the definition is at top
    /// level, the use `[x]` sits on the block quote's lazy-continuation line (so the paragraph is
    /// multi-segment) and its label lies within a single source segment. Proves the fix scans and
    /// resolves references, not merely avoids the crash.
    @Test("shortcut reference resolves inside multi-segment content")
    func shortcutReferenceResolvesMultiSegment() throws {
        try MarkdownDocument.withParsedDocument("[x]: /u\n\n>a\n[x]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .link, .text])
            #expect(inlines.texts == ["a", "b"])
            #expect(inlines.hasLink)
            #expect(inlines.linkURL == "/u")
            #expect(inlines.linkText == "x")
        }
    }

    /// The `^[…](attrs)` extended-attribute inline form scanned over multi-segment content. Its
    /// `(attrs)` interior straddles the interned-newline segment joining the two source lines. cmark
    /// reads its flattened paragraph buffer, so the interior newline is ordinary attribute content and
    /// the form resolves to an attribute whose string carries it. The scanner materializes the
    /// straddling interior into the arena (reading `attributes()` forces that materialization), so the
    /// attribute is reconstructed - matching the reference - rather than deferred to literal text.
    @Test("cross-line attribute form reconstructs the attribute (block quote)")
    func crossLineAttributeBlockQuote() throws {
        try MarkdownDocument.withParsedDocument("> ^[a](\n> b)") { doc in
            var isBlockQuote = false
            doc.root.children.forEach { block in
                if block.kind == .blockQuote { isBlockQuote = true }
            }
            #expect(isBlockQuote)
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.attribute])
            #expect(inlines.attributeStrings == ["\nb"])
        }
    }

    @Test("cross-line attribute form reconstructs the attribute (list item)")
    func crossLineAttributeListItem() throws {
        try MarkdownDocument.withParsedDocument("- ^[a](\n  b)") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.attribute])
            #expect(inlines.attributeStrings == ["\nb"])
        }
    }

    /// A NON-blank full-reference label that straddles the line join: cmark's `link_label` scans a flat
    /// buffer, so it crosses the soft break to the `]`, captures `la\nbel`, normalizes it to `la bel`,
    /// and resolves the full reference `[t][la\nbel]` - consuming the trailing bracket pair. The
    /// contiguous window can't image the straddling label, so this drives the cross-line label scan.
    @Test("cross-line full-reference label resolves and consumes the trailing bracket")
    func crossLineFullReferenceResolves() throws {
        try MarkdownDocument.withParsedDocument("[la bel]: /u\n\n>[t][la\nbel]") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.link])
            #expect(inlines.hasLink)
            #expect(inlines.linkURL == "/u")
            #expect(inlines.linkText == "t")
        }
    }

    /// The same cross-line full-reference shape with NO matching definition: cmark scans the label,
    /// fails the lookup, and rewinds to a literal `]` - both bracket pairs stay literal text. Confirms
    /// the cross-line scan doesn't spuriously consume the trailing label when the reference is unknown.
    @Test("cross-line full-reference label with no definition stays literal")
    func crossLineFullReferenceNoDefinition() throws {
        try MarkdownDocument.withParsedDocument(">[t][la\nbel]") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["[t][la", "bel]"])
            #expect(!inlines.hasLink)
        }
    }
}
