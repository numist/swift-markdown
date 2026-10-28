/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Adjacent text produced by character escapes, entities and smart punctuation is merged into one text node whose
/// content is a run of the stored segments, with no new segments when the pieces are already adjacent.
@Suite("Merging adjacent text stores few segments")
struct TextMergeSegmentCountTests {

    @Test(arguments: [
        ("a &amp; b &lt; c", 6),
        ("a\\*b\\*c", 6),
        ("a&amp;b&amp;c&amp;d", 8),
        ("[a] [b] [c] it's", 13),
        ("*a **b *c", 7),
        ("a _b *c_ d* e", 10),
    ])
    func segmentCount(_ source: String, _ segments: Int) {
        let measured = MarkdownDocument.withParsedDocument(source, options: []) { $0._segmentCount }
        #expect(measured == segments)
    }

    @Test(arguments: [
        ("x ... y ... z", 6),
        ("*a* it's b", 7),
    ])
    func smartSegmentCount(_ source: String, _ segments: Int) {
        let measured = MarkdownDocument.withParsedDocument(source, options: [.smart]) { $0._segmentCount }
        #expect(measured == segments)
    }
}
