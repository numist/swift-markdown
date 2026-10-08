/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// List tightness when a blank line separates a list item's link reference or inline-attribute definitions from
/// another block of that item.
///
/// A list is loose if any of its items directly contains two block-level elements with a blank line between them
/// (Lists), and a definition counts as one of those elements: `- a\n- b\n\n  [ref]: /url\n- d` is loose. That holds
/// whatever follows the definitions, including the end of input or a line that closes the list. A blank line inside
/// a sublist's item makes only that sublist loose. Each expected value is the tightness of every list in the document,
/// in document order.
@Suite("List looseness with a definition as an item's block")
struct ListLoosenessDefinitionBlockTests {

    static let cases: [(markdown: String, tight: [Bool])] = [
        ("- b\n\n  [a]:j\n", [false]),
        ("- b\n\n  [a]:j\n<!--\n", [false]),
        ("- b\n\n  [a]:j\n<div>\n", [false]),
        ("- b\n\n  [a]:j\n# h\n", [false]),
        ("- b\n\n  [a]:j\n> q\n", [false]),
        ("- b\n\n  [a]:j\n```\n", [false]),
        ("- b\n\n  [a]:j\n***\n", [false]),
        ("- b\n\n  [a]:j\n1. c\n", [false, true]),
        ("- b\n\n  [z]:q\n  [a]:j\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n<!--\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n<div>\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n# h\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n> q\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n```\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n***\n", [false]),
        ("- b\n\n  [z]:q\n  [a]:j\n1. c\n", [false, true]),
        ("1. b\n\n   [a]:j\n", [false]),
        ("1. b\n\n   [a]:j\n<!--\n", [false]),
        ("1. b\n\n   [a]:j\n<div>\n", [false]),
        ("1. b\n\n   [a]:j\n# h\n", [false]),
        ("1. b\n\n   [a]:j\n> q\n", [false]),
        ("1. b\n\n   [a]:j\n```\n", [false]),
        ("1. b\n\n   [a]:j\n***\n", [false]),
        ("1. b\n\n   [a]:j\n- c\n", [false, true]),
        ("- b\n\n  [a]: /u \"t\"\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n<!--\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n<div>\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n# h\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n> q\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n```\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n***\n", [false]),
        ("- b\n\n  [a]: /u \"t\"\n1. c\n", [false, true]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n<!--\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n<div>\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n# h\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n> q\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n```\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n***\n", [false]),
        ("- b\n\n  [z]:q\n  [a]: /u \"t\"\n1. c\n", [false, true]),
        ("1. b\n\n   [a]: /u \"t\"\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n<!--\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n<div>\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n# h\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n> q\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n```\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n***\n", [false]),
        ("1. b\n\n   [a]: /u \"t\"\n- c\n", [false, true]),
        ("- b\n\n  ^[a]: k: v\n", [false]),
        ("- b\n\n  ^[a]: k: v\n<!--\n", [false]),
        ("- b\n\n  ^[a]: k: v\n<div>\n", [false]),
        ("- b\n\n  ^[a]: k: v\n# h\n", [false]),
        ("- b\n\n  ^[a]: k: v\n> q\n", [false]),
        ("- b\n\n  ^[a]: k: v\n```\n", [false]),
        ("- b\n\n  ^[a]: k: v\n***\n", [false]),
        ("- b\n\n  ^[a]: k: v\n1. c\n", [false, true]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n<!--\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n<div>\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n# h\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n> q\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n```\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n***\n", [false]),
        ("- b\n\n  [z]:q\n  ^[a]: k: v\n1. c\n", [false, true]),
        ("1. b\n\n   ^[a]: k: v\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n<!--\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n<div>\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n# h\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n> q\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n```\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n***\n", [false]),
        ("1. b\n\n   ^[a]: k: v\n- c\n", [false, true]),
        ("- b\n\n  [a]:j\n---\n", [false]),
        ("- b\n\n  [a]:j\n~~~\n", [false]),
        ("- b\n\n  [a]:j\n<a>\n", [false]),
        ("- b\n\n  [a]:j\n+ c\n", [false, true]),
        ("1. b\n\n   [a]:j\n2) c\n", [false, true]),
        ("- b\n\n  [a]:j\n[^c]: x\n", [false]),
        ("-     code\n\n  [a]:j\n# h\n", [false]),
        ("- > q\n\n  [a]:j\n# h\n", [false]),
        ("- <div>\n\n  [a]:j\n# h\n", [false]),
        ("- # h\n\n  [a]:j\n# h\n", [false]),
        ("- ```\n  x\n  ```\n\n  [a]:j\n# h\n", [false]),
        ("- [^f]: y\n\n  [a]:j\n# h\n", [false]),
        ("- - x\n\n  [a]:j\n# h\n", [false, true]),
        ("> - b\n>\n>   [a]:j\n> # h\n", [false]),
        ("- - b\n\n    [a]:j\n  # h\n", [true, false]),
        ("> - b\n>\n>   [a]:j\n# h\n", [false]),
        ("- - b\n\n    [a]:j\n# h\n", [true, false]),
        ("- b\n\n  [a]:j\n\n# h\n", [false]),
        ("- ***\n\n  [a]:j\n# h\n", [false]),
        ("- [r]: /u\n\n  b\n", [false]),
        ("- a\n- [r]: /u\n\n  b\n", [false]),
        ("- ^[r]: k: v\n\n  b\n", [false]),
        ("- a\n- ^[r]: k: v\n\n  b\n", [false]),
        ("- [r]: /u\n\n  [s]: /v\n", [false]),
        ("- [r]: /u\n- b\n", [true]),
        ("- [r]: /u\n  [s]: /v\n- b\n", [true]),
        ("- [r]: /u\n  # h\n- b\n", [true]),
        ("- [r]: /u\n  ***\n- b\n", [true]),
        ("- [r]: /u\n  > q\n- b\n", [true])
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
