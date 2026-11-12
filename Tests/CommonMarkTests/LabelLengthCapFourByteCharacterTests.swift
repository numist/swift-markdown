/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A label has at most 999 characters (Links), however many bytes each takes: 999 four-byte characters fit, and 1,000
/// characters don't, whether all four-byte or ending in one-byte characters. A footnote definition's label is capped
/// likewise, so a `[^label]:` whose label is longer begins no definition and stays paragraph text.
@Suite("Label length cap with four-byte characters")
struct LabelLengthCapFourByteCharacterTests {
    private static let wideCharacter = "\u{1F600}"

    private static func wide(_ count: Int) -> String {
        String(repeating: wideCharacter, count: count)
    }

    @Test
    func footnoteReferenceOf999FourByteCharactersResolves() {
        #expect(TreeDump.dump("x[^\(Self.wide(999))]\n\n[^\(Self.wide(999))]: d", options: .footnotes) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "\(Self.wide(999))"
                paragraph
                  text "d"

            """)
    }

    @Test(arguments: [wide(1000), wide(999) + "a", wide(998) + "aa"])
    func footnoteReferenceOf1000CharactersIsText(_ label: String) {
        #expect(TreeDump.dump("x[^\(label)]\n\n[^\(label)]: d", options: .footnotes) == """
            document
              paragraph
                text "x[^\(label)]"
              paragraph
                text "[^\(label)]: d"

            """)
    }

    /// The reference's label normalizes to the defined 999-character label, so only its own length keeps it from
    /// resolving.
    @Test
    func footnoteReferenceOf1000CharactersMatchingADefinitionIsText() {
        #expect(TreeDump.dump("x[^\(Self.wide(999)) ]\n\n[^\(Self.wide(999))]: d", options: .footnotes) == """
            document
              paragraph
                text "x[^\(Self.wide(999)) ]"

            """)
    }

    @Test
    func shortcutReferenceOf999FourByteCharactersResolves() {
        #expect(TreeDump.dump("[\(Self.wide(999))]\n\n[\(Self.wide(999))]: /u", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(Self.wide(999))"

            """)
    }

    @Test(arguments: [wide(1000), wide(999) + "a", wide(998) + "aa"])
    func shortcutReferenceOf1000CharactersIsText(_ label: String) {
        #expect(TreeDump.dump("[\(label)]\n\n[\(label)]: /u", options: []) == """
            document
              paragraph
                text "[\(label)]"
              paragraph
                text "[\(label)]: /u"

            """)
    }

    /// The reference's label normalizes to the defined 999-character label, so only its own length keeps it from
    /// resolving.
    @Test
    func shortcutReferenceOf1000CharactersMatchingADefinitionIsText() {
        #expect(TreeDump.dump("[\(Self.wide(999)) ]\n\n[\(Self.wide(999))]: /u", options: []) == """
            document
              paragraph
                text "[\(Self.wide(999)) ]"

            """)
    }
}
