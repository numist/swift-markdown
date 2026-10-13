/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for many `://` autolink candidates that fail their domain check, with `.gfmAutolink`.
///
/// A candidate whose domain starts with punctuation, or bears an underscore in its last two labels, is no extended
/// autolink. Rejecting it must cost only its domain, not the rest of a whitespace-free line.
@Suite("Rejected scheme autolink candidates parse in linear time")
struct SchemeAutolinkParseTimeTests {

    static let options: [MarkdownDocument.ParseOptions] = [.gfmAutolink, [.gfmAutolink, .inlineOnly]]

    @Test("a candidate whose domain starts with punctuation stays text", arguments: options)
    func unsafeDomainText(_ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("(http://(http://", options: options) == """
            document
              paragraph
                text "(http://(http://"

            """)
    }

    /// The final candidate's domain is `a`, since trailing punctuation leaves the link.
    @Test("only the final candidate with an underscore domain links", arguments: options)
    func underscoreDomainText(_ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("http://a_http://a_", options: options) == """
            document
              paragraph
                text "http://a_"
                link "http://a" ""
                  text "http://a"
                text "_"

            """)
    }

    @Test("a line of candidates with unsafe domains parses in linear time", arguments: options)
    func unsafeDomains(_ options: MarkdownDocument.ParseOptions) {
        expectLinearParseTime(count: 2000, options: options) { String(repeating: "(http://", count: $0) }
    }

    @Test("a line of candidates with underscore domains parses in linear time", arguments: options)
    func underscoreDomains(_ options: MarkdownDocument.ParseOptions) {
        expectLinearParseTime(count: 2000, options: options) { String(repeating: "http://a_", count: $0) }
    }
}
