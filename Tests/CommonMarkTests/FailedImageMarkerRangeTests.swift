/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An `![` that opens no image, having neither an inline destination nor a matching link reference
/// definition, is literal text whose source range starts at the `!`.
@Suite("Unmatched image opener source range")
struct FailedImageMarkerRangeTests {

    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The text of every text node's segments, in depth-first order.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private func segmentTexts(_ node: borrowing MarkdownNode) -> [String] {
        var out: [String] = []
        switch node.content {
        case .text(let segments):
            segments.forEach { out.append(String(copying: $0)) }
        default:
            break
        }
        node.children.forEach { out += segmentTexts($0) }
        return out
    }

    @Test("failed `![` image marker keeps its full literal and starts at the `!` column")
    func failedImageMarkerStartsAtBang() {
        #expect(TreeDump.dump("![foo]", options: Self.options, sourceRanges: true) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "![foo]" @1:1-1:7

            """)
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test("the failed `![` image marker's text segments hold its full literal")
    func failedImageMarkerSegments() {
        #expect(MarkdownDocument.withParsedDocument("![foo]", options: Self.options) { segmentTexts($0.root).joined() } == "![foo]")
    }
}
