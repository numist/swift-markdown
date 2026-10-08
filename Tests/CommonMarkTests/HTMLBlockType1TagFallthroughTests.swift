/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Start condition 1 (HTML blocks) takes `script`, `pre` and `style`, followed by whitespace, `>` or the end of the
/// line, so a self-closing `<script/>` doesn't meet it. Start condition 7 excludes those tag names from its open tags,
/// so `<script/>` starts no HTML block. `textarea` is not a start condition 1 tag name, so `<textarea>` and
/// `<textarea/>` meet start condition 7.
@Suite("Self-closing type-1 tag names as HTML block starts")
struct HTMLBlockType1TagFallthroughTests {

    /// The concatenated literal content of `node` and its descendants in document order.
    private func allText(_ node: borrowing MarkdownNode) -> String {
        var out = ""
        if let lit = node.literal() { out += lit }
        node.children.forEach { out += allText($0) }
        return out
    }

    /// The document's top-level blocks as (kind, text) pairs, each text without a trailing line ending, which an HTML
    /// block's content has and a paragraph's text does not.
    private func blocks(
        _ src: String, options: MarkdownDocument.ParseOptions = []
    ) -> [(kind: MarkdownNode.Kind, text: String)] {
        let found: [(MarkdownNode.Kind, String)] =
            MarkdownDocument.withParsedDocument(src, options: options) { doc in
                var out: [(MarkdownNode.Kind, String)] = []
                doc.root.children.forEach { child in
                    out.append((child.kind, allText(child)))
                }
                return out
            }
        return found.map { block in
            let text = block.1.hasSuffix("\n") ? String(block.1.dropLast()) : block.1
            return (block.0, text)
        }
    }

    @Test("`<script/>` is a paragraph")
    func scriptSelfClosing() throws {
        let blocks = blocks("<script/>")
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(blocks.count == 1)
        #expect(first.kind == .paragraph)
        #expect(first.text == "<script/>")
    }

    @Test("`<pre/>`, `<style/>` are paragraphs", arguments: [
        "<pre/>", "<style/>",
    ])
    func otherType1TagsSelfClosing(_ src: String) throws {
        let blocks = blocks(src)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed for \(src.debugDescription)")
        #expect(blocks.count == 1)
        #expect(first.kind == .paragraph)
        #expect(first.text == src)
    }

    // MARK: Start condition 1

    @Test("bare `<script>`/`<pre>`/`<style>` open HTML blocks (type 1)", arguments: [
        "<script>", "<pre>", "<style>",
    ])
    func bareType1Tags(_ src: String) throws {
        let blocks = blocks(src)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed for \(src.debugDescription)")
        #expect(first.kind == .htmlBlock)
        #expect(first.text == src)
    }

    @Test("`<script ` (trailing space) opens an HTML block (type 1)")
    func scriptTrailingSpace() throws {
        let blocks = blocks("<script ")
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(first.kind == .htmlBlock)
        #expect(first.text == "<script ")
    }

    // MARK: Start condition 7

    @Test("`<scripting>` opens an HTML block (type 7, tag name is not `script`)")
    func scriptingNearMiss() throws {
        let blocks = blocks("<scripting>")
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(blocks.count == 1)
        #expect(first.kind == .htmlBlock)
        #expect(first.text == "<scripting>")
    }

    @Test("`<textarea>` and `<textarea/>` open HTML blocks (type 7)", arguments: [
        "<textarea>", "<textarea/>",
    ])
    func textareaOpensType7Block(_ src: String) throws {
        let blocks = blocks(src)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed for \(src.debugDescription)")
        #expect(blocks.count == 1)
        #expect(first.kind == .htmlBlock)
        #expect(first.text == src)
    }

    @Test("a `<textarea>` HTML block ends at a blank line (type 7)")
    func textareaBlockEndsAtBlankLine() {
        let blocks = blocks("<textarea>\n\nx</textarea>")
        #expect(blocks.map(\.kind) == [.htmlBlock, .paragraph])
        #expect(blocks.map(\.text) == ["<textarea>", "x</textarea>"])
    }

    @Test("a `</textarea>` doesn't end a type 1 HTML block")
    func textareaClosingTagDoesNotEndType1Block() {
        let blocks = blocks("<pre>\n</textarea>\nx")
        #expect(blocks.map(\.kind) == [.htmlBlock])
        #expect(blocks.map(\.text) == ["<pre>\n</textarea>\nx"])
    }

    // MARK: Interrupting a paragraph

    @Test("`<textarea>` doesn't interrupt a paragraph")
    func textareaDoesNotInterruptParagraph() {
        let blocks = blocks("foo\n<textarea>")
        #expect(blocks.map(\.kind) == [.paragraph])
        #expect(blocks.map(\.text) == ["foo<textarea>"])
    }


    @Test("`<script/>` doesn't interrupt a paragraph")
    func selfClosingDoesNotInterruptParagraph() throws {
        let blocks = blocks("foo\n<script/>")
        #expect(blocks.count == 1)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(first.kind == .paragraph)
        #expect(first.text.contains("foo"))
        #expect(first.text.contains("<script/>"))
    }

    @Test("bare `<script>` interrupts a paragraph (type 1)")
    func bareTagInterruptsParagraph() {
        let blocks = blocks("foo\n<script>")
        #expect(blocks.count == 2)
        #expect(blocks.first?.kind == .paragraph)
        #expect(blocks.last?.kind == .htmlBlock)
    }
}
