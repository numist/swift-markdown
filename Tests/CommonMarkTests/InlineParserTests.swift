/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Walk all inline children of the first paragraph (or heading) in the document, returning a compact `(kind, literal)` list. Useful for asserting inline parser output.
internal func paragraphInlines(_ doc: borrowing MarkdownDocument) -> [(kind: MarkdownNode.Kind, literal: String?)] {
    var out: [(MarkdownNode.Kind, String?)] = []
    let root = doc.root
    root.children.forEach { block in
        if block.kind.canAccumulateText {
            block.children.forEach { inline in
                out.append((inline.kind, inline.literal()))
            }
        }
    }
    return out.map { ($0.0, $0.1) }
}

@Suite("Inline parser - code spans")
struct CodeSpanTests {

    @Test("simple single-backtick code span")
    func singleBacktick() {
        let source = "`foo`"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines.count == 1)
        #expect(inlines[0].kind == .codeInline(backtickCount: 1))
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("multi-backtick fence allows interior backticks")
    func multiBacktick() {
        let source = "``foo `bar` baz``"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines.count == 1)
        #expect(inlines[0].kind == .codeInline(backtickCount: 2))
        #expect(inlines[0].literal == "foo `bar` baz")
        }
    }

    @Test("text before and after the code span")
    func surroundingText() {
        let source = "foo `code` bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        let texts = inlines.map { $0.literal }
        #expect(kinds == [.text, .codeInline(backtickCount: 1), .text])
        #expect(texts == ["foo ", "code", " bar"])
        }
    }

    @Test("unmatched opening backticks remain as text")
    func unmatchedBacktick() {
        let source = "`foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines.count == 1)
        #expect(inlines[0].kind == .text)
        #expect(inlines[0].literal == "`foo")
        }
    }

    @Test("mismatched fence lengths leave the line as text")
    func mismatchedLength() {
        let source = "`` foo `"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        // No close of length 2 → entire line stays as text.
        let kinds = inlines.map { $0.kind }
        #expect(!kinds.contains { if case .codeInline = $0 { return true } else { return false } })
        }
    }

    @Test("single space stripped from both ends when content is bracketed by spaces")
    func singleSpaceStripping() {
        let source = "` foo `"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].kind == .codeInline(backtickCount: 1))
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("only ONE space stripped per side")
    func oneSpacePerSide() {
        let source = "`  foo  `"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].kind == .codeInline(backtickCount: 1))
        #expect(inlines[0].literal == " foo ")
        }
    }

    @Test("all-space content is preserved (no stripping)")
    func allSpacesPreserved() {
        let source = "`  `"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].kind == .codeInline(backtickCount: 1))
        #expect(inlines[0].literal == "  ")
        }
    }

    @Test("code span with trailing space but no leading space - no stripping")
    func asymmetricSpaces() {
        let source = "`foo `"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "foo ")
        }
    }

    @Test("code span with three backticks each side")
    func threeBackticks() {
        let source = "```foo```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].kind == .codeInline(backtickCount: 3))
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("multiple code spans in a paragraph")
    func multipleSpans() {
        let source = "a `b` c `d` e"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .codeInline(backtickCount: 1), .text, .codeInline(backtickCount: 1), .text])
        }
    }

    @Test("greedy matching finds all valid spans after an unmatched longer run")
    func greedySpansAfterUnmatchedLongerRun() throws {
        // Spec-correct default: the unmatched opening two-backtick run
        // folds into leading text, then BOTH `b` and `d` form as code spans. cmark's per-subject
        // backtick-closer cache makes it MISS the trailing `d` span after the longer run scans to the
        // end (a stale-cache quirk); the deliverable finds
        // every valid span.
        let source = "``a`b`c`d`"
        try MarkdownDocument.withParsedDocument(source) { doc in
            let inlines = paragraphInlines(doc)
            let codeSpans = inlines.filter { if case .codeInline = $0.kind { return true } else { return false } }
            try #require(codeSpans.count == 2, "expected both `b` and `d` to form code spans, got \(inlines.map { $0.kind })")
            #expect(codeSpans.map { $0.literal } == ["b", "d"])
            #expect(inlines.map { $0.kind } == [
                .text,
                .codeInline(backtickCount: 1),
                .text,
                .codeInline(backtickCount: 1),
            ])
            #expect(inlines.map { $0.literal } == ["``a", "b", "c", "d"])
        }
    }

    @Test("code span inside a heading")
    func insideHeading() {
        let source = "# `foo` bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].kind == .codeInline(backtickCount: 1))
        #expect(inlines[0].literal == "foo")
        #expect(inlines[1].kind == .text)
        #expect(inlines[1].literal == " bar")
        }
    }

    @Test("multi-line span reconstructs its full content across a soft break")
    func multiLineSpanAcrossSoftBreak() {
        // `x` on line 1, ` y` on line 2 of one paragraph. A matched paragraph continuation strips its
        // leading whitespace, so the paragraph's content joins the two lines as `x\ny`; the code span
        // between the backticks normalizes the interior newline to a space, giving `x y`. The span's
        // bytes straddle the soft-break segment boundary of the (non-contiguous) multi-segment
        // paragraph, so the content can't be a zero-copy contiguous source slice - it must be
        // materialized from the joined segments (cmark reads the same joined paragraph buffer). Before
        // the fix the span read a single-segment window and truncated to `x  ` (dropping `y`, keeping
        // the stripped continuation space).
        let source = "`x\n y`"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].kind == .codeInline(backtickCount: 1))
        #expect(inlines[0].literal == "x y")
        }
    }
}

@Suite("Inline parser - line breaks")
struct LineBreakTests {

    @Test("plain newline becomes a soft break")
    func softBreak() {
        let source = "foo\nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .softBreak, .text])
        }
    }

    @Test("two trailing spaces before newline produce a hard break")
    func hardBreakSpaces() {
        let source = "foo  \nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .lineBreak, .text])
        // The trailing spaces are stripped from the preceding text.
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("backslash before newline produces a hard break")
    func hardBreakBackslash() {
        let source = "foo\\\nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .lineBreak, .text])
        // The trailing backslash is stripped from the preceding text.
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("single trailing space is not a hard break")
    func singleSpaceIsSoft() {
        let source = "foo \nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .softBreak, .text])
        // The trailing space is stripped from the preceding text.
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("3+ trailing spaces still produce a hard break")
    func manySpaces() {
        let source = "foo   \nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .lineBreak, .text])
        #expect(inlines[0].literal == "foo")
        }
    }

    @Test("multiple soft breaks in a paragraph")
    func multipleSoftBreaks() {
        let source = "a\nb\nc"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .softBreak, .text, .softBreak, .text])
        }
    }

    @Test("hard and soft breaks mixed")
    func mixed() {
        let source = "a  \nb\nc"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .lineBreak, .text, .softBreak, .text])
        }
    }
}

@Suite("Inline parser - HTML entities")
struct EntityTests {

    @Test("named: amp")
    func amp() {
        let source = "foo &amp; bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        // Adjacent text is coalesced into one node (cmark's consolidate_text_nodes).
        #expect(inlines.count == 1)
        #expect(inlines[0].literal == "foo & bar")
        }
    }

    @Test("named: lt and gt")
    func ltGt() {
        let source = "&lt;tag&gt;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let texts = inlines.compactMap { $0.literal }
        #expect(texts == ["<tag>"])
        }
    }

    @Test("named: copy → ©")
    func copyEntity() {
        let source = "&copy;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "©")
        }
    }

    @Test("named: hellip → …")
    func hellip() {
        let source = "wait&hellip;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let texts = inlines.compactMap { $0.literal }
        #expect(texts == ["wait…"])
        }
    }

    @Test("named: unknown entity stays as literal text")
    func unknownNamed() {
        let source = "&qwerty;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        // The whole sequence stays as one text node.
        #expect(inlines.count == 1)
        #expect(inlines[0].literal == "&qwerty;")
        }
    }

    @Test("numeric decimal")
    func numericDecimal() {
        let source = "&#42;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "*")
        }
    }

    @Test("numeric hex lowercase")
    func numericHexLower() {
        let source = "&#x2a;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "*")
        }
    }

    @Test("numeric hex uppercase X")
    func numericHexUpper() {
        let source = "&#X2A;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "*")
        }
    }

    @Test("numeric for non-ASCII codepoint")
    func numericNonASCII() {
        // &#x2026; → … (U+2026)
        let source = "&#x2026;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "…")
        }
    }

    @Test("numeric NUL is replaced with U+FFFD")
    func numericNUL() {
        let source = "&#0;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "\u{FFFD}")
        }
    }

    @Test("numeric out-of-range codepoint replaced with U+FFFD")
    func numericOutOfRange() {
        // 0x110000 is 1 above U+10FFFF (the max valid codepoint).
        let source = "&#x110000;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "\u{FFFD}")
        }
    }

    @Test("numeric with too many hex digits is not an entity")
    func numericTooManyDigits() {
        // 7 hex digits exceeds the spec's max of 6.
        let source = "&#x1100000;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "&#x1100000;")
        }
    }

    @Test("missing semicolon → not an entity")
    func missingSemicolon() {
        let source = "&amp not entity"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "&amp not entity")
        }
    }

    @Test("entity at start, middle, and end")
    func entityPositions() {
        let source = "&amp; mid &amp; end&amp;"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let texts = inlines.compactMap { $0.literal }
        #expect(texts == ["& mid & end&"])
        }
    }

    /// A valid entity on a paragraph's indented lazy-continuation line. The leading indent is
    /// stripped, so the paragraph's lines aren't source-contiguous and its content is
    /// *multi-segment* - addressed by virtual offsets that index no single buffer. The `&` scan
    /// must read real in-bounds bytes and still decode (`&amp;` → `&`) rather than trap.
    @Test("valid entity decodes on an indented lazy-continuation line (multi-segment)")
    func entityDecodesOnLazyContinuation() {
        let source = "k\n &amp;x"
        MarkdownDocument.withParsedDocument(source) { doc in
            let inlines = paragraphInlines(doc)
            let texts = inlines.compactMap { $0.literal }
            #expect(texts == ["k", "&x"])
        }
    }

    /// A non-matching `&` (no closing `;`) on the same multi-segment continuation line stays a
    /// literal `&` followed by literal `[`. Exercises the no-entity path, which must also stay in
    /// bounds for multi-segment content.
    @Test("non-entity `&` on an indented lazy-continuation line stays literal (multi-segment)")
    func nonEntityAmpersandOnLazyContinuation() {
        let source = "k\n &["
        MarkdownDocument.withParsedDocument(source) { doc in
            let inlines = paragraphInlines(doc)
            let texts = inlines.compactMap { $0.literal }
            #expect(texts == ["k", "&["])
        }
    }
}

@Suite("Inline parser - autolinks")
struct AutolinkTests {

    /// Pull the (kind, url, text-of-first-child) for the first link in the document's first paragraph. Returns nil for any of these if not found.
    private static func firstLink(_ doc: borrowing MarkdownDocument) -> (url: String?, text: String?) {
        var url: String?
        var text: String?
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link {
                    url = inline.url()
                    inline.children.forEach { child in
                        if child.kind == .text, text == nil {
                            text = child.literal()
                        }
                    }
                }
            }
        }
        return (url, text)
    }

    @Test("URI autolink: http")
    func uriHTTP() {
        let source = "<http://example.com>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines.count == 1)
        #expect(inlines[0].kind == .link)
        let info = Self.firstLink(doc)
        #expect(info.url == "http://example.com")
        #expect(info.text == "http://example.com")
        }
    }

    @Test("URI autolink: ftp")
    func uriFTP() {
        let source = "<ftp://files.example.org/foo>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "ftp://files.example.org/foo")
        }
    }

    @Test("URI autolink: custom scheme")
    func customScheme() {
        let source = "<x-custom:bar>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "x-custom:bar")
        }
    }

    @Test("URI autolink with surrounding text")
    func surroundingText() {
        let source = "before <https://swift.org> after"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .link, .text])
        }
    }

    @Test("autolink rejects whitespace in URI")
    func whitespaceRejected() {
        let source = "<http://example.com x>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(!kinds.contains(.link))
        }
    }

    @Test("scheme too short is not an autolink")
    func shortScheme() {
        let source = "<a:foo>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(!kinds.contains(.link))
        }
    }

    @Test("email autolink")
    func emailBasic() {
        let source = "<foo@bar.example.com>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "mailto:foo@bar.example.com")
        #expect(info.text == "foo@bar.example.com")
        }
    }

    @Test("email autolink with punctuation in local part")
    func emailWithPunct() {
        let source = "<f.o.o+bar@example.com>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "mailto:f.o.o+bar@example.com")
        }
    }

    @Test("email autolink with hyphen in domain")
    func emailHyphenDomain() {
        let source = "<a@b-c.example>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "mailto:a@b-c.example")
        }
    }

    @Test("invalid email: leading hyphen in domain label")
    func emailLeadingHyphenLabel() {
        let source = "<a@-bad.example>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(!kinds.contains(.link))
        }
    }

    @Test("`<` followed by non-autolink stays as text")
    func nonAutolink() {
        let source = "<not autolink"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        #expect(inlines[0].literal == "<not autolink")
        }
    }
}

@Suite("Inline parser - raw inline HTML")
struct InlineHTMLTests {

    /// Fetch the kind+literal of the first `.htmlInline` node in the first paragraph, or nil if none is present.
    private static func firstHTMLInline(_ doc: borrowing MarkdownDocument) -> String? {
        var out: String?
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .htmlInline, out == nil {
                    out = inline.literal()
                }
            }
        }
        return out
    }

    @Test("simple open tag")
    func simpleOpenTag() {
        let source = "a <b> c"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map { $0.kind }
        #expect(kinds == [.text, .htmlInline, .text])
        #expect(Self.firstHTMLInline(doc) == "<b>")
        }
    }

    @Test("open tag with attribute")
    func openTagWithAttribute() {
        let source = "x <a href=\"x.html\">"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<a href=\"x.html\">")
        }
    }

    @Test("open tag with multiple attributes (single, double, unquoted)")
    func openTagMultipleAttributes() {
        let source = "x <input type='text' name=foo value=\"v\">"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<input type='text' name=foo value=\"v\">")
        }
    }

    @Test("self-closing open tag")
    func selfClosingTag() {
        let source = "x <br />"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<br />")
        }
    }

    @Test("close tag")
    func closeTag() {
        let source = "x </span>"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "</span>")
        }
    }

    @Test("close tag with trailing whitespace")
    func closeTagTrailingSpaces() {
        let source = "x </span   >"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "</span   >")
        }
    }

    @Test("HTML comment")
    func htmlComment() {
        let source = "x <!-- a comment -->"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<!-- a comment -->")
        }
    }

    @Test("empty comment <!-->")
    func emptyComment() {
        let source = "x <!-->"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<!-->")
        }
    }

    @Test("near-empty comment <!--->")
    func nearEmptyComment() {
        let source = "x <!--->"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<!--->")
        }
    }

    @Test("processing instruction")
    func processingInstruction() {
        let source = "x <?php echo 1; ?>"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<?php echo 1; ?>")
        }
    }

    @Test("declaration")
    func declaration() {
        let source = "x <!DOCTYPE html>"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<!DOCTYPE html>")
        }
    }

    @Test("CDATA section")
    func cdataSection() {
        let source = "x <![CDATA[ raw <stuff> ]]>"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstHTMLInline(doc) == "<![CDATA[ raw <stuff> ]]>")
        }
    }

    @Test("invalid: unclosed tag stays as text")
    func unclosedTag() {
        let source = "<a"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map { $0.kind }
        #expect(!kinds.contains(.htmlInline))
        }
    }

    @Test("invalid: unterminated comment stays as text")
    func unterminatedComment() {
        let source = "<!-- never closed"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map { $0.kind }
        #expect(!kinds.contains(.htmlInline))
        }
    }

    @Test("text + html + text mixes correctly")
    func mixedWithText() {
        let source = "before <em>x</em> after"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = paragraphInlines(doc)
        let kinds = inlines.map { $0.kind }
        #expect(kinds == [.text, .htmlInline, .text, .htmlInline, .text])
        #expect(inlines[1].literal == "<em>")
        #expect(inlines[3].literal == "</em>")
        }
    }

    @Test("multi-line tag reconstructs its literal with the continuation's leading whitespace stripped")
    func multiLineTagStripsContinuationIndent() {
        // `<e` on line 1, ` e="">` on line 2: the whitespace inside the tag (here the soft break) is
        // valid tag whitespace, so the tag spans both lines. A paragraph strips each continuation
        // line's leading whitespace, so the reconstructed literal joins the two lines with a single
        // `\n` and NO leading space - `<e\ne="">` (cmark reads the same stripped paragraph buffer).
        // The tag's bytes straddle the soft-break segment boundary, so the literal can't be a
        // zero-copy contiguous source slice; it must be materialized from the joined segments.
        let source = "<e\n e=\"\">"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map { $0.kind }
        #expect(kinds == [.htmlInline])
        #expect(Self.firstHTMLInline(doc) == "<e\ne=\"\">")
        }
    }
}

@Suite("Inline parser - emphasis / strong")
struct EmphasisTests {

    /// Render the inline tree of the first paragraph as a flat list of `(kind, literal-or-empty)` in DFS order - useful for asserting on the emphasis nesting structure produced by the delimiter stack.
    private static func dfsInlines(_ doc: borrowing MarkdownDocument) -> [(MarkdownNode.Kind, String)] {
        var out: [(MarkdownNode.Kind, String)] = []
        let root = doc.root
        root.children.forEach { block in
            if block.kind.canAccumulateText {
                visit(block, into: &out)
            }
        }
        return out
    }

    private static func visit(_ node: MarkdownNode, into out: inout [(MarkdownNode.Kind, String)]) {
        if !node.kind.canAccumulateText {
            out.append((node.kind, node.literal() ?? ""))
        }
        node.children.forEach { child in
            visit(child, into: &out)
        }
    }

    @Test("simple *emphasis*")
    func simpleStarEmph() {
        let source = "*foo*"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.emphasis, .text])
        #expect(inlines[1].1 == "foo")
        }
    }

    @Test("simple _emphasis_")
    func simpleUnderEmph() {
        let source = "_foo_"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.emphasis, .text])
        #expect(inlines[1].1 == "foo")
        }
    }

    @Test("simple **strong**")
    func simpleStarStrong() {
        let source = "**foo**"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.strong, .text])
        #expect(inlines[1].1 == "foo")
        }
    }

    @Test("simple __strong__")
    func simpleUnderStrong() {
        let source = "__foo__"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.strong, .text])
        #expect(inlines[1].1 == "foo")
        }
    }

    @Test("emphasis with surrounding text")
    func surroundingText() {
        let source = "a *foo* b"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.text, .emphasis, .text, .text])
        #expect(inlines[0].1 == "a ")
        #expect(inlines[2].1 == "foo")
        #expect(inlines[3].1 == " b")
        }
    }

    @Test("nested *foo **bar** baz*")
    func nestedStrongInsideEmph() {
        let source = "*foo **bar** baz*"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        // emphasis containing: text "foo ", strong containing "bar", text " baz"
        let kinds = inlines.map(\.0)
        #expect(kinds == [.emphasis, .text, .strong, .text, .text])
        #expect(inlines[1].1 == "foo ")
        #expect(inlines[3].1 == "bar")
        #expect(inlines[4].1 == " baz")
        }
    }

    @Test("multiple emphasis runs in one paragraph")
    func multipleRuns() {
        let source = "*a* and *b*"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.emphasis, .text, .text, .emphasis, .text])
        #expect(inlines[1].1 == "a")
        #expect(inlines[2].1 == " and ")
        #expect(inlines[4].1 == "b")
        }
    }

    @Test("intraword underscore is not emphasis")
    func intrawordUnderscore() {
        let source = "foo_bar_baz"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        // No .emphasis node - _bar_ is intraword and rejected.
        #expect(!inlines.map(\.0).contains(.emphasis))
        }
    }

    @Test("intraword asterisk IS emphasis")
    func intrawordAsterisk() {
        let source = "foo*bar*baz"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0).contains(.emphasis))
        }
    }

    @Test("unmatched single * stays as text")
    func unmatchedStar() {
        let source = "*foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(!inlines.map(\.0).contains(.emphasis))
        #expect(!inlines.map(\.0).contains(.strong))
        }
    }

    @Test("asymmetric run: ***foo* bar**")
    func asymmetricStarRun() {
        // Per CommonMark: should produce <strong><em>foo</em> bar</strong>
        let source = "***foo* bar**"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        // strong containing: emphasis(foo), text " bar"
        #expect(inlines.map(\.0) == [.strong, .emphasis, .text, .text])
        #expect(inlines[2].1 == "foo")
        #expect(inlines[3].1 == " bar")
        }
    }

    @Test("flanking with punctuation: \"*\"foo\"*\"")
    func quotesAroundEmph() {
        let source = "\"*foo*\""
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        // text(`"`), emph(text(`foo`)), text(`"`)
        #expect(inlines.map(\.0) == [.text, .emphasis, .text, .text])
        }
    }

    @Test("emphasis on first byte and last byte of paragraph")
    func boundaryFlanking() {
        let source = "*x*"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        #expect(inlines.map(\.0) == [.emphasis, .text])
        #expect(inlines[1].1 == "x")
        }
    }

    @Test("emphasis with embedded code span")
    func emphWithCodeSpan() {
        let source = "*a `b` c*"
        MarkdownDocument.withParsedDocument(source) { doc in
        let inlines = Self.dfsInlines(doc)
        // emph: text "a ", code "b", text " c"
        #expect(inlines.map(\.0) == [.emphasis, .text, .codeInline(backtickCount: 1), .text])
        #expect(inlines[1].1 == "a ")
        #expect(inlines[2].1 == "b")
        #expect(inlines[3].1 == " c")
        }
    }
}

@Suite("Inline parser - links and images")
struct LinkImageTests {

    /// Pull (kind, url, title) for the first link/image found in DFS order, or all-nils if none.
    private static func firstLinkOrImage(
        _ doc: borrowing MarkdownDocument
    ) -> (kind: MarkdownNode.Kind, url: String?, title: String?, text: String?) {
        var result: (MarkdownNode.Kind, String?, String?, String?) = (.text, nil, nil, nil)
        var found = false
        let root = doc.root
        root.children.forEach { block in
            if found { return }
            block.children.forEach { inline in
                if found { return }
                if inline.kind == .link || inline.kind == .image {
                    var firstText: String?
                    inline.children.forEach { child in
                        if firstText == nil, let lit = child.literal() {
                            firstText = lit
                        }
                    }
                    result = (inline.kind, inline.url(), inline.title(), firstText)
                    found = true
                }
            }
        }
        return result
    }

    @Test("inline link: [text](url)")
    func inlineLink() {
        let source = "[foo](/url)"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .link)
        #expect(info.url == "/url")
        #expect(info.title == "")
        #expect(info.text == "foo")
        }
    }

    @Test("inline link with double-quoted title")
    func inlineLinkWithTitle() {
        let source = "[foo](/url \"the title\")"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.url == "/url")
        #expect(info.title == "the title")
        #expect(info.text == "foo")
        }
    }

    @Test("inline link with single-quoted title")
    func inlineLinkSingleQuoted() {
        let source = "[foo](/url 'title')"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.title == "title")
        }
    }

    @Test("inline link with paren title")
    func inlineLinkParenTitle() {
        let source = "[foo](/url (title))"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.title == "title")
        }
    }

    @Test("inline link with angle-bracketed destination")
    func inlineLinkAngleBracketed() {
        let source = "[foo](<http://example.com/path>)"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.url == "http://example.com/path")
        }
    }

    @Test("inline link with empty link text")
    func inlineLinkEmptyText() {
        let source = "[](/url)"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .link)
        #expect(info.url == "/url")
        }
    }

    @Test("inline image: ![alt](src)")
    func inlineImage() {
        let source = "![alt](/img.png)"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .image)
        #expect(info.url == "/img.png")
        #expect(info.text == "alt")
        }
    }

    @Test("image with title")
    func imageWithTitle() {
        let source = "![alt](/img.png \"caption\")"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .image)
        #expect(info.title == "caption")
        }
    }

    @Test("shortcut reference link")
    func shortcutReference() {
        let source = "[foo]: /url \"t\"\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .link)
        #expect(info.url == "/url")
        #expect(info.title == "t")
        #expect(info.text == "foo")
        }
    }

    @Test("collapsed reference link [foo][]")
    func collapsedReference() {
        let source = "[foo]: /url\n\n[foo][]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .link)
        #expect(info.url == "/url")
        #expect(info.text == "foo")
        }
    }

    @Test("full reference link [text][label]")
    func fullReference() {
        let source = "[label]: /url\n\n[link text][label]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .link)
        #expect(info.url == "/url")
        #expect(info.text == "link text")
        }
    }

    @Test("reference lookup is case-insensitive")
    func referenceCaseInsensitive() {
        let source = "[Foo]: /url\n\n[FOO]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.url == "/url")
        }
    }

    @Test("unmatched [ stays as text")
    func unmatchedOpenBracket() {
        let source = "[foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        // No link/image; the [ remains in the inline tree as text.
        let kinds = paragraphInlines(doc).map(\.kind)
        #expect(!kinds.contains(.link))
        }
    }

    @Test("unmatched ] stays as text")
    func unmatchedCloseBracket() {
        let source = "foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map(\.kind)
        #expect(!kinds.contains(.link))
        }
    }

    @Test("[foo] without ref-def stays as text")
    func shortcutNoMatch() {
        let source = "[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map(\.kind)
        #expect(!kinds.contains(.link))
        }
    }

    @Test("emphasis inside link text")
    func emphasisInsideLink() {
        let source = "[*foo*](/url)"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLinkOrImage(doc)
        #expect(info.kind == .link)
        #expect(info.url == "/url")
        // Within the link, the text is wrapped in emphasis.
        let root = doc.root
        var foundEmph = false
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link {
                    inline.children.forEach { child in
                        if child.kind == .emphasis {
                            foundEmph = true
                        }
                    }
                }
            }
        }
        #expect(foundEmph)
        }
    }

    @Test("link with no title, simple")
    func multipleLinks() {
        let source = "[a](/1) and [b](/2)"
        MarkdownDocument.withParsedDocument(source) { doc in
        var urls: [String] = []
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link, let u = inline.url() {
                    urls.append(u)
                }
            }
        }
        #expect(urls == ["/1", "/2"])
        }
    }

    @Test("nested links not allowed: outer [ becomes text")
    func nestedLinksDisallowed() {
        let source = "[outer [inner](/i)](/o)"
        MarkdownDocument.withParsedDocument(source) { doc in
        // Inner link matches; outer doesn't (no_link_openers).
        var linkUrls: [String] = []
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link, let u = inline.url() {
                    linkUrls.append(u)
                }
            }
        }
        #expect(linkUrls == ["/i"])
        }
    }

    @Test("image can contain inner link")
    func imageContainsLink() {
        let source = "![alt with [link](/i)](/img.png)"
        MarkdownDocument.withParsedDocument(source) { doc in
        // Image matches; the inner link also matches because images don't disable the link opener.
        var hasImage = false
        var hasInnerLink = false
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .image {
                    hasImage = true
                    inline.children.forEach { child in
                        if child.kind == .link {
                            hasInnerLink = true
                        }
                    }
                }
            }
        }
        #expect(hasImage)
        #expect(hasInnerLink)
        }
    }
}

@Suite("Extended attributes - `^[..]`")
struct ExtendedAttributeTests {

    /// Find the first `.attribute` node anywhere in the doc. Returns `(attrs, firstChildLiteral)` or `(nil, nil)` if none.
    private static func firstAttribute(_ doc: borrowing MarkdownDocument) -> (attrs: String?, text: String?) {
        var found: (String?, String?) = (nil, nil)
        let root = doc.root
        root.children.forEach { block in
            if found.0 != nil { return }
            block.children.forEach { inline in
                if found.0 != nil { return }
                visit(inline, into: &found)
            }
        }
        return found
    }

    private static func visit(_ node: borrowing MarkdownNode, into out: inout (String?, String?)) {
        if node.kind == .attribute, out.0 == nil {
            var firstText: String?
            node.children.forEach { child in
                if firstText == nil, let lit = child.literal() {
                    firstText = lit
                }
            }
            out = (node.attributes(), firstText)
            return
        }
        node.children.forEach { child in
            visit(child, into: &out)
        }
    }

    @Test("inline form: ^[content](attrs)")
    func inlineForm() {
        let source = "^[hello](color: red)"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "color: red")
        #expect(info.text == "hello")
        }
    }

    @Test("inline form: empty content")
    func emptyContent() {
        let source = "^[](attr)"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "attr")
        }
    }

    @Test("inline form: attrs with whitespace")
    func attrsWithWhitespace() {
        let source = "^[x](color: red, weight: bold)"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "color: red, weight: bold")
        }
    }

    @Test("inline form: attrs with balanced parens")
    func attrsWithParens() {
        let source = "^[x](rgb(255, 0, 0))"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "rgb(255, 0, 0)")
        }
    }

    @Test("inline form: attrs with backslash-escaped paren")
    func attrsWithEscapedParen() {
        let source = "^[x](a\\)b)"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        // The `\)` is an escape; cmark preserves the backslash in the chunk.
        #expect(info.attrs == "a\\)b")
        }
    }

    @Test("inline form with surrounding text")
    func surroundingText() {
        let source = "before ^[middle](attr) after"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "attr")
        #expect(info.text == "middle")
        }
    }

    @Test("emphasis inside attribute content")
    func emphasisInside() {
        let source = "^[*foo*](attr)"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        var hasEmph = false
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .attribute {
                    inline.children.forEach { child in
                        if child.kind == .emphasis { hasEmph = true }
                    }
                }
            }
        }
        #expect(hasEmph)
        }
    }

    @Test("reference def + reference form")
    func referenceForm() {
        let source = "^[label]: color: blue\n\n^[content][label]"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "color: blue")
        #expect(info.text == "content")
        }
    }

    @Test("reference def whose label spans a soft break resolves")
    func crossLineReferenceDef() {
        // cmark scans the label over the paragraph's flat buffer, so a `^[..]:` definition whose label
        // straddles a soft break is captured normally (`la\nbel` → `la bel`) and produces no visible node.
        let source = "^[la\nbel]: color: blue\n\n^[content][la bel]"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        #expect(doc._storage.attributeReferenceMap["la bel"] != nil)
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == "color: blue")
        #expect(info.text == "content")
        }
    }

    @Test("attribute ref defs do not collide with link ref defs")
    func separateRefMaps() {
        let source = "[foo]: /url\n^[foo]: color: red\n\n[foo] and ^[content][foo]"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        // Both should be registered.
        #expect(doc._storage.referenceMap["foo"] != nil)
        #expect(doc._storage.attributeReferenceMap["foo"] != nil)
        // Inline parsing should produce both a .link and a .attribute.
        var hasLink = false
        var hasAttr = false
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link { hasLink = true }
                if inline.kind == .attribute { hasAttr = true }
            }
        }
        #expect(hasLink)
        #expect(hasAttr)
        }
    }

    @Test("invalid: ^[content] without (...) or [label] stays as text")
    func invalidNoFollowup() {
        let source = "^[content]"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        // No `.attribute` should be emitted.
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == nil)
        }
    }

    @Test("invalid: unknown reference label fails")
    func invalidUnknownRef() {
        let source = "^[content][unknown]"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        let info = Self.firstAttribute(doc)
        #expect(info.attrs == nil)
        }
    }

    @Test("nested attribute is allowed")
    func nestedAttribute() {
        let source = "^[outer ^[inner](b)](a)"
        MarkdownDocument.withParsedDocument(source, options: [.attributes]) { doc in
        // Outer attribute matches; inner attribute also nests.
        var attrCount = 0
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .attribute {
                    attrCount += 1
                    inline.children.forEach { child in
                        if child.kind == .attribute {
                            attrCount += 1
                        }
                    }
                }
            }
        }
        #expect(attrCount == 2)
        }
    }
}

@Suite("GFM extensions - strikethrough")
struct StrikethroughTests {

    private static func firstStrikethrough(_ doc: borrowing MarkdownDocument) -> String? {
        var found: String?
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if found != nil { return }
                visit(inline, into: &found)
            }
        }
        return found
    }

    private static func visit(_ node: borrowing MarkdownNode, into out: inout String?) {
        if node.kind == .strikethrough, out == nil {
            var inner = ""
            node.children.forEach { child in
                if let lit = child.literal() {
                    inner += lit
                }
            }
            out = inner
            return
        }
        node.children.forEach { child in
            visit(child, into: &out)
        }
    }

    @Test("default-disabled: ~text~ stays as text")
    func defaultDisabled() {
        let source = "~foo~"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.firstStrikethrough(doc) == nil)
        }
    }

    @Test("single tilde with strikethrough enabled")
    func singleTilde() {
        let source = "~foo~"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
        #expect(Self.firstStrikethrough(doc) == "foo")
        }
    }

    @Test("double tilde with strikethrough enabled")
    func doubleTilde() {
        let source = "~~foo~~"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
        #expect(Self.firstStrikethrough(doc) == "foo")
        }
    }

    @Test("strikethrough with surrounding text")
    func surroundingText() {
        let source = "before ~foo~ after"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
        #expect(Self.firstStrikethrough(doc) == "foo")
        }
    }

    @Test("doubleTilde flag rejects single tilde")
    func doubleTildeFlagRejects() {
        let source = "~foo~"
        MarkdownDocument.withParsedDocument(source, options: [.strikethrough, .strikethroughDoubleTilde]) { doc in
        #expect(Self.firstStrikethrough(doc) == nil)
        }
    }

    @Test("doubleTilde flag accepts double tilde")
    func doubleTildeFlagAccepts() {
        let source = "~~foo~~"
        MarkdownDocument.withParsedDocument(source, options: [.strikethrough, .strikethroughDoubleTilde]) { doc in
        #expect(Self.firstStrikethrough(doc) == "foo")
        }
    }

    @Test("mismatched tilde lengths don't pair")
    func mismatchedLengths() {
        let source = "~foo~~"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
        #expect(Self.firstStrikethrough(doc) == nil)
        }
    }

    /// Count every `.strikethrough` node in the document (DFS).
    private static func strikethroughCount(_ doc: borrowing MarkdownDocument) -> Int {
        var count = 0
        func walk(_ node: borrowing MarkdownNode) {
            if node.kind == .strikethrough { count += 1 }
            node.children.forEach { walk($0) }
        }
        doc.root.children.forEach { walk($0) }
        return count
    }

    /// A closer must not reach past a mismatched-length intervening `~` run to pair with a farther
    /// equal-length opener. cmark-gfm's generic delimiter walk (`S_process_emphasis`) accepts the
    /// *nearest* flanking opener; the strikethrough `insert` callback then finds the lengths differ
    /// and removes both delimiters (closer back through opener), so the farther opener never pairs.
    /// The only reason the same shape on one line already matches is that the intervening `~~` there
    /// is also can-close, which the generic flanking rule rejects as an opener; across a softbreak the
    /// intervening `~~` is can-open-only, so cmark selects and then discards it. No strikethrough forms.
    @Test("mismatched intervening run across a softbreak suppresses the far pairing")
    func mismatchedInterveningAcrossSoftbreak() {
        let source = "~a\n~~b~"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 0)
            #expect(Self.firstStrikethrough(doc) == nil)
        }
    }

    /// Fixture sanity + guard against over-suppression: the same shape on ONE line still forms a
    /// strikethrough, pairing the outer len-1 tildes across the interior `~~` (which becomes content).
    @Test("one-line control still pairs the outer tildes across an interior run")
    func oneLineControlStillPairs() throws {
        let source = "~a~~b~"
        try MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
            let inner = Self.firstStrikethrough(doc)
            let content = try #require(inner, "one-line control must form a strikethrough")
            #expect(content == "a~~b")
            #expect(Self.strikethroughCount(doc) == 1)
        }
    }

    /// Guard against over-suppression: a matched-length pair that spans a softbreak DOES form a
    /// strikethrough (opener on line 1, closer on line 2, both len 1). cmark forms this.
    @Test("matched-length pair forms across a softbreak")
    func matchedPairAcrossSoftbreak() {
        let source = "~a\nb~"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 1)
        }
    }

    /// The line-2 first run being len 1 (not len 2) is the single differentiator: here the `~b~` on
    /// line 2 pairs locally and the line-1 `~` is orphaned. One strikethrough, content "b".
    @Test("line-2 local pairing leaves the line-1 opener orphaned")
    func lineTwoLocalPairing() throws {
        let source = "~a\n~b~"
        try MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
            let inner = Self.firstStrikethrough(doc)
            let content = try #require(inner, "line-2 ~b~ must form a strikethrough")
            #expect(content == "b")
            #expect(Self.strikethroughCount(doc) == 1)
        }
    }

    /// Mirror of the RED case with the mismatched run adjacent to the closer side rather than the
    /// opener side: `~~b~` on line 1, `~a` on line 2. The line-1 closer `~` cannot pair with the
    /// len-2 `~~` opener, and the line-2 `~` is an opener with no following closer. No strikethrough.
    @Test("mismatched run near the closer side forms nothing")
    func mismatchedRunNearCloser() {
        let source = "~~b~\n~a"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 0)
        }
    }

    /// A three-line span: the mismatched intervening `~~` still suppresses the far pairing exactly as
    /// in the two-line case; the trailing len-1 closer on line 3 consumes the line-2 `~~` and neither
    /// the line-1 opener nor any farther delimiter forms a strikethrough.
    @Test("mismatched intervening run suppresses pairing across a three-line span")
    func mismatchedInterveningThreeLines() {
        let source = "~a\nx\n~~b~"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 0)
        }
    }

    @Test("strikethrough nested inside emphasis")
    func nestedInEmphasis() {
        let source = "*foo ~bar~ baz*"
        MarkdownDocument.withParsedDocument(source, options: .strikethrough) { doc in
        // The strikethrough should be a child of the emphasis.
        var foundNested = false
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .emphasis {
                    inline.children.forEach { child in
                        if child.kind == .strikethrough {
                            foundNested = true
                        }
                    }
                }
            }
        }
        #expect(foundNested)
        }
    }

    /// The first paragraph's direct inline children as `(kind, literal)` pairs. A container inline
    /// (e.g. `.strikethrough`) reports a `nil` literal; read its inner text via `firstStrikethrough`.
    private static func paragraphInlines(_ doc: borrowing MarkdownDocument) -> [(kind: MarkdownNode.Kind, literal: String?)] {
        var inlines: [(kind: MarkdownNode.Kind, literal: String?)] = []
        var seenParagraph = false
        doc.root.children.forEach { block in
            guard block.kind == .paragraph, !seenParagraph else { return }
            seenParagraph = true
            block.children.forEach { inline in
                inlines.append((inline.kind, inline.literal()))
            }
        }
        return inlines
    }

    // cmark scans emphasis/strikethrough delimiter flanking with `cmark_utf8proc_is_space`
    // (`src/utf8.c`), whose ASCII members are space, tab, LF, CR, and FF (0x0C) - but NOT vertical
    // tab (0x0B). So a VT between tildes is a non-space neighbour: each `~` is left/right-flanking
    // against it and the pair forms a strikethrough. The strikethrough's content is the VT byte
    // itself, which the debug surface renders invisibly (appearing as an "empty" strikethrough).
    @Test("VT between tildes pairs into a strikethrough")
    func verticalTabPairs() {
        MarkdownDocument.withParsedDocument("~\u{0B}~", options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 1)
            #expect(Self.firstStrikethrough(doc) == "\u{0B}")
        }
    }

    @Test("VT between tildes pairs with surrounding text")
    func verticalTabPairsWithSurroundingText() throws {
        try MarkdownDocument.withParsedDocument("a~\u{0B}~b", options: .strikethrough) { doc in
            let inlines = Self.paragraphInlines(doc)
            try #require(inlines.count == 3)
            #expect(inlines[0].kind == .text)
            #expect(inlines[0].literal == "a")
            #expect(inlines[1].kind == .strikethrough)
            #expect(inlines[2].kind == .text)
            #expect(inlines[2].literal == "b")
            #expect(Self.firstStrikethrough(doc) == "\u{0B}")
        }
    }

    @Test("VT between double tildes pairs into a strikethrough")
    func verticalTabDoubleTildePairs() {
        MarkdownDocument.withParsedDocument("~~\u{0B}~~", options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 1)
            #expect(Self.firstStrikethrough(doc) == "\u{0B}")
        }
    }

    // Guards for the flanking whitespace boundary the VT fix must NOT disturb. FF (0x0C), space, and
    // tab are all flanking spaces in `cmark_utf8proc_is_space`, so tildes around them are non-flanking
    // and stay literal - no strikethrough forms.
    @Test("FF between tildes stays literal")
    func formFeedStaysLiteral() {
        MarkdownDocument.withParsedDocument("~\u{0C}~", options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 0)
        }
    }

    @Test("space between tildes stays literal")
    func spaceStaysLiteral() {
        MarkdownDocument.withParsedDocument("~ ~", options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 0)
        }
    }

    @Test("tab between tildes stays literal")
    func tabStaysLiteral() {
        MarkdownDocument.withParsedDocument("~\t~", options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 0)
        }
    }

    // Fixture sanity: ordinary non-space content between tildes pairs into a strikethrough as always.
    @Test("non-space content between tildes still pairs")
    func contentBetweenTildesPairs() {
        MarkdownDocument.withParsedDocument("~x~", options: .strikethrough) { doc in
            #expect(Self.strikethroughCount(doc) == 1)
            #expect(Self.firstStrikethrough(doc) == "x")
        }
    }
}

@Suite("GFM extensions - extended autolinks")
struct GFMAutolinkTests {

    private static func firstLink(_ doc: borrowing MarkdownDocument) -> (url: String?, text: String?) {
        var url: String?
        var text: String?
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link, url == nil {
                    url = inline.url()
                    inline.children.forEach { child in
                        if text == nil, let lit = child.literal() {
                            text = lit
                        }
                    }
                }
            }
        }
        return (url, text)
    }

    @Test("default-disabled: bare URL stays as text")
    func defaultDisabled() {
        let source = "visit http://example.com today"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == nil)
        }
    }

    @Test("http URL")
    func httpURL() {
        let source = "visit http://example.com today"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "http://example.com")
        #expect(info.text == "http://example.com")
        }
    }

    @Test("https URL")
    func httpsURL() {
        let source = "see https://example.com/path?q=1#frag"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "https://example.com/path?q=1#frag")
        }
    }

    @Test("www URL synthesizes http://")
    func wwwURL() {
        let source = "go to www.example.com please"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "http://www.example.com")
        #expect(info.text == "www.example.com")
        }
    }

    @Test("email synthesizes mailto:")
    func emailURL() {
        let source = "mail me at foo@example.com please"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "mailto:foo@example.com")
        #expect(info.text == "foo@example.com")
        }
    }

    @Test("trailing punctuation is peeled")
    func trailingPunct() {
        let source = "see http://example.com."
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "http://example.com")
        }
    }

    @Test("trailing unbalanced ) is peeled")
    func trailingParen() {
        let source = "(see http://example.com/path)"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "http://example.com/path")
        }
    }

    @Test("balanced parens within URL are kept")
    func balancedParens() {
        let source = "see http://en.wikipedia.org/wiki/Markdown_(format) here"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "http://en.wikipedia.org/wiki/Markdown_(format)")
        }
    }

    @Test("URL preceded by word char is rejected")
    func wordCharBefore() {
        let source = "abchttp://example.com"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == nil)
        }
    }

    /// A valid domain holds at least one period (spec "Autolinks (extension)").
    @Test("scheme URL host needs a period")
    func schemeHostNeedsPeriod() {
        let source = "look at http://localhost"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == nil)
        }
    }

    @Test("multiple URLs in one paragraph")
    func multipleURLs() {
        let source = "first http://a.com then https://b.com"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        var urls: [String] = []
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link, let u = inline.url() {
                    urls.append(u)
                }
            }
        }
        #expect(urls == ["http://a.com", "https://b.com"])
        }
    }

    @Test("URL terminates at whitespace")
    func terminatesAtWhitespace() {
        let source = "http://a.com foo"
        MarkdownDocument.withParsedDocument(source, options: .gfmAutolink) { doc in
        let info = Self.firstLink(doc)
        #expect(info.url == "http://a.com")
        }
    }
}

@Suite("GFM extensions - footnotes")
struct FootnoteTests {

    /// Pull the first .footnoteReference (label, index) and the first .footnoteDefinition (label, refCount) anywhere in the doc.
    private static func firstFootnotes(_ doc: borrowing MarkdownDocument) -> (
        ref: (label: String?, index: Int?)?,
        def: (label: String?, refCount: Int?)?
    ) {
        var ref: (String?, Int?)? = nil
        var def: (String?, Int?)? = nil
        let root = doc.root
        visit(root, ref: &ref, def: &def)
        return (ref, def)
    }

    private static func visit(
        _ node: borrowing MarkdownNode,
        ref: inout (String?, Int?)?,
        def: inout (String?, Int?)?
    ) {
        if case .footnoteReference(let index) = node.kind, ref == nil {
            ref = (node.footnoteLabel(), index)
        }
        if node.kind == .footnoteDefinition, def == nil {
            // refCount is internal, but we can derive it via reflection of the node's data through public API. Since there's no public accessor for refCount yet, leave it nil and verify only label.
            def = (node.footnoteLabel(), nil)
        }
        node.children.forEach { child in
            visit(child, ref: &ref, def: &def)
        }
    }

    @Test("default-disabled: [^x] stays as text")
    func defaultDisabled() {
        let source = "ref [^x]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = paragraphInlines(doc).map(\.kind)
        #expect(!kinds.contains { if case .footnoteReference = $0 { true } else { false } })
        }
    }

    @Test("definition followed by reference")
    func defThenRef() {
        let source = "[^a]: footnote body\n\nref [^a]"
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        let info = Self.firstFootnotes(doc)
        #expect(info.def?.label == "a")
        #expect(info.ref?.label == "a")
        #expect(info.ref?.index == 1)
        }
    }

    @Test("reference before definition still parses")
    func refThenDef() {
        let source = "ref [^a]\n\n[^a]: body"
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        let info = Self.firstFootnotes(doc)
        #expect(info.ref?.label == "a")
        #expect(info.ref?.index == 1)
        #expect(info.def?.label == "a")
        }
    }

    @Test("multiple footnotes get sequential indices")
    func multipleFootnotes() {
        // Indices are assigned in first-reference order, per label; repeat references reuse the index.
        // Definitions are required — an unresolved reference becomes literal text (see `unresolvedRef`).
        let source = "[^a] and [^b] and [^a] again\n\n[^a]: A\n[^b]: B"
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        var indices: [Int] = []
        var labels: [String] = []
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if case .footnoteReference(let i) = inline.kind,
                   let l = inline.footnoteLabel() {
                    indices.append(i)
                    labels.append(l)
                }
            }
        }
        #expect(labels == ["a", "b", "a"])
        #expect(indices == [1, 2, 1])
        }
    }

    @Test("unresolved reference becomes literal text")
    func unresolvedRef() {
        // cmark turns a `[^label]` with no matching definition back into literal text; the rewrite
        // matches by not emitting a reference node when the label doesn't resolve.
        let source = "see [^missing]"
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        let info = Self.firstFootnotes(doc)
        #expect(info.ref == nil)
        let text = paragraphInlines(doc).compactMap { $0.literal }.joined()
        #expect(text.contains("[^missing]"))
        }
    }

    @Test("definition produces a footnoteDefinition + paragraph child")
    func definitionStructure() {
        // The definition must be referenced to survive — cmark drops unreferenced definitions.
        let source = "[^a]: hello world\n\nsee [^a]"
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        var found = false
        let root = doc.root
        root.children.forEach { block in
            if block.kind == .footnoteDefinition {
                found = true
                var hasPara = false
                block.children.forEach { child in
                    if child.kind == .paragraph { hasPara = true }
                }
                #expect(hasPara)
            }
        }
        #expect(found)
        }
    }

    @Test("[^x] without `^` interior stays as link/text")
    func noFootnoteWithoutCaret() throws {
        // `[x]` should still try as a shortcut ref link, fail, emit `]` text.
        let source = "[x]"
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        let kinds = paragraphInlines(doc).map(\.kind)
        #expect(!kinds.contains { if case .footnoteReference = $0 { true } else { false } })
        }
    }

    @Test("multiple definitions, multiple refs")
    func realisticDocument() {
        let source = """
        Some text with a ref[^one] and another[^two].

        [^one]: First note.

        [^two]: Second note.
        """
        MarkdownDocument.withParsedDocument(source, options: .footnotes) { doc in
        var refLabels: [String] = []
        var defLabels: [String] = []
        let root = doc.root
        root.children.forEach { block in
            if block.kind == .footnoteDefinition, let l = block.footnoteLabel() {
                defLabels.append(l)
            }
            block.children.forEach { inline in
                if case .footnoteReference = inline.kind, let l = inline.footnoteLabel() {
                    refLabels.append(l)
                }
            }
        }
        #expect(refLabels == ["one", "two"])
        #expect(defLabels == ["one", "two"])
        }
    }
}
