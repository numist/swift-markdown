/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// The parse options `.inlineOnly` and `.preserveWhitespace`.
///
/// Neither opens a block container: the whole input is one paragraph, so block markers such as `#`, `* `, `> `, `---`,
/// ` ``` ` and a 4-space indent are text, and line endings, blank lines and leading and trailing whitespace stay in the
/// paragraph's text. Inline syntax is parsed. The two options produce the same tree.
@Suite("Parse options - inlineOnly / preserveWhitespace")
struct InlineOnlyOptionTests {

    /// The single top-level child of the document, or `nil` if the count isn't exactly one.
    private func soleBlock(_ doc: borrowing MarkdownDocument) -> (kind: MarkdownNode.Kind, count: Int)? {
        var kinds: [MarkdownNode.Kind] = []
        let root = doc.root
        root.children.forEach { kinds.append($0.kind) }
        guard kinds.count == 1 else { return (kinds.first ?? .document, kinds.count) }
        return (kinds[0], 1)
    }

    /// `(kind, literal)` for every inline child of the document's first paragraph.
    private func inlines(_ doc: borrowing MarkdownDocument) -> [(kind: MarkdownNode.Kind, literal: String?)] {
        paragraphInlines(doc).map { ($0.kind, $0.literal) }
    }

    /// A compact recursive dump of the whole tree, for comparing two parses.
    private func dump(_ doc: borrowing MarkdownDocument) -> String {
        var out = ""
        func walk(_ node: borrowing MarkdownNode, _ depth: Int) {
            out += String(repeating: "  ", count: depth)
            out += "\(node.kind)"
            if let literal = node.literal() { out += " \(String(reflecting: literal))" }
            if let url = node.url() { out += " url=\(url)" }
            out += "\n"
            node.children.forEach { walk($0, depth + 1) }
        }
        let root = doc.root
        walk(root, 0)
        return out
    }

    // MARK: - inlineOnly

    @Test("inlineOnly suppresses all block structure into one paragraph")
    func inlineOnlySuppressesBlocks() {
        let source = "# heading\n\n* item"
        MarkdownDocument.withParsedDocument(source, options: .inlineOnly) { doc in

        let block = soleBlock(doc)
        #expect(block?.kind == .paragraph)
        #expect(block?.count == 1)

        let inlines = inlines(doc)
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.first?.literal == "# heading\n\n* item")
        }
    }

    @Test("inlineOnly parses inline emphasis and code spans")
    func inlineOnlyKeepsInlineSyntax() {
        let source = "# *em* and `code`"
        MarkdownDocument.withParsedDocument(source, options: .inlineOnly) { doc in

        #expect(soleBlock(doc)?.kind == .paragraph)

        let inlines = inlines(doc)
        #expect(inlines.map(\.kind) == [.text, .emphasis, .text, .codeInline(backtickCount: 1)])
        #expect(inlines.map(\.literal) == ["# ", nil, " and ", "code"])

        var emphasisText: String?
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .emphasis {
                    inline.children.forEach { emphasisText = $0.literal() }
                }
            }
        }
        #expect(emphasisText == "em")
        }
    }

    @Test("inlineOnly parses links")
    func inlineOnlyParsesLinks() {
        let source = "see [text](http://example.com) ok"
        MarkdownDocument.withParsedDocument(source, options: .inlineOnly) { doc in

        #expect(soleBlock(doc)?.kind == .paragraph)

        let inlines = inlines(doc)
        #expect(inlines.map(\.kind) == [.text, .link, .text])
        #expect(inlines.map(\.literal) == ["see ", nil, " ok"])

        var linkURL: String?
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { inline in
                if inline.kind == .link { linkURL = inline.url() }
            }
        }
        #expect(linkURL == "http://example.com")
        }
    }

    @Test("inlineOnly does not turn a 4-space indent into a code block")
    func inlineOnlyNoIndentedCodeBlock() {
        let source = "    indented code"
        MarkdownDocument.withParsedDocument(source, options: .inlineOnly) { doc in

        #expect(soleBlock(doc)?.kind == .paragraph)
        let inlines = inlines(doc)
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.first?.literal == "    indented code")
        }
    }

    @Test("inlineOnly leaves a block quote marker as literal text")
    func inlineOnlyNoBlockQuote() {
        let source = "> not a quote"
        MarkdownDocument.withParsedDocument(source, options: .inlineOnly) { doc in

        #expect(soleBlock(doc)?.kind == .paragraph)
        #expect(inlines(doc).first?.literal == "> not a quote")
        }
    }

    @Test(
        "inline-only modes consolidate adjacent text nodes",
        arguments: [
            ("_f", "_f"),
            ("[t", "[t"),
            ("a\\*b", "a*b"),
            ("a&amp;b", "a&b"),
        ]
    )
    func inlineOnlyConsolidatesText(source: String, merged: String) {
        for options in [MarkdownDocument.ParseOptions.inlineOnly, .preserveWhitespace] {
            MarkdownDocument.withParsedDocument(source, options: options) { doc in
                let inlines = inlines(doc)
                #expect(inlines.map(\.kind) == [.text])
                #expect(inlines.first?.literal == merged)
            }
        }
    }

    // MARK: - preserveWhitespace

    @Test("preserveWhitespace is a superset that includes inlineOnly")
    func preserveWhitespaceImpliesInlineOnly() {
        #expect(MarkdownDocument.ParseOptions.preserveWhitespace.contains(.inlineOnly))
    }

    @Test("preserveWhitespace keeps leading/trailing whitespace and blank lines")
    func preserveWhitespaceKeepsWhitespace() {
        let source = "   leading   spaces\n\n\ntrailing  "
        MarkdownDocument.withParsedDocument(source, options: .preserveWhitespace) { doc in

        let block = soleBlock(doc)
        #expect(block?.kind == .paragraph)
        #expect(block?.count == 1)

        let inlines = inlines(doc)
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.first?.literal == "   leading   spaces\n\n\ntrailing  ")
        }
    }

    @Test("preserveWhitespace and inlineOnly produce an identical tree")
    func preserveWhitespaceMatchesInlineOnlyAST() {
        let source = "  # x\n\n  *y*  \n\n> z"
        MarkdownDocument.withParsedDocument(source, options: .inlineOnly) { inlineOnly in
            MarkdownDocument.withParsedDocument(source, options: .preserveWhitespace) { preserve in
                #expect(dump(inlineOnly) == dump(preserve))
            }
        }
    }
}
