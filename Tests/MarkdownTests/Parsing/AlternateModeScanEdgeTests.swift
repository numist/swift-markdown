/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Autolinking) @_spi(Footnotes) @_spi(InlineOnly) import Markdown
import Testing

struct AlternateModeScanEdgeTests {
    private func tree(_ markdown: String, _ options: ParseOptions = [.cmarkBugCompatibility, .gfmAutolink, .footnotes]) -> String {
        Document(parsing: markdown, options: options).debugDescription()
    }

    @Test(arguments: [
        ("> [^a\n> b]", "Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"[^]\""),
        ("x " + String(repeating: "`", count: 81) + "y", "Document\n└─ Paragraph\n   └─ Text \"x " + String(repeating: "`", count: 81) + "y\""),
        ("xmpp:a@b.c/d", "Document\n└─ Paragraph\n   ├─ Text \"\"\n   ├─ Link destination: \"xmpp:a@b.c/d\"\n   │  └─ Text \"xmpp:a@b.c/d\"\n   └─ Text \"\""),
        ("a@b@c.d", "Document\n└─ Paragraph\n   ├─ Text \"a@\"\n   ├─ Link destination: \"mailto:b@c.d\"\n   │  └─ Text \"b@c.d\"\n   └─ Text \"\""),
        ("a@ x", "Document\n└─ Paragraph\n   └─ Text \"a@ x\""),
        ("a@b.c9", "Document\n└─ Paragraph\n   └─ Text \"a@b.c9\""),
        ("a@b", "Document\n└─ Paragraph\n   └─ Text \"a@b\""),
        ("www.a\\_b.c", "Document\n└─ Paragraph\n   └─ Text \"www.a_b.c\""),
        ("http://-x", "Document\n└─ Paragraph\n   └─ Text \"http://-x\""),
    ] as [(String, String)])
    func scan(_ markdown: String, _ expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test func definitionWithEscapedAngleBracketInDestination() {
        #expect(tree("[a]: <b\\>c>\n\n[a]", []) == "Document\n└─ Paragraph\n   └─ Link destination: \"b>c\"\n      └─ Text \"a\"")
    }

    @Test func destinationFollowedBySpacesAtEndOfInlineContent() {
        #expect(tree("[](a ", .preserveWhitespace) == "Document\n└─ Paragraph\n   └─ Text \"[](a \"")
    }
}
