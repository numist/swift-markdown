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
    /// `(attrs)` scanner used to build a single `Chunk` from virtual offsets, which for content that
    /// straddles a line join indexed the wrong buffer / ran past a segment and trapped. The fix
    /// defers a cross-line attribute (not representable as one contiguous chunk) to the no-match
    /// path, so the `^[…]` stays literal text. These pin the never-crash invariant; the exact
    /// deferred surface is the rewrite's (a cross-line attribute isn't reconstructed).
    @Test("cross-line attribute form does not crash (block quote)")
    func crossLineAttributeBlockQuoteNoCrash() throws {
        try MarkdownDocument.withParsedDocument("> ^[a](\n> b)") { doc in
            var isBlockQuote = false
            doc.root.children.forEach { block in
                if block.kind == .blockQuote { isBlockQuote = true }
            }
            #expect(isBlockQuote)
            let inlines = Self.firstParagraphInlines(doc)
            #expect(!inlines.kinds.contains(.attribute))
        }
    }

    @Test("cross-line attribute form does not crash (list item)")
    func crossLineAttributeListItemNoCrash() throws {
        try MarkdownDocument.withParsedDocument("- ^[a](\n  b)") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(!inlines.kinds.contains(.attribute))
        }
    }
}
