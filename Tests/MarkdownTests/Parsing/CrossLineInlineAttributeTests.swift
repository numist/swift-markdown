/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

@Suite("Inline attributes across a line ending")
struct CrossLineInlineAttributeTests {
    private static func tree(_ markdown: String) -> String {
        Document(parsing: markdown)
            .debugDescription(options: .printSourceLocations)
    }

    @Test(arguments: [
        ("> ^[a](\n> b)", """
            Document @1:1-2:5
            └─ BlockQuote @1:1-2:5
               └─ Paragraph @1:3-2:5
                  └─ InlineAttributes @1:3-2:5 attributes: `
            b`
                     └─ Text @1:5-1:6 "a"
            """),
        ("> ^[hi](\n> x)", """
            Document @1:1-2:5
            └─ BlockQuote @1:1-2:5
               └─ Paragraph @1:3-2:5
                  └─ InlineAttributes @1:3-2:5 attributes: `
            x`
                     └─ Text @1:5-1:7 "hi"
            """),
        ("- ^[a](\n  b)", """
            Document @1:1-2:5
            └─ UnorderedList @1:1-2:5
               └─ ListItem @1:1-2:5
                  └─ Paragraph @1:3-2:5
                     └─ InlineAttributes @1:3-2:5 attributes: `
            b`
                        └─ Text @1:5-1:6 "a"
            """),
        (">^[a](b\n>c)", """
            Document @1:1-2:4
            └─ BlockQuote @1:1-2:4
               └─ Paragraph @1:2-2:4
                  └─ InlineAttributes @1:2-2:4 attributes: `b
            c`
                     └─ Text @1:4-1:5 "a"
            """),
    ])
    func crossLineAttributesKeepLineEnding(_ markdown: String, _ expected: String) {
        #expect(Self.tree(markdown) == expected)
    }

    @Test func trailingBracketAfterAttributeIsText() {
        #expect(Document(parsing: "^[](x)[y]").debugDescription() == """
            Document
            └─ Paragraph
               ├─ InlineAttributes attributes: `x`
               └─ Text "[y]"
            """)
        #expect(Document(parsing: ">a^[](x)[\n>c]").debugDescription() == """
            Document
            └─ BlockQuote
               └─ Paragraph
                  ├─ Text "a"
                  ├─ InlineAttributes attributes: `x`
                  ├─ Text "["
                  ├─ SoftBreak
                  └─ Text "c]"
            """)
        // `(ignore)` completes the inline attribute, so `[a b]` can only be a link reference, and no link reference
        // definition names `a b`.
        #expect(Document(parsing: "^[a b]: color: red\n\n>x^[](ignore)[a\n>b]").debugDescription() == """
            Document
            └─ BlockQuote
               └─ Paragraph
                  ├─ Text "x"
                  ├─ InlineAttributes attributes: `ignore`
                  ├─ Text "[a"
                  ├─ SoftBreak
                  └─ Text "b]"
            """)
    }
}
