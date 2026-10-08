/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A leading byte order mark is not part of the document's content, but the line it begins is still a line, so a
/// document holding only a byte order mark has one line.
@Suite("Line count of a document beginning with a byte order mark")
struct ByteOrderMarkLineCountTests {

    @Test("a document of only a byte order mark has one line")
    func byteOrderMarkOnly() {
        #expect(MarkdownDocument.withParsedDocument("\u{FEFF}", options: []) { $0.lineCount } == 1)
    }

    @Test("a document of only a byte order mark has one line in inline-only parsing")
    func byteOrderMarkOnlyInlineOnly() {
        #expect(MarkdownDocument.withParsedDocument("\u{FEFF}", options: [.inlineOnly]) { $0.lineCount } == 1)
    }

    @Test("a byte order mark followed by a line ending is one line")
    func byteOrderMarkThenLineEnding() {
        #expect(MarkdownDocument.withParsedDocument("\u{FEFF}\n", options: []) { $0.lineCount } == 1)
    }

    @Test("a byte order mark followed by text is one line")
    func byteOrderMarkThenText() {
        #expect(MarkdownDocument.withParsedDocument("\u{FEFF}a", options: []) { $0.lineCount } == 1)
    }

    @Test("an empty document has no lines")
    func emptyDocument() {
        #expect(MarkdownDocument.withParsedDocument("", options: []) { $0.lineCount } == 0)
    }
}
