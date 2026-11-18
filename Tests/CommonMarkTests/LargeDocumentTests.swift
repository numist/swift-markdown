/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Foundation
import Testing

@Suite("Documents whose offsets or lengths exceed 2 GiB")
struct LargeDocumentTests {

    // The large documents need several gigabytes of memory, so they run only when this variable is set.
    static let largeDocumentsEnabled = ProcessInfo.processInfo.environment["COMMONMARK_LARGE_DOCUMENT_TESTS"] != nil

    static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .tables]

    // The heading is read from the source in pieces between block quote markers, and the table's escaped pipe and
    // entity are copied, so the tail checks both borrowed and copied content at offsets past the first block's.
    static let tail = "> c\n> d\n> ===\n\n| x | y\\|z |\n| - | - |\n| &amp; | `q` |\n"

    static func document(_ prefix: String, _ byte: Character, count: Int, _ suffix: String) -> String {
        var markdown = prefix
        markdown.reserveCapacity(prefix.utf8.count + count + suffix.utf8.count)
        let piece = String(repeating: byte, count: min(count, 1 << 20))
        for _ in 0..<(count / piece.count) {
            markdown += piece
        }
        markdown += String(repeating: byte, count: count % piece.count)
        markdown += suffix
        return markdown
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    static func dumpSizesOfFirstBlock(_ document: borrowing MarkdownDocument) -> String {
        var out = ""
        if let block = document.root.firstChild {
            dumpSizes(block, depth: 0, into: &out)
        }
        return out
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private static func dumpSizes(_ node: borrowing MarkdownNode, depth: Int, into out: inout String) {
        out += String(repeating: "  ", count: depth) + TreeDump.describe(node.kind)
        switch node.content {
        case .text(let segments): out += " segments=\(segments.count) bytes=\(segments.byteCount)"
        case .codeBlock(_, let body): out += " segments=\(body.count) bytes=\(body.byteCount)"
        default: break
        }
        if let range = node.sourceRange {
            out += " @\(range.lowerBound.line):\(range.lowerBound.column)-\(range.upperBound.line):\(range.upperBound.column)"
        }
        out += "\n"
        node.children.forEach { dumpSizes($0, depth: depth + 1, into: &out) }
    }

    static func dumpAfterFirstBlock(_ document: borrowing MarkdownDocument) -> String {
        var out = ""
        var block = document.root.firstChild?.next
        while let current = block {
            out += TreeDump.dump(current, sourceRanges: true)
            block = current.next
        }
        return out
    }

    static let tailTree = """
        block_quote @3:1-5:6
          heading 1 @3:3-5:6
            text "c" @3:3-3:4
            softbreak @-
            text "d" @4:3-4:4
        table @7:1-9:16
          table_header @7:1-7:13
            table_cell align=none colspan=1 rowspan=1 @7:3-7:4
              text "x" @7:3-7:4
            table_cell align=none colspan=1 rowspan=1 @7:7-7:11
              text "y|z" @7:7-7:11
          table_row @9:1-9:16
            table_cell align=none colspan=1 rowspan=1 @9:3-9:8
              text "&" @9:3-9:8
            table_cell align=none colspan=1 rowspan=1 @9:11-9:14
              code "q" @9:11-9:14

        """

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    static func dumpBlocks(_ markdown: String) -> (first: String, rest: String) {
        MarkdownDocument.withParsedDocument(markdown, options: options) { document in
            (dumpSizesOfFirstBlock(document), dumpAfterFirstBlock(document))
        }
    }

    @Test
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func paragraph() {
        let (first, rest) = Self.dumpBlocks(Self.document("", "a", count: 3, " *b*\n\n" + Self.tail))
        #expect(first == """
            paragraph @1:1-1:8
              text segments=1 bytes=4 @1:1-1:5
              emph @1:5-1:8
                text segments=1 bytes=1 @1:6-1:7

            """)
        #expect(rest == Self.tailTree)
    }

    @Test(.enabled(if: largeDocumentsEnabled))
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func paragraphLongerThanTwoGiB() {
        let (first, rest) = Self.dumpBlocks(Self.document("", "a", count: 2_147_483_648, " *b*\n\n" + Self.tail))
        #expect(first == """
            paragraph @1:1-1:2147483653
              text segments=1 bytes=2147483649 @1:1-1:2147483650
              emph @1:2147483650-1:2147483653
                text segments=1 bytes=1 @1:2147483651-1:2147483652

            """)
        #expect(rest == Self.tailTree)
    }

    @Test
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func codeBlockOfNULs() {
        let (first, rest) = Self.dumpBlocks(Self.document("    ", "\0", count: 2, "\n\n" + Self.tail))
        #expect(first == """
            code_block indented fence=none length=0 offset=0 segments=2 bytes=7 @1:5-1:7

            """)
        #expect(rest == Self.tailTree)
    }

    @Test(.enabled(if: largeDocumentsEnabled))
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    func codeBlockOfNULsMaterializingMoreThanTwoGiB() {
        let (first, rest) = Self.dumpBlocks(Self.document("    ", "\0", count: 715_827_883, "\n\n" + Self.tail))
        #expect(first == """
            code_block indented fence=none length=0 offset=0 segments=2 bytes=2147483650 @1:5-1:715827888

            """)
        #expect(rest == Self.tailTree)
    }
}
