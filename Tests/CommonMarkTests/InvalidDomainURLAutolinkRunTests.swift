/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Runs of extended URL autolink candidates with invalid domains")
struct InvalidDomainURLAutolinkRunTests {
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

    @Test(arguments: options)
    func longRunOfCandidatesWithPunctuationDomainsIsText(options: MarkdownDocument.ParseOptions) {
        let source = String(repeating: "(http://", count: 100)
        #expect(TreeDump.dump(source, options: options) == """
            document
              paragraph
                text "\(source)"

            """)
    }

    // Every candidate but the last has the domain `a_http`, whose last segment holds an underscore, so it is not valid
    // (Autolinks (extension)). The domain check never examines the paragraph's last character, so the final `_` leaves
    // the last candidate's domain valid and, as trailing punctuation, stays outside the link.
    @Test(arguments: options)
    func longRunOfCandidatesWithUnderscoreDomainsLinksOnlyTheLast(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(String(repeating: "http://a_", count: 100), options: options) == """
            document
              paragraph
                text "\(String(repeating: "http://a_", count: 99))"
                link "http://a" ""
                  text "http://a"
                text "_"

            """)
    }
}
