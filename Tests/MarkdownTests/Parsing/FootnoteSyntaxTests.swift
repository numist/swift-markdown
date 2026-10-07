/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// Markdown parsing recognizes no footnotes, so footnote syntax is a link reference definition whose label begins
/// with `^`, and a reference to it is a link (spec "Link reference definitions").
@Suite("Footnote syntax")
struct FootnoteSyntaxTests {
    @Test("a footnote reference and definition are a link and a link reference definition")
    func referenceAndDefinition() {
        let document = Document(parsing: "a[^n]\n\n[^n]: /u\n", source: nil, options: [])
        #expect(document.debugDescription(options: .printSourceLocations) == """
            Document @1:1-3:9
            └─ Paragraph @1:1-1:6
               ├─ Text @1:1-1:2 "a"
               └─ Link @1:2-1:6 destination: "/u"
                  └─ Text @1:3-1:5 "^n"
            """)
    }
}
