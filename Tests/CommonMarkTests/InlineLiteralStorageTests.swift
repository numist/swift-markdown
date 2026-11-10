/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A code span, link destination, link title, autolink or code block info string is stored as its source bytes when
/// its value is those bytes, and otherwise is stored once. The stored strings of a document start with one byte, a line
/// feed, so each expected size is one more than the bytes the document's values add.
@Suite("Inline literals and code block info strings store at most one copy")
struct InlineLiteralStorageTests {

    @Test(arguments: [
        // Code spans.
        ("`a`", [], 1),
        ("`a\nb`", [], 4),
        ("> `a\n> b`", [], 4),
        ("> `\\!\n> b`", [], 5),
        // Link destinations and titles.
        ("[x](/u \"t\")", [], 1),
        ("[x](/u?a&b \"t&u\")", [], 1),
        ("[x](/u?a&amp;b \"t&amp;u\")", [], 10),
        ("[x](/u \"\\!\")", [], 2),
        ("> x [x](/u \"a\n> b\")", [], 4),
        ("> x [x](/u \"\\!\n> b\")", [], 4),
        ("> x [x](/u \"&amp;\n> b\")", [], 4),
        ("[x]: /u?a&b \"t&u\"\n\n[x]", [], 1),
        ("[x]: /u?a&amp;b\n\n[x]", [], 7),
        ("> [x]: /u \"a\n> b\"\n\n[x]", [], 4),
        ("> [x]: /u \"\\!\n> b\"\n\n[x]", [], 4),
        ("> [x]: /u \"&amp;\n> b\"\n\n[x]", [], 4),
        // Autolinks.
        ("<http://x?a=1&b=2>", [], 1),
        ("<http://x?a&amp;b>", [], 13),
        ("<a@b.c>", [], 13),
        ("http://a.b", [.gfmAutolink], 1),
        ("www.a.b", [.gfmAutolink], 15),
        ("a@b.c", [.gfmAutolink], 13),
        // Code block info strings.
        ("```a&b\n```", [], 1),
        ("```a&amp;b\n```", [], 4),
    ] as [(String, MarkdownDocument.ParseOptions, Int)])
    func storedStringSize(_ source: String, _ options: MarkdownDocument.ParseOptions, _ size: Int) {
        let measured = MarkdownDocument.withParsedDocument(source, options: options) { $0._materializedStringSize }
        #expect(measured == size)
    }
}
