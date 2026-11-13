/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// Link references expand to at most the larger of 100,000 bytes and the document's byte count of destination and
/// title, charged per resolved reference in document order after backslash escapes and character references are
/// resolved. A reference past that stays text. The trees hold destinations too long to write out, so each run of ten or
/// more of one character other than a space is written `<c×n>`.
struct ReferenceExpansionBudgetTests {

    /// The document's debug description with source locations, with each run of ten or more of one character other
    /// than a space written `<c×n>`.
    private func tree(_ markdown: String) -> String {
        let description = Document(parsing: markdown).debugDescription(options: .printSourceLocations)
        var result = ""
        var characters = description[...]
        while let first = characters.first {
            let run = characters.prefix { $0 == first }
            if run.count >= 10, first != " " {
                result += "<\(first)×\(run.count)>"
            } else {
                result += run
            }
            characters = characters.dropFirst(run.count)
        }
        return result
    }

    private func repeated(_ string: String, _ count: Int) -> String {
        String(repeating: string, count: count)
    }

    @Test func twoUsesOf50000BytesFitExactly() {
        #expect(tree("[a]: <\(repeated("u", 50_000))>\n\n[a] [a] [a]") == """
            Document @1:1-3:12
            └─ Paragraph @3:1-3:12
               ├─ Link @3:1-3:4 destination: "<u×50000>"
               │  └─ Text @3:2-3:3 "a"
               ├─ Text @3:4-3:5 " "
               ├─ Link @3:5-3:8 destination: "<u×50000>"
               │  └─ Text @3:6-3:7 "a"
               └─ Text @3:8-3:12 " [a]"
            """)
    }

    @Test func titleBytesAreCharged() {
        #expect(tree("[a]: <\(repeated("u", 49_990))> \"\(repeated("t", 10))\"\n\n[a] [a] [a]") == """
            Document @1:1-3:12
            └─ Paragraph @3:1-3:12
               ├─ Link @3:1-3:4 destination: "<u×49990>"
               │  └─ Text @3:2-3:3 "a"
               ├─ Text @3:4-3:5 " "
               ├─ Link @3:5-3:8 destination: "<u×49990>"
               │  └─ Text @3:6-3:7 "a"
               └─ Text @3:8-3:12 " [a]"
            """)
        #expect(tree("[a]: <\(repeated("u", 49_990))> \"\(repeated("t", 11))\"\n\n[a] [a] [a]") == """
            Document @1:1-3:12
            └─ Paragraph @3:1-3:12
               ├─ Link @3:1-3:4 destination: "<u×49990>"
               │  └─ Text @3:2-3:3 "a"
               └─ Text @3:4-3:12 " [a] [a]"
            """)
    }

    @Test func aCRLFInATitleIsChargedOneByte() {
        #expect(tree("[a]: <\(repeated("u", 49_990))> \"ttttt\r\ntttt\"\r\n\r\n[a] [a] [a]") == """
            Document @1:1-4:12
            └─ Paragraph @4:1-4:12
               ├─ Link @4:1-4:4 destination: "<u×49990>"
               │  └─ Text @4:2-4:3 "a"
               ├─ Text @4:4-4:5 " "
               ├─ Link @4:5-4:8 destination: "<u×49990>"
               │  └─ Text @4:6-4:7 "a"
               └─ Text @4:8-4:12 " [a]"
            """)
    }

    @Test func aTitleIsChargedAfterBackslashEscapes() {
        #expect(tree("[a]: <\(repeated("u", 49_995))> \"\(repeated("\\*", 5))\"\n\n[a] [a] [a]") == """
            Document @1:1-3:12
            └─ Paragraph @3:1-3:12
               ├─ Link @3:1-3:4 destination: "<u×49995>"
               │  └─ Text @3:2-3:3 "a"
               ├─ Text @3:4-3:5 " "
               ├─ Link @3:5-3:8 destination: "<u×49995>"
               │  └─ Text @3:6-3:7 "a"
               └─ Text @3:8-3:12 " [a]"
            """)
    }

    @Test func aDestinationIsChargedAfterCharacterReferences() {
        let uses = (0..<11).map { _ in "[a]" }.joined(separator: " ")
        #expect(tree("[a]: <\(repeated("&amp;", 10_000))>\n\n\(uses)") == """
            Document @1:1-3:44
            └─ Paragraph @3:1-3:44
               ├─ Link @3:1-3:4 destination: "<&×10000>"
               │  └─ Text @3:2-3:3 "a"
               ├─ Text @3:4-3:5 " "
               ├─ Link @3:5-3:8 destination: "<&×10000>"
               │  └─ Text @3:6-3:7 "a"
               ├─ Text @3:8-3:9 " "
               ├─ Link @3:9-3:12 destination: "<&×10000>"
               │  └─ Text @3:10-3:11 "a"
               ├─ Text @3:12-3:13 " "
               ├─ Link @3:13-3:16 destination: "<&×10000>"
               │  └─ Text @3:14-3:15 "a"
               ├─ Text @3:16-3:17 " "
               ├─ Link @3:17-3:20 destination: "<&×10000>"
               │  └─ Text @3:18-3:19 "a"
               ├─ Text @3:20-3:21 " "
               ├─ Link @3:21-3:24 destination: "<&×10000>"
               │  └─ Text @3:22-3:23 "a"
               ├─ Text @3:24-3:25 " "
               ├─ Link @3:25-3:28 destination: "<&×10000>"
               │  └─ Text @3:26-3:27 "a"
               ├─ Text @3:28-3:29 " "
               ├─ Link @3:29-3:32 destination: "<&×10000>"
               │  └─ Text @3:30-3:31 "a"
               ├─ Text @3:32-3:33 " "
               ├─ Link @3:33-3:36 destination: "<&×10000>"
               │  └─ Text @3:34-3:35 "a"
               ├─ Text @3:36-3:37 " "
               ├─ Link @3:37-3:40 destination: "<&×10000>"
               │  └─ Text @3:38-3:39 "a"
               └─ Text @3:40-3:44 " [a]"
            """)
        let tenUses = (0..<10).map { _ in "[a]" }.joined(separator: " ")
        #expect(tree("[a]: <\(repeated("&amp;", 10_000))x>\n\n\(tenUses)") == """
            Document @1:1-3:40
            └─ Paragraph @3:1-3:40
               ├─ Link @3:1-3:4 destination: "<&×10000>x"
               │  └─ Text @3:2-3:3 "a"
               ├─ Text @3:4-3:5 " "
               ├─ Link @3:5-3:8 destination: "<&×10000>x"
               │  └─ Text @3:6-3:7 "a"
               ├─ Text @3:8-3:9 " "
               ├─ Link @3:9-3:12 destination: "<&×10000>x"
               │  └─ Text @3:10-3:11 "a"
               ├─ Text @3:12-3:13 " "
               ├─ Link @3:13-3:16 destination: "<&×10000>x"
               │  └─ Text @3:14-3:15 "a"
               ├─ Text @3:16-3:17 " "
               ├─ Link @3:17-3:20 destination: "<&×10000>x"
               │  └─ Text @3:18-3:19 "a"
               ├─ Text @3:20-3:21 " "
               ├─ Link @3:21-3:24 destination: "<&×10000>x"
               │  └─ Text @3:22-3:23 "a"
               ├─ Text @3:24-3:25 " "
               ├─ Link @3:25-3:28 destination: "<&×10000>x"
               │  └─ Text @3:26-3:27 "a"
               ├─ Text @3:28-3:29 " "
               ├─ Link @3:29-3:32 destination: "<&×10000>x"
               │  └─ Text @3:30-3:31 "a"
               ├─ Text @3:32-3:33 " "
               ├─ Link @3:33-3:36 destination: "<&×10000>x"
               │  └─ Text @3:34-3:35 "a"
               └─ Text @3:36-3:40 " [a]"
            """)
    }

    @Test func aNULIsChargedAsTheThreeBytesOfTheReplacementCharacter() {
        #expect(tree("[a]: <\(repeated("u", 49_997))\u{0}>\n\n[a] [a] [a]") == """
            Document @1:1-3:12
            └─ Paragraph @3:1-3:12
               ├─ Link @3:1-3:4 destination: "<u×49997>\u{FFFD}"
               │  └─ Text @3:2-3:3 "a"
               ├─ Text @3:4-3:5 " "
               ├─ Link @3:5-3:8 destination: "<u×49997>\u{FFFD}"
               │  └─ Text @3:6-3:7 "a"
               └─ Text @3:8-3:12 " [a]"
            """)
        #expect(tree("[a]: <\(repeated("u", 49_998))\u{0}>\n\n[a] [a] [a]") == """
            Document @1:1-3:12
            └─ Paragraph @3:1-3:12
               ├─ Link @3:1-3:4 destination: "<u×49998>\u{FFFD}"
               │  └─ Text @3:2-3:3 "a"
               └─ Text @3:4-3:12 " [a] [a]"
            """)
    }

    @Test func aDocumentLargerThan100000BytesIsTheBudget() {
        let head = "[a]: <\(repeated("u", 60_000))>\n\n[a] [a]\n\n"
        let fits = head + repeated("z", 120_000 - head.utf8.count)
        let short = head + repeated("z", 119_999 - head.utf8.count)
        #expect(fits.utf8.count == 120_000)
        #expect(short.utf8.count == 119_999)
        #expect(tree(fits) == """
            Document @1:1-5:59983
            ├─ Paragraph @3:1-3:8
            │  ├─ Link @3:1-3:4 destination: "<u×60000>"
            │  │  └─ Text @3:2-3:3 "a"
            │  ├─ Text @3:4-3:5 " "
            │  └─ Link @3:5-3:8 destination: "<u×60000>"
            │     └─ Text @3:6-3:7 "a"
            └─ Paragraph @5:1-5:59983
               └─ Text @5:1-5:59983 "<z×59982>"
            """)
        #expect(tree(short) == """
            Document @1:1-5:59982
            ├─ Paragraph @3:1-3:8
            │  ├─ Link @3:1-3:4 destination: "<u×60000>"
            │  │  └─ Text @3:2-3:3 "a"
            │  └─ Text @3:4-3:8 " [a]"
            └─ Paragraph @5:1-5:59982
               └─ Text @5:1-5:59982 "<z×59981>"
            """)
        #expect(tree("[a]: <\(repeated("u", 200_000))>\n\n[a] [a]") == """
            Document @1:1-3:8
            └─ Paragraph @3:1-3:8
               ├─ Link @3:1-3:4 destination: "<u×200000>"
               │  └─ Text @3:2-3:3 "a"
               └─ Text @3:4-3:8 " [a]"
            """)
    }

    @Test func referencesAreChargedInDocumentOrderAcrossBlocks() {
        #expect(tree("[a] [x]\n\n[a]: <\(repeated("u", 50_000))>\n\n# [a]\n\n> [a]") == """
            Document @1:1-7:6
            ├─ Paragraph @1:1-1:8
            │  ├─ Link @1:1-1:4 destination: "<u×50000>"
            │  │  └─ Text @1:2-1:3 "a"
            │  └─ Text @1:4-1:8 " [x]"
            ├─ Heading @5:1-5:6 level: 1
            │  └─ Link @5:3-5:6 destination: "<u×50000>"
            │     └─ Text @5:4-5:5 "a"
            └─ BlockQuote @7:1-7:6
               └─ Paragraph @7:3-7:6
                  └─ Text @7:3-7:6 "[a]"
            """)
        #expect(tree("|[a]|\n|-|\n|[a]|\n\n[a]: <\(repeated("u", 50_000))>\n\n[a]") == """
            Document @1:1-7:4
            ├─ Table @1:1-3:6 alignments: |-|
            │  ├─ Head @1:1-1:6
            │  │  └─ Cell @1:2-1:5
            │  │     └─ Link @1:2-1:5 destination: "<u×50000>"
            │  │        └─ Text @1:3-1:4 "a"
            │  └─ Body @3:1-3:6
            │     └─ Row @3:1-3:6
            │        └─ Cell @3:2-3:5
            │           └─ Link @3:2-3:5 destination: "<u×50000>"
            │              └─ Text @3:3-3:4 "a"
            └─ Paragraph @7:1-7:4
               └─ Text @7:1-7:4 "[a]"
            """)
    }

    @Test func imageCollapsedAndFullReferencesAreCharged() {
        #expect(tree("[a]: <\(repeated("u", 50_000))>\n\n![a] [a][] [x][a]") == """
            Document @1:1-3:18
            └─ Paragraph @3:1-3:18
               ├─ Image @3:1-3:5 source: "<u×50000>"
               │  └─ Text @3:3-3:4 "a"
               ├─ Text @3:5-3:6 " "
               ├─ Link @3:6-3:11 destination: "<u×50000>"
               │  └─ Text @3:7-3:8 "a"
               └─ Text @3:11-3:18 " [x][a]"
            """)
    }

    @Test func aReferenceInLinkTextIsChargedOnce() {
        #expect(tree("[a]: <\(repeated("u", 50_000))>\n\n[[a]](/v) [a] [a]") == """
            Document @1:1-3:18
            └─ Paragraph @3:1-3:18
               ├─ Text @3:1-3:2 "["
               ├─ Link @3:2-3:5 destination: "<u×50000>"
               │  └─ Text @3:3-3:4 "a"
               ├─ Text @3:5-3:11 "](/v) "
               ├─ Link @3:11-3:14 destination: "<u×50000>"
               │  └─ Text @3:12-3:13 "a"
               └─ Text @3:14-3:18 " [a]"
            """)
    }

    @Test func inlineAttributeReferencesAreNotCharged() {
        #expect(tree("[a]: <\(repeated("u", 50_000))>\n^[b]: k: 1\n\n[a] ^[x][b] ^[y][b] [a] [a]") == """
            Document @1:1-4:28
            └─ Paragraph @4:1-4:28
               ├─ Link @4:1-4:4 destination: "<u×50000>"
               │  └─ Text @4:2-4:3 "a"
               ├─ Text @4:4-4:5 " "
               ├─ InlineAttributes @4:5-4:12 attributes: `k: 1`
               │  └─ Text @4:7-4:8 "x"
               ├─ Text @4:12-4:13 " "
               ├─ InlineAttributes @4:13-4:20 attributes: `k: 1`
               │  └─ Text @4:15-4:16 "y"
               ├─ Text @4:20-4:21 " "
               ├─ Link @4:21-4:24 destination: "<u×50000>"
               │  └─ Text @4:22-4:23 "a"
               └─ Text @4:24-4:28 " [a]"
            """)
    }
}
