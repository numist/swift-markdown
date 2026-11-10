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

    /// The kind of node a shape nests `depth` deep, from its name.
    static func nestedKind(_ shape: String) -> MarkdownNode.Kind {
        switch shape {
        case "emphasis", "emphasis around an email", "emphasis around smart quotes",
             "emphasis around a footnote-shaped bracket across a line", "emphasis around caret brackets": .emphasis
        case "strong emphasis": .strong
        case "strikethrough": .strikethrough
        case "images", "links in images": .image
        case "attributes": .attribute
        default: preconditionFailure("unknown shape \(shape)")
        }
    }

    static let inlineShapes = [
        "emphasis", "strong emphasis", "strikethrough", "images", "links in images", "attributes",
        "emphasis around an email", "emphasis around smart quotes",
        "emphasis around a footnote-shaped bracket across a line", "emphasis around caret brackets",
    ]

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("deep inline nesting parses without exhausting a 512 KB stack", arguments: inlineShapes, [
        MarkdownDocument.ParseOptions([.attributes, .strikethrough, .smart, .gfmAutolink, .footnotes, .sourcePosition]),
        [.attributes, .strikethrough, .smart, .gfmAutolink, .footnotes],
        [.attributes, .strikethrough, .smart, .gfmAutolink, .inlineOnly],
    ])
    func inlineNesting(_ shape: String, options: MarkdownDocument.ParseOptions) throws {
        let source = Self.inlineSource(shape)
        let kind = Self.nestedKind(shape)
        let nesting = try #require(Self.nestingOnSmallStack(source, options: options) { $0 == kind })
        #expect(nesting.blocks == 1, "\(shape)")
        #expect(nesting.nested == Self.depth, "\(shape)")
    }

    /// The reference sits at the bottom of the quotes; its definition, at the top level, follows them.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("a footnote reference in deeply nested block quotes parses without exhausting a 512 KB stack", arguments: [
        MarkdownDocument.ParseOptions.footnotes,
        [.footnotes, .sourcePosition],
    ])
    func blockQuoteNesting(_ options: MarkdownDocument.ParseOptions) throws {
        let source = String(repeating: ">", count: Self.depth) + " x[^a]\n\n[^a]: y\n"
        let nesting = try #require(Self.nestingOnSmallStack(source, options: options) { $0 == .blockQuote })
        #expect(nesting.blocks == 2)
        #expect(nesting.nested == Self.depth)
    }

    /// The reference sits in the innermost item; its definition, at the top level, follows the lists.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("a footnote reference in deeply nested lists parses without exhausting a 512 KB stack", arguments: [
        MarkdownDocument.ParseOptions.footnotes,
        [.footnotes, .sourcePosition],
    ])
    func listNesting(_ options: MarkdownDocument.ParseOptions) throws {
        let source = String(repeating: "- ", count: Self.depth) + "x[^a]\n\n[^a]: y\n"
        let nesting = try #require(Self.nestingOnSmallStack(source, options: options) {
            if case .list = $0 { true } else { false }
        })
        #expect(nesting.blocks == 2)
        #expect(nesting.nested == Self.depth)
    }

    /// Each definition opens inside the one before it; the outermost and the innermost are referenced, and move to the
    /// document's end.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test("deeply nested footnote definitions parse without exhausting a 512 KB stack", arguments: [
        MarkdownDocument.ParseOptions.footnotes,
        [.footnotes, .sourcePosition],
    ])
    func footnoteDefinitionNesting(_ options: MarkdownDocument.ParseOptions) throws {
        let source = "x[^a][^b]\n\n" + String(repeating: "[^a]: ", count: Self.depth - 1) + "[^b]: y\n"
        let nesting = try #require(Self.nestingOnSmallStack(source, options: options) { $0 == .footnoteDefinition })
        #expect(nesting.blocks == 3)
        #expect(nesting.nested == 2)
    }

    /// The number of top-level blocks and of nodes whose kind `isNested` accepts, or `nil` where no small-stack thread
    /// can run the parse. The count walks the tree without recursion, so it fits on the same stack.
    private static func nestingOnSmallStack(
        _ source: String,
        options: MarkdownDocument.ParseOptions,
        counting isNested: @escaping @Sendable (MarkdownNode.Kind) -> Bool
    ) -> (blocks: Int, nested: Int)? {
        onThread(stackSize: 512 * 1024) {
            MarkdownDocument.withParsedDocument(source, options: options) { document in
                var blocks = 0
                document.root.children.forEach { _ in blocks += 1 }
                var nested = 0
                var node = document.root.firstChild
                while let current = node {
                    if isNested(current.kind) {
                        nested += 1
                    }
                    if let child = current.firstChild {
                        node = child
                        continue
                    }
                    node = nil
                    var ancestor: MarkdownNode? = current
                    while let candidate = ancestor {
                        if let sibling = candidate.next {
                            node = sibling
                            break
                        }
                        ancestor = candidate.parent
                    }
                }
                return (blocks, nested)
            }
        }
    }
}
