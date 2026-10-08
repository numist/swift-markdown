/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// HTML block start condition 5 (HTML blocks) is the string `<![CDATA[`, matched case-sensitively. `<![cdata[` and
/// `<![CDAtA[` meet no start condition, since condition 4 needs an uppercase ASCII letter after `<!`, so they are
/// paragraphs.
@Suite("HTML block CDATA start condition case")
struct HTMLBlockCDATAStartCaseTests {

    private static let options: MarkdownDocument.ParseOptions = []

    /// The concatenated literal content of `node` and its descendants in document order.
    private func allText(_ node: borrowing MarkdownNode) -> String {
        var out = ""
        if let lit = node.literal() { out += lit }
        node.children.forEach { out += allText($0) }
        return out
    }

    /// The document's first block: its kind and its literal text without a trailing line ending, which an HTML block's
    /// content has and a paragraph's text does not.
    private func firstBlock(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (kind: MarkdownNode.Kind, text: String) {
        let found: (MarkdownNode.Kind, String)? =
            MarkdownDocument.withParsedDocument(src, options: options) { doc in
                var first: (MarkdownNode.Kind, String)? = nil
                doc.root.children.forEach { child in
                    if first == nil { first = (child.kind, allText(child)) }
                }
                return first
            }
        let block = try #require(found, "fixture vacuous: no block parsed for \(src.debugDescription)")
        let text = block.1.hasSuffix("\n") ? String(block.1.dropLast()) : block.1
        return (block.0, text)
    }

    @Test("`<![CDAtA[` (lowercase t) is a paragraph")
    func mixedCaseIsParagraph() throws {
        let block = try firstBlock("<![CDAtA[", options: Self.options)
        #expect(block.kind == .paragraph)
        #expect(block.text == "<![CDAtA[")
    }

    @Test("`<![cdata[` (all lowercase) is a paragraph")
    func lowercaseIsParagraph() throws {
        let block = try firstBlock("<![cdata[", options: Self.options)
        #expect(block.kind == .paragraph)
        #expect(block.text == "<![cdata[")
    }

    @Test("`<![CDATA[` opens an HTML block")
    func exactCaseOpensHTMLBlock() throws {
        let block = try firstBlock("<![CDATA[", options: Self.options)
        #expect(block.kind == .htmlBlock)
        #expect(block.text == "<![CDATA[")
    }

    @Test("`<![CDATAx` (no trailing bracket) is a paragraph")
    func noTrailingBracket() throws {
        let block = try firstBlock("<![CDATAx", options: Self.options)
        #expect(block.kind == .paragraph)
        #expect(block.text == "<![CDATAx")
    }

    @Test("`<!x` (lowercase after `<!`) is a paragraph")
    func lowercaseAfterBang() throws {
        let block = try firstBlock("<!x", options: Self.options)
        #expect(block.kind == .paragraph)
        #expect(block.text == "<!x")
    }

    @Test("`<!DOCTYPE html>` meets start condition 4 and opens an HTML block")
    func type4Declaration() throws {
        let block = try firstBlock("<!DOCTYPE html>", options: Self.options)
        #expect(block.kind == .htmlBlock)
        #expect(block.text == "<!DOCTYPE html>")
    }
}
