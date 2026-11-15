/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("BasicTests")
struct BasicTests {

    @Test("empty document parses to a single .document node with no children")
    func emptyDocument() {
        let source = ""
        MarkdownDocument.withParsedDocument(source) { doc in
        let root = doc.root
        let kind = root.kind
        let isLeaf = root.isLeaf
        var count = 0
        root.children.forEach { _ in
            count += 1
        }

        #expect(kind == .document)
        #expect(isLeaf)
        #expect(count == 0)
        }
    }

    @Test("a single line of text parses to a paragraph holding one text node")
    func singleLineParagraph() {
        let source = "hello"
        MarkdownDocument.withParsedDocument(source) { doc in
        let root = doc.root
        let rootKind = root.kind

        var visited: [MarkdownNode.Kind] = []
        var textLiteral: String?
        root.children.forEach { paragraph in
            visited.append(paragraph.kind)
            paragraph.children.forEach { inline in
                visited.append(inline.kind)
                if inline.kind == .text {
                    textLiteral = inline.literal()
                }
            }
        }

        #expect(rootKind == .document)
        #expect(visited == [.paragraph, .text])
        #expect(textLiteral == "hello")
        }
    }

    @Test("parent/sibling navigation links work")
    func navigation() {
        let source = "a\n\nb"
        MarkdownDocument.withParsedDocument(source) { doc in
        let root = doc.root

        var paragraphParentKinds: [MarkdownNode.Kind?] = []
        var textParentKinds: [MarkdownNode.Kind?] = []
        var nextLiterals: [String?] = []
        var previousLiterals: [String?] = []
        var textHasSibling = false

        root.children.forEach { paragraph in
            paragraphParentKinds.append(paragraph.parent?.kind)
            nextLiterals.append(paragraph.next?.firstChild?.literal())
            previousLiterals.append(paragraph.previous?.firstChild?.literal())
            paragraph.children.forEach { text in
                textParentKinds.append(text.parent?.kind)
                textHasSibling = textHasSibling || text.next != nil || text.previous != nil
            }
        }

        #expect(paragraphParentKinds == [.document, .document])
        #expect(textParentKinds == [.paragraph, .paragraph])
        #expect(nextLiterals == ["b", nil])
        #expect(previousLiterals == [nil, "a"])
        #expect(!textHasSibling)
        }
    }

    @Test("MarkdownNode.Kind classifies block vs. inline correctly")
    func kindClassification() {
        let source = "- a\n\n```\nx\n```"
        let parsedKinds = MarkdownDocument.withParsedDocument(source) { doc in
            var kinds: [MarkdownNode.Kind] = []
            doc.root.children.forEach { block in
                kinds.append(block.kind)
            }
            return kinds
        }
        guard parsedKinds.count == 2, case .list = parsedKinds[0], case .codeBlock = parsedKinds[1] else {
            Issue.record("expected a list and a code block, got \(parsedKinds)")
            return
        }

        let blocks: [MarkdownNode.Kind] = [
            .document, .blockQuote, parsedKinds[0], .item(checked: nil), parsedKinds[1], .htmlBlock,
            .paragraph, .heading(level: 1), .thematicBreak, .footnoteDefinition, .table,
            .tableRow(isHeader: true), .tableCell(alignment: .none, columns: 1, rows: 1),
        ]
        let inlines: [MarkdownNode.Kind] = [
            .text, .softBreak, .lineBreak, .codeInline(backtickCount: 1), .htmlInline, .emphasis,
            .strong, .link, .image, .footnoteReference(index: 1), .strikethrough, .attribute,
        ]
        #expect(blocks.map(\.isBlock) == Array(repeating: true, count: 13))
        #expect(blocks.map(\.isInline) == Array(repeating: false, count: 13))
        #expect(inlines.map(\.isBlock) == Array(repeating: false, count: 12))
        #expect(inlines.map(\.isInline) == Array(repeating: true, count: 12))
    }

    @Test("options are exposed on the parsed document")
    func optionsRoundTrip() {
        let source = "x"
        MarkdownDocument.withParsedDocument(source, options: [.smart, .footnotes]) { doc in
        let opts = doc.options
        #expect(opts.contains(.smart))
        #expect(opts.contains(.footnotes))
        #expect(!opts.contains(.strikethrough))
        }
    }
    
    @Test("the benchmarks' sample document parses to its full tree")
    func benchmarkSampleDocument() {
        let sample = """
        # Hello, World

        This is a *simple* markdown document with some **bold** text, a [link](https://example.com), and a code span: `let x = 1`.

        - First item
        - Second item
        - Third item
        """

        #expect(TreeDump.dump(sample, options: []) == """
            document
              heading 1
                text "Hello, World"
              paragraph
                text "This is a "
                emph
                  text "simple"
                text " markdown document with some "
                strong
                  text "bold"
                text " text, a "
                link "https://example.com" ""
                  text "link"
                text ", and a code span: "
                code "let x = 1"
                text "."
              list bullet '-' tight
                item
                  paragraph
                    text "First item"
                item
                  paragraph
                    text "Second item"
                item
                  paragraph
                    text "Third item"

            """)
    }
}
