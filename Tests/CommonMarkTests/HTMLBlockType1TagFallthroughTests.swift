/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// CommonMark HTML block start condition 1 opens a block for a line beginning with `<pre`,
/// `<script`, `<style`, or `<textarea` (case-insensitive) *followed by whitespace, `>`, or
/// end-of-line* — cmark's `_scan_html_block_start` type-1 branch is
/// `[<] ('script'|'pre'|'textarea'|'style') (spacechar | [>])` (swift-cmark `src/scanners.re`;
/// generated state `yy389` accepts only `0x09`–`0x0D`, space, or `>` after the tag name). A `/`
/// (as in `<script/>`) is NOT an accepted follow char, so the type-1 rule does not fire.
///
/// But cmark does not stop there: its scanner backtracks and blocks.c then tries
/// `scan_html_block_start_7`, and `<script/>` is a complete open tag followed only by end-of-line,
/// so it opens an HTML block of TYPE 7 (which — unlike type 1 — cannot interrupt a paragraph).
///
/// The rewrite combined the type-1/6/7 checks into one `matchHTMLBlockStart`. When the tag name
/// matched a type-1 tag but the follow char disqualified type 1, it returned `nil` immediately,
/// short-circuiting the type-7 fallthrough that cmark reaches by backtracking. So `<script/>` fell
/// through to a paragraph with inline HTML instead of an HTML block. These tests pin cmark's
/// behavior: a type-1 tag name with a non-type-1 follow char must still be considered for type 7.
///
/// HTML-block recognition is STRUCTURAL and spec-correct here, so this holds unconditionally (flag
/// OFF, the deliverable). The tests parse without `.sourcePosition`.
@Suite("HTML block type-1 tag name falls through to type 7")
struct HTMLBlockType1TagFallthroughTests {

    /// Concatenated literal content of `node` and its descendants (DFS). For a single-line HTML
    /// block this is the block body; for a paragraph it is the run of inline text.
    private func allText(_ node: borrowing MarkdownNode) -> String {
        var out = ""
        if let lit = node.literal() { out += lit }
        node.children.forEach { out += allText($0) }
        return out
    }

    /// The document's top-level blocks as (kind, text) pairs, each with a single trailing newline
    /// removed. cmark newline-terminates every HTML-block body (so `<script/>` yields the body
    /// `"<script/>\n"`) while paragraph text has none; stripping one trailing `\n` lets each test
    /// compare a block's meaningful content against the source it was given, uniformly across kinds.
    private func blocks(
        _ src: String, options: MarkdownDocument.ParseOptions = []
    ) throws -> [(kind: MarkdownNode.Kind, text: String)] {
        let found: [(MarkdownNode.Kind, String)] =
            try MarkdownDocument.withParsedDocument(src, options: options) { doc in
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

    // MARK: The finding — `<script/>` opens an HTML block (type 7 via fallthrough)

    @Test("`<script/>` opens an HTML block")
    func scriptSelfClosing() throws {
        let blocks = try blocks("<script/>")
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(blocks.count == 1)
        #expect(first.kind == .htmlBlock)
        #expect(first.text == "<script/>")
    }

    /// The other three type-1 tag names take the same fallthrough path when self-closed.
    @Test("`<pre/>`, `<style/>`, `<textarea/>` open HTML blocks", arguments: [
        "<pre/>", "<style/>", "<textarea/>",
    ])
    func otherType1TagsSelfClosing(_ src: String) throws {
        let blocks = try blocks(src)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed for \(src.debugDescription)")
        #expect(blocks.count == 1)
        #expect(first.kind == .htmlBlock)
        #expect(first.text == src)
    }

    // MARK: Type-1 controls (the follow char DOES qualify) — must stay HTML blocks

    @Test("bare `<script>`/`<pre>`/`<style>`/`<textarea>` open HTML blocks (type 1)", arguments: [
        "<script>", "<pre>", "<style>", "<textarea>",
    ])
    func bareType1Tags(_ src: String) throws {
        let blocks = try blocks(src)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed for \(src.debugDescription)")
        #expect(first.kind == .htmlBlock)
        #expect(first.text == src)
    }

    /// `<script ` — a space after the tag name — is the canonical type-1 follow char.
    @Test("`<script ` (trailing space) opens an HTML block (type 1)")
    func scriptTrailingSpace() throws {
        let blocks = try blocks("<script ")
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(first.kind == .htmlBlock)
        #expect(first.text == "<script ")
    }

    // MARK: Verified-not-guessed control — `<scripting>` is a type-7 HTML block too

    /// `<scripting>` is not a type-1 tag name (it is not exactly `script`), so type 1 never fires;
    /// but it is a complete open tag followed by end-of-line, so cmark opens a type-7 HTML block.
    /// This path never touched the type-1 early-return, so it must remain an HTML block after the
    /// fix — a guard that the fix did not narrow type-7 detection for near-miss tag names.
    @Test("`<scripting>` opens an HTML block (type 7, tag name is not `script`)")
    func scriptingNearMiss() throws {
        let blocks = try blocks("<scripting>")
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(blocks.count == 1)
        #expect(first.kind == .htmlBlock)
        #expect(first.text == "<scripting>")
    }

    // MARK: Over-broadening guard — type 7 cannot interrupt a paragraph, type 1 can

    /// The critical guard against fixing this by broadening type 1 to accept `/`. cmark opens
    /// `<script/>` only as type 7, and type 7 CANNOT interrupt an open paragraph, so `foo` then
    /// `<script/>` is one paragraph with inline HTML — not paragraph + HTML block. Broadening type 1
    /// to accept `/` would wrongly interrupt the paragraph here.
    @Test("`<script/>` does NOT interrupt a paragraph (stays inline)")
    func selfClosingDoesNotInterruptParagraph() throws {
        let blocks = try blocks("foo\n<script/>")
        #expect(blocks.count == 1)
        let first = try #require(blocks.first, "fixture vacuous: no block parsed")
        #expect(first.kind == .paragraph)
        #expect(first.text.contains("foo"))
        #expect(first.text.contains("<script/>"))
    }

    /// The positive counterpart: a bare `<script>` IS a type-1 start, and type 1 DOES interrupt a
    /// paragraph, so `foo` then `<script>` is a paragraph followed by a separate HTML block.
    @Test("bare `<script>` DOES interrupt a paragraph (type 1)")
    func bareTagInterruptsParagraph() throws {
        let blocks = try blocks("foo\n<script>")
        #expect(blocks.count == 2)
        #expect(blocks.first?.kind == .paragraph)
        #expect(blocks.last?.kind == .htmlBlock)
    }
}
