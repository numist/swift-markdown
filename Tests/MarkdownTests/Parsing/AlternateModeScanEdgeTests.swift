/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

struct AlternateModeScanEdgeTests {
    private func tree(_ markdown: String, _ options: ParseOptions) -> String {
        Document(parsing: markdown, options: options).debugDescription()
    }

    @Test func definitionWithEscapedAngleBracketInDestination() {
        #expect(tree("[a]: <b\\>c>\n\n[a]", []) == "Document\n└─ Paragraph\n   └─ Link destination: \"b>c\"\n      └─ Text \"a\"")
    }
}
