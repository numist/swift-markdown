/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `www.` followed by a space is an extended www autolink whose final `.` is trailing punctuation, so the link is
/// `www` (Autolinks (extension)). `www.` at the end of the input and `www._` stay text.
@Suite("Extended www autolink without a domain")
struct AutolinkWWWBareTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    @Test("`www.` followed by a space links `www`")
    func domainlessWWWLinksWWW() {
        #expect(TreeDump.dump("www. x", options: Self.options) == """
            document
              paragraph
                link "http://www" ""
                  text "www"
                text ". x"

            """)
    }

    @Test("`www.` at the end of the input is text")
    func wwwAtEndOfInputNotLinked() {
        #expect(TreeDump.dump("www.", options: Self.options) == """
            document
              paragraph
                text "www."

            """)
    }

    @Test("`www.a.b` autolinks")
    func validDomainAutolinks() {
        #expect(TreeDump.dump("www.a.b x", options: Self.options) == """
            document
              paragraph
                link "http://www.a.b" ""
                  text "www.a.b"
                text " x"

            """)
    }

    @Test("`www._` is text")
    func domainlessWWWUnderscoreNotLinked() {
        #expect(TreeDump.dump("www._ x", options: Self.options) == """
            document
              paragraph
                text "www._ x"

            """)
    }
}
