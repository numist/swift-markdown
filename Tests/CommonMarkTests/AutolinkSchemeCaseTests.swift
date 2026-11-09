/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The scheme of an extended url autolink (Autolinks (extension)) matches `http://`, `https://` or `ftp://` in any
/// case, and the destination and link text keep the source's case.
@Suite("Extended url autolink scheme case")
struct AutolinkSchemeCaseTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    @Test("a scheme in any case links, preserving case", arguments: [
        ("HTTP://e.e", """
            document
              paragraph
                link "HTTP://e.e" ""
                  text "HTTP://e.e"

            """),
        ("Http://e.e", """
            document
              paragraph
                link "Http://e.e" ""
                  text "Http://e.e"

            """),
        ("hTTp://e.e", """
            document
              paragraph
                link "hTTp://e.e" ""
                  text "hTTp://e.e"

            """),
        ("HTTPS://x.io", """
            document
              paragraph
                link "HTTPS://x.io" ""
                  text "HTTPS://x.io"

            """),
        ("FTP://x.io", """
            document
              paragraph
                link "FTP://x.io" ""
                  text "FTP://x.io"

            """),
        ("http://e.e", """
            document
              paragraph
                link "http://e.e" ""
                  text "http://e.e"

            """),
    ])
    func schemeCaseLinks(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: Self.options) == tree)
    }

    @Test("another scheme (`xttp://`) is text")
    func unrecognizedSchemeNoLink() {
        #expect(TreeDump.dump("xttp://e", options: Self.options) == """
            document
              paragraph
                text "xttp://e"

            """)
    }

    @Test("`WWW.` is not `www.`, so it is text")
    func wwwIsCaseSensitive() {
        #expect(TreeDump.dump("WWW.e.f", options: Self.options) == """
            document
              paragraph
                text "WWW.e.f"

            """)
    }
}
