/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// The literal of the first text node in depth-first order, or nil if there is none.
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
internal func firstTextLiteral(_ node: borrowing MarkdownNode) -> String? {
    switch node.content {
    case .text(let segments):
        var joined = ""
        segments.forEach { span in joined += String(copying: span) }
        return joined
    default:
        var found: String? = nil
        node.children.forEach { child in
            if found == nil { found = firstTextLiteral(child) }
        }
        return found
    }
}

/// An `![` that opens no image, having neither an inline destination nor a matching link reference
/// definition, is literal text whose source range starts at the `!`.
@Suite("Unmatched image opener source range")
struct FailedImageMarkerRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    @Test("failed `![` image marker keeps its full literal and starts at the `!` column")
    func failedImageMarkerStartsAtBang() throws {
        try MarkdownDocument.withParsedDocument("![foo]", options: Self.specOptions) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)

            let texts = ranges.filter { $0.kind == .text }
            #expect(texts.count == 1, "the failed `![` must consolidate into a single text run")
            let range = try #require(texts.first?.range)
            #expect(range.lowerBound == Pos(line: 1, column: 1))   // the `!`, not the `f` after `![`
            #expect(range.upperBound == Pos(line: 1, column: 7))   // just past the `]` (6 bytes)

            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
                #expect(firstTextLiteral(doc.root) == "![foo]")
            }
        }
    }
}
