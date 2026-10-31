/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Document source text")
struct DocumentSourceTests {

    @Test("source is the parsed text from both initializers and from withParsedDocument", arguments: [
        "",
        "plain",
        "\u{FEFF}# Heading\n",
        "caf\u{E9} \u{1F600}\n> \u{4E2D}\u{6587}\n",
        "a\0b\r\nc",
    ])
    func sourceFromEveryEntryPoint(text: String) {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(String(copying: MarkdownDocument(parsing: text).source) == text)
        #expect(String(copying: MarkdownDocument(parsing: text.utf8Span).source) == text)
        let viaClosure = MarkdownDocument.withParsedDocument(text) { String(copying: $0.source) }
        #expect(viaClosure == text)
    }
}
