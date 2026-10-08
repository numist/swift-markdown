/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Link label, destination and title scanning (Links) over a paragraph whose lines are not contiguous
/// in the source, such as a block quote or list item body or a lazy continuation line. The paragraph's
/// content is a list of segments, and a label, destination or title may cross from one to the next.
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

    /// The inline children of `paragraph`, flattened to the fields the assertions below check. Reading
    /// each node's string content checks that every node's content is readable.
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

    /// The inlines of the first `.paragraph` within three levels of the root.
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

    @Test("block-quote lazy continuation with empty brackets is literal text")
    func blockQuoteEmptyBrackets() {
        MarkdownDocument.withParsedDocument(">a\n[]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["a", "[]b"])
            #expect(!inlines.hasLink)
        }
    }

    @Test("list-item lazy continuation with empty brackets is literal text")
    func listItemEmptyBrackets() {
        MarkdownDocument.withParsedDocument("- a\n[]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["a", "[]b"])
            #expect(!inlines.hasLink)
        }
    }

    @Test("block-quote lazy continuation with full brackets and no definition is literal text")
    func blockQuoteFullBracketsNoDefinition() {
        MarkdownDocument.withParsedDocument(">a\n[x]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["a", "[x]b"])
            #expect(!inlines.hasLink)
        }
    }

    /// `[x]` sits on a lazy continuation line of the block quote.
    @Test("shortcut reference resolves inside multi-segment content")
    func shortcutReferenceResolvesMultiSegment() {
        MarkdownDocument.withParsedDocument("[x]: /u\n\n>a\n[x]b") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .link, .text])
            #expect(inlines.texts == ["a", "b"])
            #expect(inlines.hasLink)
            #expect(inlines.linkURL == "/u")
            #expect(inlines.linkText == "x")
        }
    }

    /// An inline attribute's `(…)` may span a line ending, which is part of the attribute string.
    @Test("cross-line attribute form reconstructs the attribute (block quote)")
    func crossLineAttributeBlockQuote() {
        MarkdownDocument.withParsedDocument("> ^[a](\n> b)", options: [.attributes]) { doc in
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
    func crossLineAttributeListItem() {
        MarkdownDocument.withParsedDocument("- ^[a](\n  b)", options: [.attributes]) { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.attribute])
            #expect(inlines.attributeStrings == ["\nb"])
        }
    }

    /// A link label may span a line ending; matching normalizes `la\nbel` to `la bel` (Links).
    @Test("cross-line full-reference label resolves and consumes the trailing bracket")
    func crossLineFullReferenceResolves() {
        MarkdownDocument.withParsedDocument("[la bel]: /u\n\n>[t][la\nbel]") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.link])
            #expect(inlines.hasLink)
            #expect(inlines.linkURL == "/u")
            #expect(inlines.linkText == "t")
        }
    }

    @Test("cross-line full-reference label with no definition stays literal")
    func crossLineFullReferenceNoDefinition() {
        MarkdownDocument.withParsedDocument(">[t][la\nbel]") { doc in
            let inlines = Self.firstParagraphInlines(doc)
            #expect(inlines.kinds == [.text, .softBreak, .text])
            #expect(inlines.texts == ["[t][la", "bel]"])
            #expect(!inlines.hasLink)
        }
    }
}
