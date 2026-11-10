/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark

/// Reports, for every text node's segments in document order, whether the segment's bytes lie inside the parsed
/// source or in a copy the document made.
///
/// Each line is a segment's text in quotes followed by `source` or `copy`.
internal enum SourceBackedText {

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    internal static func describe(_ source: String, options: MarkdownDocument.ParseOptions) -> String {
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            let sourceBytes = doc.source.span.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }.map { $0 ..< $0 + UInt(buffer.count) }
            }
            var out = ""
            visit(doc.root, sourceBytes: sourceBytes, into: &out)
            return out
        }
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private static func visit(_ node: borrowing MarkdownNode, sourceBytes: Range<UInt>?, into out: inout String) {
        switch node.content {
        case .text(let segments):
            segments.forEach { segment in
                let address = segment.span.withUnsafeBufferPointer { $0.baseAddress.map { UInt(bitPattern: $0) } }
                let inSource = address.map { sourceBytes?.contains($0) ?? false } ?? false
                out += "\"\(String(copying: segment))\" \(inSource ? "source" : "copy")\n"
            }
        default:
            break
        }
        node.children.forEach { visit($0, sourceBytes: sourceBytes, into: &out) }
    }
}
