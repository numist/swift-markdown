/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Storage growth for many email addresses interleaved with smart punctuation: ellipses, dashes, single quotes, double
/// quotes paired around a word, and lone double quotes.
///
/// Each of these glyphs is stored apart from the text around it, so a paragraph of addresses separated by them is one
/// text run of many pieces. Splitting that run into email links must store content in proportion to the input.
@Suite("Email autolinks among smart punctuation store linear content")
struct EmailAutolinkSmartPunctuationSegmentGrowthTests {

    @Test("segment count grows linearly with the addresses", arguments: [
        "a@b.c ...",
        "a@b.c --",
        "a@b.c '",
        "a@b.c \"x\" ",
        "a@b.c \"",
    ], [
        MarkdownDocument.ParseOptions([.gfmAutolink, .smart]),
        [.gfmAutolink, .smart, .inlineOnly],
    ])
    func linearSegments(_ unit: String, _ options: MarkdownDocument.ParseOptions) {
        let source = String(repeating: unit, count: 2000)
        let (segments, links) = MarkdownDocument.withParsedDocument(source, options: options) { document in
            var links = 0
            document.root.children.forEach { paragraph in
                paragraph.children.forEach { inline in
                    if case .link = inline.kind { links += 1 }
                }
            }
            return (document._segmentCount, links)
        }
        #expect(links == 2000)
        #expect(segments <= 16 * source.utf8.count + 256, "\(segments) segments for \(source.utf8.count) bytes")
    }
}
