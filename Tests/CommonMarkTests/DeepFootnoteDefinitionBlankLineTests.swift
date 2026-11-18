/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Blank lines under deep footnote definition nesting")
struct DeepFootnoteDefinitionBlankLineTests {

    static let depth = 40_000

    @Test(arguments: [MarkdownDocument.ParseOptions.footnotes, [.footnotes, .sourcePosition]])
    func blankLinesAfterAParagraph(options: MarkdownDocument.ParseOptions) {
        let markdown = "[^a]\n\n" + String(repeating: "[^b]:", count: Self.depth - 1) + "[^a]:x\n" + String(repeating: "\n", count: Self.depth)
        let tree = TreeDump.dump(markdown, options: options, sourceRanges: options.contains(.sourcePosition))

        if options.contains(.sourcePosition) {
            #expect(tree == """
                document @1:1-40004:1
                  paragraph @1:1-1:5
                    footnote_reference "1" @1:1-1:5
                  footnote_definition "a" @3:199996-3:200002
                    paragraph @3:200001-3:200002
                      text "x" @3:200001-3:200002

                """)
        } else {
            #expect(tree == """
                document
                  paragraph
                    footnote_reference "1"
                  footnote_definition "a"
                    paragraph
                      text "x"

                """)
        }
    }

    @Test(arguments: [MarkdownDocument.ParseOptions.footnotes, [.footnotes, .sourcePosition]])
    func blankLinesInAFencedCodeBlock(options: MarkdownDocument.ParseOptions) {
        let markdown = "[^a]\n\n" + String(repeating: "[^b]:", count: Self.depth - 1) + "[^a]:```\n" + String(repeating: "\n", count: Self.depth)
        let (kinds, literal) = MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
            (dfs(doc).map { TreeDump.describe($0.kind) }, codeBlocks(doc).map(\.literal))
        }

        #expect(kinds == [
            "document", "paragraph", "footnote_reference 1", "footnote_definition",
            "code_block fenced fence='`' length=3 offset=0",
        ])
        #expect(literal == [String(repeating: "\n", count: Self.depth)])
    }
}
