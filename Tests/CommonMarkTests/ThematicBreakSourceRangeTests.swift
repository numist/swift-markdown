/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of thematic breaks. A thematic break runs from its first marker character to just past its last
/// marker character on its own line, so trailing spaces or tabs and any following lines are outside it.
@Suite("Thematic break source ranges")
struct ThematicBreakSourceRangeTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func ranges(in markdown: String) -> [String] {
        MarkdownDocument.withParsedDocument(markdown, options: Self.options) { document in
            var out: [String] = []
            collectRanges(document.root, into: &out)
            return out
        }
    }

    @Test func testBreak() {
        #expect(ranges(in: "***") == ["document 1:1-1:4", "thematicBreak 1:1-1:4"])
    }

    @Test func testBreakWithInteriorSpaces() {
        #expect(ranges(in: "- - -") == ["document 1:1-1:6", "thematicBreak 1:1-1:6"])
    }

    @Test func testBreakWithTrailingSpaces() {
        #expect(ranges(in: "***   \nx") == [
            "document 1:1-2:2",
            "thematicBreak 1:1-1:4",
            "paragraph 2:1-2:2",
            "text 2:1-2:2",
        ])
    }

    @Test func testBreakWithTrailingTab() {
        #expect(ranges(in: "***\t\nx") == [
            "document 1:1-2:2",
            "thematicBreak 1:1-1:4",
            "paragraph 2:1-2:2",
            "text 2:1-2:2",
        ])
    }

    @Test func testIndentedBreak() {
        #expect(ranges(in: "  ***") == ["document 1:1-1:6", "thematicBreak 1:3-1:6"])
    }

    @Test func testBreakThenBlankLineAndParagraph() {
        #expect(ranges(in: "***\n\nx") == [
            "document 1:1-3:2",
            "thematicBreak 1:1-1:4",
            "paragraph 3:1-3:2",
            "text 3:1-3:2",
        ])
    }

    @Test func testBreakThenBlankLines() {
        #expect(ranges(in: "***\n\n\n") == ["document 1:1-3:1", "thematicBreak 1:1-1:4"])
    }

    @Test func testBreakThenCRLFBlankLineAndParagraph() {
        #expect(ranges(in: "***\r\n\r\nx") == [
            "document 1:1-3:2",
            "thematicBreak 1:1-1:4",
            "paragraph 3:1-3:2",
            "text 3:1-3:2",
        ])
    }

    @Test func testBreakInBlockQuoteThenBlankLine() {
        #expect(ranges(in: "> ***\n>\nx") == [
            "document 1:1-3:2",
            "blockQuote 1:1-2:2",
            "thematicBreak 1:3-1:6",
            "paragraph 3:1-3:2",
            "text 3:1-3:2",
        ])
    }

    @Test func testBreakWithTrailingSpacesInListItem() {
        #expect(ranges(in: "- ***  \n- b") == [
            "document 1:1-2:4",
            "list 1:1-2:4",
            "item 1:1-1:6",
            "thematicBreak 1:3-1:6",
            "item 2:1-2:4",
            "paragraph 2:3-2:4",
            "text 2:3-2:4",
        ])
    }

    @Test func testConsecutiveBreaks() {
        #expect(ranges(in: "***\n---") == [
            "document 1:1-2:4",
            "thematicBreak 1:1-1:4",
            "thematicBreak 2:1-2:4",
        ])
    }
}

// File scope because a `MarkdownNode` is `~Escapable`, so an instance-method closure can't capture it.
private func collectRanges(_ node: borrowing MarkdownNode, into out: inout [String]) {
    let name = switch node.kind {
    case .document: "document"
    case .blockQuote: "blockQuote"
    case .list: "list"
    case .item: "item"
    case .paragraph: "paragraph"
    case .thematicBreak: "thematicBreak"
    case .text: "text"
    default: "\(node.kind)"
    }
    let range = node.sourceRange.map {
        "\($0.lowerBound.line):\($0.lowerBound.column)-\($0.upperBound.line):\($0.upperBound.column)"
    } ?? "nil"
    out.append("\(name) \(range)")
    node.children.forEach { collectRanges($0, into: &out) }
}
