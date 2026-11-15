/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Disallowed Raw HTML (extension) filters only the listed tag names; a tag name is an ASCII letter
/// followed by letters, digits or `-` (Raw HTML), so a longer name that starts with a listed one is left untouched.
@Suite("HTML renderer tagfilter")
struct HTMLRendererTagfilterTests {

    @Test("a tag name that extends a disallowed name is left untouched")
    func extendedTagName() {
        let html = MarkdownDocument.withParsedDocument("<title1> <title-x> <scripts> <script>\n", options: []) { doc in
            HTMLRenderer.render(doc, tagfilter: true)
        }
        #expect(html == "<p><title1> <title-x> <scripts> &lt;script></p>\n")
    }
}
