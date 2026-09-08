/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// CommonMark §2.3: "For security reasons, a conforming parser must strip or replace the U+0000
/// character" — cmark-gfm replaces every NUL (U+0000) in the input with U+FFFD (REPLACEMENT
/// CHARACTER) at feed time, so every emitted node's literal content shows U+FFFD, never a raw NUL.
/// The rewrite is zero-copy (it parses a borrowed source `Span`), so it reproduces this by
/// materializing any NUL-bearing content into the additions arena with the 1-byte NUL replaced by
/// the 3-byte U+FFFD — the same arena-materialization it already uses for tab expansion — while
/// NUL-free content stays zero-copy. NUL is a non-structural byte (not whitespace, not punctuation),
/// so it only ever changes content, never block/inline structure; the exception is that a raw NUL is
/// an ASCII control character while U+FFFD is not, so contexts that reject control characters (e.g. an
/// angle-bracket autolink body) must see U+FFFD to match — which requires the substitution to happen
/// before inline scanning, not just at emission.
///
/// Other C0 control bytes (0x01, 0x08, …) are kept literally by cmark and are unaffected here.
@Suite("NUL replacement (U+0000 -> U+FFFD)")
struct NULReplacementTests {
    private static let replacement = "\u{FFFD}"
    private static let nul = "\u{0}"

    /// Concatenated `.text` / literal content across the whole tree (DFS), for coarse content checks.
    private func allText(_ node: borrowing MarkdownNode) -> String {
        var out = ""
        if let lit = node.literal() { out += lit }
        node.children.forEach { out += allText($0) }
        return out
    }

    /// The whole document's literal text (DFS concatenation), parsed with `options`.
    private func firstText(
        _ source: String,
        options: MarkdownDocument.ParseOptions = []
    ) throws -> String {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            allText(doc.root)
        }
    }

    @Test("NUL in paragraph text becomes U+FFFD")
    func paragraphText() throws {
        let text = try firstText("a\u{0}b")
        #expect(text.contains(Self.replacement))
        #expect(!text.contains(Self.nul))
        #expect(text == "a\u{FFFD}b")
    }

    @Test("NUL in a code span becomes U+FFFD")
    func codeSpan() throws {
        let text = try MarkdownDocument.withParsedDocument("`\u{0}`") { doc -> String in
            var out = ""
            doc.root.children.forEach { p in
                p.children.forEach { inline in
                    if case .codeInline = inline.kind, let lit = inline.literal() { out += lit }
                }
            }
            return out
        }
        #expect(text.contains(Self.replacement))
        #expect(!text.contains(Self.nul))
        #expect(text == "\u{FFFD}")
    }

    @Test("NUL in a fenced code block body becomes U+FFFD")
    func fencedCodeBlock() throws {
        let body = try MarkdownDocument.withParsedDocument("```\n\u{0}\n```") { doc -> String in
            var out = ""
            doc.root.children.forEach { if case .codeBlock = $0.kind, let b = $0.literal() { out += b } }
            return out
        }
        #expect(body.contains(Self.replacement))
        #expect(!body.contains(Self.nul))
    }

    @Test("NUL in an indented code block body becomes U+FFFD")
    func indentedCodeBlock() throws {
        let body = try MarkdownDocument.withParsedDocument("    \u{0}") { doc -> String in
            var out = ""
            doc.root.children.forEach { if case .codeBlock = $0.kind, let b = $0.literal() { out += b } }
            return out
        }
        #expect(body.contains(Self.replacement))
        #expect(!body.contains(Self.nul))
    }

    @Test("NUL in a fenced code block info string becomes U+FFFD")
    func codeBlockInfoString() throws {
        let info = try MarkdownDocument.withParsedDocument("```\u{0}x\n\n```") { doc -> String in
            var out = ""
            doc.root.children.forEach { if let i = $0.codeBlockInfoString() { out += i } }
            return out
        }
        #expect(info.contains(Self.replacement))
        #expect(!info.contains(Self.nul))
        #expect(info == "\u{FFFD}x")
    }

    @Test("NUL in an HTML block body becomes U+FFFD")
    func htmlBlock() throws {
        let body = try MarkdownDocument.withParsedDocument("<div>\n\u{0}\n</div>") { doc -> String in
            var out = ""
            doc.root.children.forEach { if case .htmlBlock = $0.kind, let b = $0.literal() { out += b } }
            return out
        }
        #expect(body.contains(Self.replacement))
        #expect(!body.contains(Self.nul))
    }

    @Test("NUL in an inline link destination becomes U+FFFD")
    func inlineLinkDestination() throws {
        let url = try MarkdownDocument.withParsedDocument("[a](\u{0})") { doc -> String in
            var out = ""
            doc.root.children.forEach { p in
                p.children.forEach { inline in
                    if case .link = inline.kind, let u = inline.url() { out += u }
                }
            }
            return out
        }
        #expect(url.contains(Self.replacement))
        #expect(!url.contains(Self.nul))
        #expect(url == "\u{FFFD}")
    }

    @Test("NUL in a reference-definition destination becomes U+FFFD")
    func referenceDefinitionDestination() throws {
        let url = try MarkdownDocument.withParsedDocument("[a]\n\n[a]: \u{0}") { doc -> String in
            var out = ""
            doc.root.children.forEach { p in
                p.children.forEach { inline in
                    if case .link = inline.kind, let u = inline.url() { out += u }
                }
            }
            return out
        }
        #expect(url.contains(Self.replacement))
        #expect(!url.contains(Self.nul))
        #expect(url == "\u{FFFD}")
    }

    @Test("NUL in a ref-def destination stripped on the setext-underline path becomes U+FFFD")
    func setextStrippedReferenceDefinition() throws {
        // The whole first line is a ref-def; the `===` underline triggers `processLine`'s ref-def strip
        // over the paragraph's still-*source-backed* content (bypassing `drainLeaf`), so the definition
        // store is where the NUL must be replaced. cmark yields destination "/u<U+FFFD>".
        let url = try MarkdownDocument.withParsedDocument("[a]: /u\u{0}\n===\n\n[a]") { doc -> String in
            var found: String? = nil
            func walk(_ n: borrowing MarkdownNode) {
                if found == nil, case .link = n.kind { found = n.url() }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return found ?? ""
        }
        #expect(url == "/u\u{FFFD}")
        #expect(!url.contains(Self.nul))
    }

    @Test("NUL in a footnote definition's content becomes U+FFFD")
    func footnoteDefinitionContent() throws {
        try MarkdownDocument.withParsedDocument("[^a]: x\u{0}\n\n[^a]", options: [.footnotes]) { doc in
            var defText: String? = nil
            var hasRef = false
            func walk(_ n: borrowing MarkdownNode) {
                if case .footnoteDefinition = n.kind { defText = self.allText(n) }
                if case .footnoteReference = n.kind { hasRef = true }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            let text = try #require(defText, "expected a footnote definition")
            #expect(text == "x\u{FFFD}")
            #expect(!text.contains(Self.nul))
            #expect(hasRef, "expected a footnote reference")
        }
    }

    @Test("NUL in an ATX heading becomes U+FFFD")
    func atxHeading() throws {
        let text = try MarkdownDocument.withParsedDocument("# \u{0}") { doc -> String in
            var out = ""
            doc.root.children.forEach { if case .heading = $0.kind { out += self.allText($0) } }
            return out
        }
        #expect(text.contains(Self.replacement))
        #expect(!text.contains(Self.nul))
        #expect(text == "\u{FFFD}")
    }

    @Test("NUL in a setext heading becomes U+FFFD")
    func setextHeading() throws {
        let text = try MarkdownDocument.withParsedDocument("a\u{0}\n==") { doc -> String in
            var out = ""
            doc.root.children.forEach { if case .heading = $0.kind { out += self.allText($0) } }
            return out
        }
        #expect(text.contains(Self.replacement))
        #expect(!text.contains(Self.nul))
        #expect(text == "a\u{FFFD}")
    }

    @Test("NUL in a non-contiguous (block-quote) paragraph becomes U+FFFD")
    func blockQuoteMultiline() throws {
        let text = try firstText("> a\u{0}\n> b")
        #expect(text.contains(Self.replacement))
        #expect(!text.contains(Self.nul))
        // "a" + U+FFFD, a soft break (no literal), then "b".
        #expect(text == "a\u{FFFD}b")
    }

    @Test("NUL inside an angle-bracket autolink body forms a link with a U+FFFD destination")
    func angleAutolinkBody() throws {
        // A raw NUL is an ASCII control char, which the autolink URI scanner rejects; U+FFFD is not,
        // so cmark forms the autolink. The substitution must therefore happen before inline scanning.
        try MarkdownDocument.withParsedDocument("<http://a\u{0}b>") { doc in
            var link: String? = nil
            doc.root.children.forEach { p in
                p.children.forEach { inline in
                    if case .link = inline.kind { link = inline.url() }
                }
            }
            let url = try #require(link, "expected an autolink node")
            #expect(url == "http://a\u{FFFD}b")
        }
    }

    @Test("NUL in a GFM table cell becomes U+FFFD")
    func tableCell() throws {
        let cells = try MarkdownDocument.withParsedDocument("h\u{0}\n|-", options: [.tables]) { doc -> [String] in
            var out: [String] = []
            func walk(_ n: borrowing MarkdownNode) {
                if case .tableCell = n.kind {
                    var t = ""
                    n.children.forEach { if let l = $0.literal() { t += l } }
                    out.append(t)
                }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return out
        }
        try #require(!cells.isEmpty, "expected a table with at least one cell")
        #expect(cells.contains("h\u{FFFD}"))
        #expect(!cells.joined().contains(Self.nul))
    }

    @Test("NUL in inline-only mode becomes U+FFFD")
    func inlineOnly() throws {
        let text = try firstText("a\u{0}b", options: [.inlineOnly])
        #expect(text.contains(Self.replacement))
        #expect(!text.contains(Self.nul))
        #expect(text == "a\u{FFFD}b")
    }

    /// The first `.attribute` node's attributes string, or `nil`.
    private func firstAttributes(_ source: String) throws -> String? {
        try MarkdownDocument.withParsedDocument(source) { doc -> String? in
            var found: String? = nil
            func walk(_ n: borrowing MarkdownNode) {
                if found == nil, case .attribute = n.kind { found = n.attributes() }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return found
        }
    }

    @Test("NUL in an inline `^[..](..)` attribute becomes U+FFFD")
    func inlineAttribute() throws {
        let attrs = try #require(try firstAttributes("^[x](a\u{0}b)"))
        #expect(attrs == "a\u{FFFD}b")
        #expect(!attrs.contains(Self.nul))
    }

    @Test("NUL in a reference-form `^[label]: ..` attribute becomes U+FFFD")
    func referenceAttribute() throws {
        let attrs = try #require(try firstAttributes("^[label]: a\u{0}b\n\n^[content][label]"))
        #expect(attrs == "a\u{FFFD}b")
        #expect(!attrs.contains(Self.nul))
    }

    @Test("other C0 control bytes are left literal (only NUL is replaced)")
    func otherControlBytesUnchanged() throws {
        // cmark keeps 0x01 / 0x08 / 0x1F literally; the rewrite already matches and must not start
        // replacing them.
        for control in ["\u{1}", "\u{8}", "\u{1F}"] {
            let text = try firstText("a\(control)b")
            #expect(text == "a\(control)b")
            #expect(!text.contains(Self.replacement))
        }
    }
}
