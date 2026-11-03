/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Lines of extended URL autolink candidates whose domains are not valid (Autolinks (extension)).
///
/// A candidate whose domain is not valid stays text, and the candidates after it are recognized as if it were absent, so
/// a line of 40,000 such candidates, about 340 KB of source, parses well within the time limit.
@Suite("Runs of scheme autolink candidates with invalid domains")
struct InvalidDomainSchemeAutolinkRunTests {
    private static let options: [MarkdownDocument.ParseOptions] = [.gfmAutolink, [.gfmAutolink, .inlineOnly]]

    @Test(arguments: options)
    func candidatesWithPunctuationDomainsAreText(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("(http://(http://", options: options) == """
            document
              paragraph
                text "(http://(http://"

            """)
    }

    @Test(arguments: options)
    func candidateWithValidDomainLinks(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("(http://a(http://a", options: options) == """
            document
              paragraph
                text "("
                link "http://a(http://a" ""
                  text "http://a(http://a"

            """)
    }

    @Test(.timeLimit(.minutes(1)), arguments: options)
    func longRunOfCandidatesWithPunctuationDomainsIsText(options: MarkdownDocument.ParseOptions) {
        let source = String(repeating: "(http://", count: 40_000)
        #expect(TreeDump.dump(source, options: options) == """
            document
              paragraph
                text "\(source)"

            """)
    }

    /// Each candidate but the last has the domain `a_http`, which is not valid. The final `_` ends the paragraph, so
    /// the last candidate's domain is `a` and the `_`, as trailing punctuation, stays outside its link.
    @Test(.timeLimit(.minutes(1)), arguments: options)
    func longRunOfCandidatesWithUnderscoreDomainsLinksOnlyTheLast(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(String(repeating: "http://a_", count: 40_000), options: options) == """
            document
              paragraph
                text "\(String(repeating: "http://a_", count: 39_999))"
                link "http://a" ""
                  text "http://a"
                text "_"

            """)
    }
}
