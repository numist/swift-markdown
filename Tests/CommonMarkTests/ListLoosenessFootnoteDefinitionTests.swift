/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// List tightness when a blank line follows a footnote definition inside a list item.
///
/// A list is loose if its items, or two blocks of one item, are separated by a blank line (Lists). A footnote
/// definition is a container block, so a blank line after it separates it from the next item or the next block of
/// its item. Each expected value is the tightness of every list in the document, in document order.
@Suite("List looseness after a footnote definition")
struct ListLoosenessFootnoteDefinitionTests {

    static let cases: [(markdown: String, tight: [Bool])] = [
        ("- [^x]: a\n\n- b", [false]),
        ("- a\n  [^x]: c\n\n- b", [false]),
        ("- [^b]: x\n\n- b\n", [false]),
        ("- [^b]: x\n\n  b\n", [false]),
        ("- a\n- [^b]: x\n\n  b\n", [false]),
        ("- [^b]: x\n\n\n- b\n", [false]),
        ("- a\n- [^b]: x\n\n", [true]),
        ("- - [^b]: x\n\n- b\n", [false, true]),
        ("- - [^b]: x\n\n  - b\n", [true, false]),
        ("> - [^b]: x\n>\n> - b\n", [false]),
        ("1. [^b]: x\n\n2. b\n", [false]),
        ("- [^b]: x\n- b\n", [true]),
        ("- [^b]: x\n  b\n", [true]),
        ("- [^f]: x\n\n      y\n- c", [true]),
    ]

    @Test("tightness", arguments: cases)
    func tightness(_ testCase: (markdown: String, tight: [Bool])) {
        let options: MarkdownDocument.ParseOptions = [.footnotes, .tables, .strikethrough, .tasklist, .attributes]
        let tight = MarkdownDocument.withParsedDocument(testCase.markdown, options: options) { document in
            var tight: [Bool] = []
            collectTightness(document.root, into: &tight)
            return tight
        }
        #expect(tight == testCase.tight, "\(testCase.markdown.debugDescription)")
    }

    private func collectTightness(_ node: borrowing MarkdownNode, into tight: inout [Bool]) {
        if case .list(let info) = node.kind { tight.append(info.tight) }
        node.children.forEach { collectTightness($0, into: &tight) }
    }
}
