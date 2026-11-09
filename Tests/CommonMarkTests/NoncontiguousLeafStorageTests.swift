/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Storage for paragraphs and setext headings whose lines are not contiguous in the source.
///
/// Such content is a list of its source lines joined by line endings. It is copied into the materialized string buffer
/// only where a block structure needs contiguous bytes, and then once. The empty document's buffer holds one byte, the
/// line ending that joins lines.
@Suite("Content of non-contiguous lines is copied at most once")
struct NoncontiguousLeafStorageTests {

    private func materializedSize(_ source: String, options: MarkdownDocument.ParseOptions = []) -> Int {
        MarkdownDocument.withParsedDocument(source, options: options) { $0._materializedStringSize }
    }

    @Test("the empty document holds the line ending")
    func emptyDocument() {
        #expect(materializedSize("") == 1)
    }

    @Test("a setext heading in a block quote copies its text once")
    func setextHeadingInBlockQuote() {
        // "abc\ndef"
        #expect(materializedSize("> abc\n> def\n> ===\n") == 1 + 7)
        #expect(materializedSize("> abc\n> def\n> ===\n", options: .sourcePosition) == 1 + 7)
    }

    @Test("a setext heading after a definition in a block quote copies its lines once")
    func setextHeadingAfterDefinitionInBlockQuote() {
        // "[x]: /u\nabc"
        #expect(materializedSize("> [x]: /u\n> abc\n> ===\n") == 1 + 11)
    }
}
