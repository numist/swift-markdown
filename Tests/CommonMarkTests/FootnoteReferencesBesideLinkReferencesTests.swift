/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Many footnote references and many uses of a link reference with a long destination in one paragraph: every
/// footnote reference and every link reference resolves (spec "Link reference definitions"; GFM "Footnotes").
@Suite("Footnote references beside link references")
struct FootnoteReferencesBesideLinkReferencesTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes,
    ]

    /// The number of dumped nodes whose type name is `kind`.
    private func count(_ kind: String, in dump: String) -> Int {
        dump.split(separator: "\n").filter { $0.drop(while: { $0 == " " }).hasPrefix(kind + " ") }.count
    }

    @Test func everyReferenceResolves() {
        let markdown = "[^n]: note\n\n[bar]: /" + String(repeating: "a", count: 2000) + "\n\n"
            + Array(repeating: "[^n]", count: 100).joined(separator: " ") + " "
            + Array(repeating: "[bar]", count: 60).joined(separator: " ")
        let dump = TreeDump.dump(markdown, options: Self.options)
        #expect(count("footnote_reference", in: dump) == 100)
        #expect(count("link", in: dump) == 60)
    }
}
