/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// List tightness when a list item holds link reference, inline-attribute or footnote definitions, with or without a
/// blank line before them, by the line that follows.
///
/// A list is loose if its items, or two blocks of one item, are separated by a blank line (Lists). A following line
/// that continues the definitions' paragraph leaves a paragraph after the blank line; a following item is separated
/// from the item by the blank line. Each expected value is the tightness of every list in the document, in document
/// order.
@Suite("List looseness around a list item's definitions")
struct ListLoosenessAroundDefinitionsTests {

    static let cases: [(markdown: String, tight: [Bool])] = [
        ("- b\n\n  [a]:j\nx\n", [false]),
        ("- b\n\n  [a]:j\n- c\n", [false]),
        ("- b\n\n  [a]:j\n    code\n", [false]),
        ("- b\n\n  [a]:j\na\n---\n", [false]),
        ("- b\n\n  [a]:j\n|a|\n|-|\n", [false]),
        ("- b\n  [a]:j\n", [true]),
        ("- b\n  [a]:j\nx\n", [true]),
        ("- b\n  [a]:j\n<!--\n", [true]),
        ("- b\n  [a]:j\n<div>\n", [true]),
        ("- b\n  [a]:j\n# h\n", [true]),
        ("- b\n  [a]:j\n> q\n", [true]),
        ("- b\n  [a]:j\n```\n", [true]),
        ("- b\n  [a]:j\n***\n", [true]),
        ("- b\n  [a]:j\n- c\n", [true]),
        ("- b\n  [a]:j\n1. c\n", [true, true]),
        ("- b\n  [a]:j\n    code\n", [true]),
        ("- b\n  [a]:j\na\n---\n", [true]),
        ("- b\n  [a]:j\n|a|\n|-|\n", [true]),
        ("- b\n\n  [z]:q\n  [a]:j\nx\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n- c\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n    code\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\na\n---\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n|a|\n|-|\n", [false]),
        ("1. b\n\n   [a]:j\nx\n", [false]),
        ("1. b\n\n   [a]:j\n1. c\n", [false]),
        ("1. b\n\n   [a]:j\n    code\n", [false]),
        ("1. b\n\n   [a]:j\na\n---\n", [false]),
        ("1. b\n\n   [a]:j\n|a|\n|-|\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\nx\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n- c\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n    code\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\na\n---\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n|a|\n|-|\n", [false]),
        ("- b\n  [a]: /u \"t\"\n", [true]),
        ("- b\n  [a]: /u \"t\"\nx\n", [true]),
        ("- b\n  [a]: /u \"t\"\n<!--\n", [true]),
        ("- b\n  [a]: /u \"t\"\n<div>\n", [true]),
        ("- b\n  [a]: /u \"t\"\n# h\n", [true]),
        ("- b\n  [a]: /u \"t\"\n> q\n", [true]),
        ("- b\n  [a]: /u \"t\"\n```\n", [true]),
        ("- b\n  [a]: /u \"t\"\n***\n", [true]),
        ("- b\n  [a]: /u \"t\"\n- c\n", [true]),
        ("- b\n  [a]: /u \"t\"\n1. c\n", [true, true]),
        ("- b\n  [a]: /u \"t\"\n    code\n", [true]),
        ("- b\n  [a]: /u \"t\"\na\n---\n", [true]),
        ("- b\n  [a]: /u \"t\"\n|a|\n|-|\n", [true]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\nx\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n- c\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n    code\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\na\n---\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n|a|\n|-|\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\nx\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n1. c\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n    code\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\na\n---\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n|a|\n|-|\n", [false]),
        ("- b\n\n  ^[a]: k: v\nx\n", [false]),
        ("- b\n\n  ^[a]: k: v\n- c\n", [false]),
        ("- b\n\n  ^[a]: k: v\n    code\n", [false]),
        ("- b\n\n  ^[a]: k: v\na\n---\n", [false]),
        ("- b\n\n  ^[a]: k: v\n|a|\n|-|\n", [false]),
        ("- b\n  ^[a]: k: v\n", [true]),
        ("- b\n  ^[a]: k: v\nx\n", [true]),
        ("- b\n  ^[a]: k: v\n<!--\n", [true]),
        ("- b\n  ^[a]: k: v\n<div>\n", [true]),
        ("- b\n  ^[a]: k: v\n# h\n", [true]),
        ("- b\n  ^[a]: k: v\n> q\n", [true]),
        ("- b\n  ^[a]: k: v\n```\n", [true]),
        ("- b\n  ^[a]: k: v\n***\n", [true]),
        ("- b\n  ^[a]: k: v\n- c\n", [true]),
        ("- b\n  ^[a]: k: v\n1. c\n", [true, true]),
        ("- b\n  ^[a]: k: v\n    code\n", [true]),
        ("- b\n  ^[a]: k: v\na\n---\n", [true]),
        ("- b\n  ^[a]: k: v\n|a|\n|-|\n", [true]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\nx\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n- c\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n    code\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\na\n---\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n|a|\n|-|\n", [false]),
        ("1. b\n\n   ^[a]: k: v\nx\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n1. c\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n    code\n", [false]),
        ("1. b\n\n   ^[a]: k: v\na\n---\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n|a|\n|-|\n", [false]),
        ("- b\n\n  [^a]: x\n", [false]),
        ("- b\n\n  [^a]: x\nx\n", [false]),
        ("- b\n\n  [^a]: x\n<!--\n", [false]),
        ("- b\n\n  [^a]: x\n<div>\n", [false]),
        ("- b\n\n  [^a]: x\n# h\n", [false]),
        ("- b\n\n  [^a]: x\n> q\n", [false]),
        ("- b\n\n  [^a]: x\n```\n", [false]),
        ("- b\n\n  [^a]: x\n***\n", [false]),
        ("- b\n\n  [^a]: x\n- c\n", [false]),
        ("- b\n\n  [^a]: x\n1. c\n", [false, true]),
        ("- b\n\n  [^a]: x\n    code\n", [false]),
        ("- b\n\n  [^a]: x\na\n---\n", [false]),
        ("- b\n\n  [^a]: x\n|a|\n|-|\n", [false]),
        ("- b\n  [^a]: x\n", [true]),
        ("- b\n  [^a]: x\nx\n", [true]),
        ("- b\n  [^a]: x\n<!--\n", [true]),
        ("- b\n  [^a]: x\n<div>\n", [true]),
        ("- b\n  [^a]: x\n# h\n", [true]),
        ("- b\n  [^a]: x\n> q\n", [true]),
        ("- b\n  [^a]: x\n```\n", [true]),
        ("- b\n  [^a]: x\n***\n", [true]),
        ("- b\n  [^a]: x\n- c\n", [true]),
        ("- b\n  [^a]: x\n1. c\n", [true, true]),
        ("- b\n  [^a]: x\n    code\n", [true]),
        ("- b\n  [^a]: x\na\n---\n", [true]),
        ("- b\n  [^a]: x\n|a|\n|-|\n", [true]),
        ("- b\n\n  [z]:q\n  [^a]: x\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\nx\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n<!--\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n<div>\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n# h\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n> q\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n```\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n***\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n- c\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n1. c\n", [false, true]),
        ("- b\n\n  [z]:q\n  [^a]: x\n    code\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\na\n---\n", [false]),
        ("- b\n\n  [z]:q\n  [^a]: x\n|a|\n|-|\n", [false]),
        ("1. b\n\n   [^a]: x\n", [false]),
        ("1. b\n\n   [^a]: x\nx\n", [false]),
        ("1. b\n\n   [^a]: x\n<!--\n", [false]),
        ("1. b\n\n   [^a]: x\n<div>\n", [false]),
        ("1. b\n\n   [^a]: x\n# h\n", [false]),
        ("1. b\n\n   [^a]: x\n> q\n", [false]),
        ("1. b\n\n   [^a]: x\n```\n", [false]),
        ("1. b\n\n   [^a]: x\n***\n", [false]),
        ("1. b\n\n   [^a]: x\n- c\n", [false, true]),
        ("1. b\n\n   [^a]: x\n1. c\n", [false]),
        ("1. b\n\n   [^a]: x\n    code\n", [false]),
        ("1. b\n\n   [^a]: x\na\n---\n", [false]),
        ("1. b\n\n   [^a]: x\n|a|\n|-|\n", [false])
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
