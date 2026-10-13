/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parsing deeply nested constructs on a thread with a small stack.
///
/// Parsing must not crash on any input. Nesting tens of thousands deep fits in a few tens of kilobytes of source, so
/// parsing must not use stack in proportion to nesting depth: a 512 KB secondary-thread stack has to suffice.
@Suite("Deep nesting parses on a small stack")
struct DeepNestingStackTests {

    static let depth = 20_000

    /// A shape's source, from its name (the test arguments are names, so failure output stays readable).
    static func inlineSource(_ shape: String) -> String {
        switch shape {
        case "emphasis": String(repeating: "*a ", count: depth) + String(repeating: "b* ", count: depth)
        case "strong emphasis": String(repeating: "**a ", count: depth) + String(repeating: "b** ", count: depth)
        case "strikethrough": String(repeating: "~~a ", count: depth) + String(repeating: "b~~ ", count: depth)
        case "images": String(repeating: "![", count: depth) + "x" + String(repeating: "](u)", count: depth)
        case "links in images": String(repeating: "![[", count: depth) + "x" + String(repeating: "](u)](v)", count: depth)
        case "attributes": String(repeating: "^[", count: depth) + "x" + String(repeating: "](k: v)", count: depth)
        case "emphasis around an email": String(repeating: "*a ", count: depth) + "a@b.c" + String(repeating: " b*", count: depth)
        case "emphasis around smart quotes": String(repeating: "*a ", count: depth) + "'x' \"y\"" + String(repeating: " b*", count: depth)
        case "emphasis around a footnote-shaped bracket across a line": String(repeating: "*a ", count: depth) + "[^x\ny]" + String(repeating: " b*", count: depth)
        case "emphasis around caret brackets": String(repeating: "*a ", count: depth) + "x[^[]]y" + String(repeating: " b*", count: depth)
        default: preconditionFailure("unknown shape \(shape)")
        }
    }

    static let inlineShapes = [
        "emphasis", "strong emphasis", "strikethrough", "images", "links in images", "attributes",
        "emphasis around an email", "emphasis around smart quotes",
        "emphasis around a footnote-shaped bracket across a line", "emphasis around caret brackets",
    ]

    @Test("deep inline nesting parses without exhausting a 512 KB stack", arguments: inlineShapes, [
        MarkdownDocument.ParseOptions([.attributes, .strikethrough, .smart, .gfmAutolink, .footnotes, .sourcePosition]),
        [.attributes, .strikethrough, .smart, .gfmAutolink, .footnotes],
        [.attributes, .strikethrough, .smart, .gfmAutolink, .inlineOnly],
    ])
    func inlineNesting(_ shape: String, options: MarkdownDocument.ParseOptions) {
        let source = Self.inlineSource(shape)
        let blocks = Self.topLevelBlocksOnSmallStack(source, options: options)
        #expect(blocks == 1, "\(shape)")
    }

    /// The reference sits at the bottom of the quotes; its definition, at the top level, follows them.
    @Test("a footnote reference in deeply nested block quotes parses without exhausting a 512 KB stack", arguments: [
        MarkdownDocument.ParseOptions.footnotes,
        [.footnotes, .sourcePosition],
    ])
    func blockQuoteNesting(_ options: MarkdownDocument.ParseOptions) {
        let source = String(repeating: ">", count: Self.depth) + " x[^a]\n\n[^a]: y\n"
        let blocks = Self.topLevelBlocksOnSmallStack(source, options: options)
        #expect(blocks == 2)
    }

    private static func topLevelBlocksOnSmallStack(_ source: String, options: MarkdownDocument.ParseOptions) -> Int {
        onThread(stackSize: 512 * 1024) {
            MarkdownDocument.withParsedDocument(source, options: options) { document in
                var count = 0
                document.root.children.forEach { _ in count += 1 }
                return count
            }
        }
    }
}
