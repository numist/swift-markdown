/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// List tightness when a blank line follows each kind of block inside a list item, in several list layouts: between
/// two items, between two blocks of one item, after the last item, with two blank lines, in a nested list, in a block
/// quote, and in an ordered list.
///
/// A list is loose if its items, or two blocks of one item, are separated by a blank line (Lists). A blank line that
/// is part of a block, such as one inside a fenced code block or a type 1-5 HTML block, separates nothing. Each
/// expected value is the tightness of every list in the document, in document order.
@Suite("List looseness after each block kind")
struct ListLoosenessBlockKindMatrixTests {

    static let cases: [(markdown: String, tight: [Bool])] = [
        ("- <script>\n\n  b\n", [true]),
        ("- a\n- <script>\n\n  b\n", [true]),
        ("- a\n- <script>\n\n", [true]),
        ("- <!--\n\n  b\n", [true]),
        ("- a\n- <!--\n\n  b\n", [true]),
        ("- a\n- <!--\n\n", [true]),
        ("- <?x\n\n  b\n", [true]),
        ("- a\n- <?x\n\n  b\n", [true]),
        ("- a\n- <?x\n\n", [true]),
        ("- <!X\n\n  b\n", [true]),
        ("- a\n- <!X\n\n  b\n", [true]),
        ("- a\n- <!X\n\n", [true]),
        ("- <![CDATA[x\n\n  b\n", [true]),
        ("- a\n- <![CDATA[x\n\n  b\n", [true]),
        ("- a\n- <![CDATA[x\n\n", [true]),
        ("- <div>\n\n- b\n", [false]),
        ("- <div>\n\n  b\n", [false]),
        ("- a\n- <div>\n\n  b\n", [false]),
        ("- <div>\n\n\n- b\n", [false]),
        ("- a\n- <div>\n\n", [true]),
        ("- - <div>\n\n- b\n", [false, true]),
        ("- - <div>\n\n  - b\n", [true, false]),
        ("> - <div>\n>\n> - b\n", [false]),
        ("1. <div>\n\n2. b\n", [false]),
        ("- <a>\n\n- b\n", [false]),
        ("- <a>\n\n  b\n", [false]),
        ("- a\n- <a>\n\n  b\n", [false]),
        ("- <a>\n\n\n- b\n", [false]),
        ("- a\n- <a>\n\n", [true]),
        ("- - <a>\n\n- b\n", [false, true]),
        ("- - <a>\n\n  - b\n", [true, false]),
        ("> - <a>\n>\n> - b\n", [false]),
        ("1. <a>\n\n2. b\n", [false]),
        ("- > x\n\n- b\n", [false]),
        ("- > x\n\n  b\n", [false]),
        ("- a\n- > x\n\n  b\n", [false]),
        ("- > x\n\n\n- b\n", [false]),
        ("- a\n- > x\n\n", [true]),
        ("- - > x\n\n- b\n", [false, true]),
        ("- - > x\n\n  - b\n", [true, false]),
        ("> - > x\n>\n> - b\n", [false]),
        ("1. > x\n\n2. b\n", [false]),
        ("- > x\n  > y\n\n- b\n", [false]),
        ("- > x\n  > y\n\n  b\n", [false]),
        ("- a\n- > x\n  > y\n\n  b\n", [false]),
        ("- > x\n  > y\n\n\n- b\n", [false]),
        ("- a\n- > x\n  > y\n\n", [true]),
        ("- - > x\n    > y\n\n- b\n", [false, true]),
        ("- - > x\n    > y\n\n  - b\n", [true, false]),
        ("> - > x\n>   > y\n>\n> - b\n", [false]),
        ("1. > x\n   > y\n\n2. b\n", [false]),
        ("- a\n- [^b]: x\n\n", [true]),
        ("- ```\n  x\n  ```\n\n- b\n", [false]),
        ("- ```\n  x\n  ```\n\n  b\n", [false]),
        ("- a\n- ```\n  x\n  ```\n\n  b\n", [false]),
        ("- ```\n  x\n  ```\n\n\n- b\n", [false]),
        ("- a\n- ```\n  x\n  ```\n\n", [true]),
        ("- - ```\n    x\n    ```\n\n- b\n", [false, true]),
        ("- - ```\n    x\n    ```\n\n  - b\n", [true, false]),
        ("> - ```\n>   x\n>   ```\n>\n> - b\n", [false]),
        ("1. ```\n   x\n   ```\n\n2. b\n", [false]),
        ("- ```\n  x\n\n- b\n", [true]),
        ("- ```\n  x\n\n  b\n", [true]),
        ("- a\n- ```\n  x\n\n  b\n", [true]),
        ("- ```\n  x\n\n\n- b\n", [true]),
        ("- a\n- ```\n  x\n\n", [true]),
        ("- - ```\n    x\n\n- b\n", [true, true]),
        ("- - ```\n    x\n\n  - b\n", [true, true]),
        ("> - ```\n>   x\n>\n> - b\n", [true]),
        ("1. ```\n   x\n\n2. b\n", [true]),
        ("-     code\n\n- b\n", [false]),
        ("-     code\n\n  b\n", [false]),
        ("- a\n-     code\n\n  b\n", [false]),
        ("-     code\n\n\n- b\n", [false]),
        ("- a\n-     code\n\n", [true]),
        ("- -     code\n\n- b\n", [false, true]),
        ("- -     code\n\n  - b\n", [true, false]),
        ("> -     code\n>\n> - b\n", [false]),
        ("1.     code\n\n2. b\n", [false]),
        ("- # h\n\n- b\n", [false]),
        ("- # h\n\n  b\n", [false]),
        ("- a\n- # h\n\n  b\n", [false]),
        ("- # h\n\n\n- b\n", [false]),
        ("- a\n- # h\n\n", [true]),
        ("- - # h\n\n- b\n", [false, true]),
        ("- - # h\n\n  - b\n", [true, false]),
        ("> - # h\n>\n> - b\n", [false]),
        ("1. # h\n\n2. b\n", [false]),
        ("- h\n  -\n\n- b\n", [false]),
        ("- h\n  -\n\n  b\n", [false]),
        ("- a\n- h\n  -\n\n  b\n", [false]),
        ("- h\n  -\n\n\n- b\n", [false]),
        ("- a\n- h\n  -\n\n", [true]),
        ("- - h\n    -\n\n- b\n", [false, true]),
        ("- - h\n    -\n\n  - b\n", [true, false]),
        ("> - h\n>   -\n>\n> - b\n", [false]),
        ("1. h\n   -\n\n2. b\n", [false]),
        ("- ***\n\n- b\n", [false]),
        ("- ***\n\n  b\n", [false]),
        ("- a\n- ***\n\n  b\n", [false]),
        ("- ***\n\n\n- b\n", [false]),
        ("- a\n- ***\n\n", [true]),
        ("- - ***\n\n- b\n", [false, true]),
        ("- - ***\n\n  - b\n", [true, false]),
        ("> - ***\n>\n> - b\n", [false]),
        ("1. ***\n\n2. b\n", [false]),
        ("- a\n\n- b\n", [false]),
        ("- a\n\n  b\n", [false]),
        ("- a\n- a\n\n  b\n", [false]),
        ("- a\n\n\n- b\n", [false]),
        ("- a\n- a\n\n", [true]),
        ("- - a\n\n- b\n", [false, true]),
        ("- - a\n\n  - b\n", [true, false]),
        ("> - a\n>\n> - b\n", [false]),
        ("1. a\n\n2. b\n", [false]),
        ("- | a |\n  | - |\n  | c |\n\n- b\n", [false]),
        ("- | a |\n  | - |\n  | c |\n\n  b\n", [false]),
        ("- a\n- | a |\n  | - |\n  | c |\n\n  b\n", [false]),
        ("- | a |\n  | - |\n  | c |\n\n\n- b\n", [false]),
        ("- a\n- | a |\n  | - |\n  | c |\n\n", [true]),
        ("- - | a |\n    | - |\n    | c |\n\n- b\n", [false, true]),
        ("- - | a |\n    | - |\n    | c |\n\n  - b\n", [true, false]),
        ("> - | a |\n>   | - |\n>   | c |\n>\n> - b\n", [false]),
        ("1. | a |\n   | - |\n   | c |\n\n2. b\n", [false]),
        ("- [r]: /u\n\n- b\n", [false]),
        ("- [r]: /u\n\n\n- b\n", [false]),
        ("- a\n- [r]: /u\n\n", [true]),
        ("- - [r]: /u\n\n- b\n", [false, true]),
        ("- - [r]: /u\n\n  - b\n", [true, false]),
        ("> - [r]: /u\n>\n> - b\n", [false]),
        ("1. [r]: /u\n\n2. b\n", [false]),
        ("- ^[r]: k: v\n\n- b\n", [false]),
        ("- ^[r]: k: v\n\n\n- b\n", [false]),
        ("- a\n- ^[r]: k: v\n\n", [true]),
        ("- - ^[r]: k: v\n\n- b\n", [false, true]),
        ("- - ^[r]: k: v\n\n  - b\n", [true, false]),
        ("> - ^[r]: k: v\n>\n> - b\n", [false]),
        ("1. ^[r]: k: v\n\n2. b\n", [false]),
        ("- \n\n- b\n", [false]),
        ("- \n\n  b\n", [true]),
        ("- a\n- \n\n  b\n", [true]),
        ("- \n\n\n- b\n", [false]),
        ("- a\n- \n\n", [true]),
        ("- - \n\n- b\n", [false, true]),
        ("- - \n\n  - b\n", [true, false]),
        ("> - \n>\n> - b\n", [false]),
        ("1. \n\n2. b\n", [false]),
        ("- - x\n\n- b\n", [false, true]),
        ("- - x\n\n  b\n", [false, true]),
        ("- a\n- - x\n\n  b\n", [false, true]),
        ("- - x\n\n\n- b\n", [false, true]),
        ("- a\n- - x\n\n", [true, true]),
        ("- - - x\n\n- b\n", [false, true, true]),
        ("- - - x\n\n  - b\n", [true, false, true]),
        ("> - - x\n>\n> - b\n", [false, true]),
        ("1. - x\n\n2. b\n", [false, true])
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
