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
        #expect(tree("[a]: <\(repeated("u", 25_000))>\n\n![a] [a][] [x][a] [a] [a]") == """
            Document @1:1-3:26
            └─ Paragraph @3:1-3:26
               ├─ Image @3:1-3:5 source: "<u×25000>"
               │  └─ Text @3:3-3:4 "a"
               ├─ Text @3:5-3:6 " "
               ├─ Link @3:6-3:11 destination: "<u×25000>"
               │  └─ Text @3:7-3:8 "a"
               ├─ Text @3:11-3:12 " "
               ├─ Link @3:12-3:18 destination: "<u×25000>"
               │  └─ Text @3:13-3:14 "x"
               ├─ Text @3:18-3:19 " "
               ├─ Link @3:19-3:22 destination: "<u×25000>"
               │  └─ Text @3:20-3:21 "a"
               └─ Text @3:22-3:26 " [a]"
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

    /// Attribute and link labels are separate namespaces, so an inline attribute label never reads or charges a link
    /// definition of the same label, and the 100 references fit the budget exactly.
    @Test func inlineAttributeLabelsThatMatchLinkDefinitionsAreNotCharged() {
        let markdown = "[a]: \(repeated("u", 1000))\n\n^[x][a]\(repeated(" [a]", 100))"
        #expect(markdown.utf8.count == 1414)
        #expect(tree(markdown) == """
            Document @1:1-3:408
            └─ Paragraph @3:1-3:408
               ├─ Text @3:1-3:9 "^[x] "
               ├─ Link @3:9-3:12 destination: "<u×1000>"
               │  └─ Text @3:10-3:11 "a"
               ├─ Text @3:12-3:13 " "
               ├─ Link @3:13-3:16 destination: "<u×1000>"
               │  └─ Text @3:14-3:15 "a"
               ├─ Text @3:16-3:17 " "
               ├─ Link @3:17-3:20 destination: "<u×1000>"
               │  └─ Text @3:18-3:19 "a"
               ├─ Text @3:20-3:21 " "
               ├─ Link @3:21-3:24 destination: "<u×1000>"
               │  └─ Text @3:22-3:23 "a"
               ├─ Text @3:24-3:25 " "
               ├─ Link @3:25-3:28 destination: "<u×1000>"
               │  └─ Text @3:26-3:27 "a"
               ├─ Text @3:28-3:29 " "
               ├─ Link @3:29-3:32 destination: "<u×1000>"
               │  └─ Text @3:30-3:31 "a"
               ├─ Text @3:32-3:33 " "
               ├─ Link @3:33-3:36 destination: "<u×1000>"
               │  └─ Text @3:34-3:35 "a"
               ├─ Text @3:36-3:37 " "
               ├─ Link @3:37-3:40 destination: "<u×1000>"
               │  └─ Text @3:38-3:39 "a"
               ├─ Text @3:40-3:41 " "
               ├─ Link @3:41-3:44 destination: "<u×1000>"
               │  └─ Text @3:42-3:43 "a"
               ├─ Text @3:44-3:45 " "
               ├─ Link @3:45-3:48 destination: "<u×1000>"
               │  └─ Text @3:46-3:47 "a"
               ├─ Text @3:48-3:49 " "
               ├─ Link @3:49-3:52 destination: "<u×1000>"
               │  └─ Text @3:50-3:51 "a"
               ├─ Text @3:52-3:53 " "
               ├─ Link @3:53-3:56 destination: "<u×1000>"
               │  └─ Text @3:54-3:55 "a"
               ├─ Text @3:56-3:57 " "
               ├─ Link @3:57-3:60 destination: "<u×1000>"
               │  └─ Text @3:58-3:59 "a"
               ├─ Text @3:60-3:61 " "
               ├─ Link @3:61-3:64 destination: "<u×1000>"
               │  └─ Text @3:62-3:63 "a"
               ├─ Text @3:64-3:65 " "
               ├─ Link @3:65-3:68 destination: "<u×1000>"
               │  └─ Text @3:66-3:67 "a"
               ├─ Text @3:68-3:69 " "
               ├─ Link @3:69-3:72 destination: "<u×1000>"
               │  └─ Text @3:70-3:71 "a"
               ├─ Text @3:72-3:73 " "
               ├─ Link @3:73-3:76 destination: "<u×1000>"
               │  └─ Text @3:74-3:75 "a"
               ├─ Text @3:76-3:77 " "
               ├─ Link @3:77-3:80 destination: "<u×1000>"
               │  └─ Text @3:78-3:79 "a"
               ├─ Text @3:80-3:81 " "
               ├─ Link @3:81-3:84 destination: "<u×1000>"
               │  └─ Text @3:82-3:83 "a"
               ├─ Text @3:84-3:85 " "
               ├─ Link @3:85-3:88 destination: "<u×1000>"
               │  └─ Text @3:86-3:87 "a"
               ├─ Text @3:88-3:89 " "
               ├─ Link @3:89-3:92 destination: "<u×1000>"
               │  └─ Text @3:90-3:91 "a"
               ├─ Text @3:92-3:93 " "
               ├─ Link @3:93-3:96 destination: "<u×1000>"
               │  └─ Text @3:94-3:95 "a"
               ├─ Text @3:96-3:97 " "
               ├─ Link @3:97-3:100 destination: "<u×1000>"
               │  └─ Text @3:98-3:99 "a"
               ├─ Text @3:100-3:101 " "
               ├─ Link @3:101-3:104 destination: "<u×1000>"
               │  └─ Text @3:102-3:103 "a"
               ├─ Text @3:104-3:105 " "
               ├─ Link @3:105-3:108 destination: "<u×1000>"
               │  └─ Text @3:106-3:107 "a"
               ├─ Text @3:108-3:109 " "
               ├─ Link @3:109-3:112 destination: "<u×1000>"
               │  └─ Text @3:110-3:111 "a"
               ├─ Text @3:112-3:113 " "
               ├─ Link @3:113-3:116 destination: "<u×1000>"
               │  └─ Text @3:114-3:115 "a"
               ├─ Text @3:116-3:117 " "
               ├─ Link @3:117-3:120 destination: "<u×1000>"
               │  └─ Text @3:118-3:119 "a"
               ├─ Text @3:120-3:121 " "
               ├─ Link @3:121-3:124 destination: "<u×1000>"
               │  └─ Text @3:122-3:123 "a"
               ├─ Text @3:124-3:125 " "
               ├─ Link @3:125-3:128 destination: "<u×1000>"
               │  └─ Text @3:126-3:127 "a"
               ├─ Text @3:128-3:129 " "
               ├─ Link @3:129-3:132 destination: "<u×1000>"
               │  └─ Text @3:130-3:131 "a"
               ├─ Text @3:132-3:133 " "
               ├─ Link @3:133-3:136 destination: "<u×1000>"
               │  └─ Text @3:134-3:135 "a"
               ├─ Text @3:136-3:137 " "
               ├─ Link @3:137-3:140 destination: "<u×1000>"
               │  └─ Text @3:138-3:139 "a"
               ├─ Text @3:140-3:141 " "
               ├─ Link @3:141-3:144 destination: "<u×1000>"
               │  └─ Text @3:142-3:143 "a"
               ├─ Text @3:144-3:145 " "
               ├─ Link @3:145-3:148 destination: "<u×1000>"
               │  └─ Text @3:146-3:147 "a"
               ├─ Text @3:148-3:149 " "
               ├─ Link @3:149-3:152 destination: "<u×1000>"
               │  └─ Text @3:150-3:151 "a"
               ├─ Text @3:152-3:153 " "
               ├─ Link @3:153-3:156 destination: "<u×1000>"
               │  └─ Text @3:154-3:155 "a"
               ├─ Text @3:156-3:157 " "
               ├─ Link @3:157-3:160 destination: "<u×1000>"
               │  └─ Text @3:158-3:159 "a"
               ├─ Text @3:160-3:161 " "
               ├─ Link @3:161-3:164 destination: "<u×1000>"
               │  └─ Text @3:162-3:163 "a"
               ├─ Text @3:164-3:165 " "
               ├─ Link @3:165-3:168 destination: "<u×1000>"
               │  └─ Text @3:166-3:167 "a"
               ├─ Text @3:168-3:169 " "
               ├─ Link @3:169-3:172 destination: "<u×1000>"
               │  └─ Text @3:170-3:171 "a"
               ├─ Text @3:172-3:173 " "
               ├─ Link @3:173-3:176 destination: "<u×1000>"
               │  └─ Text @3:174-3:175 "a"
               ├─ Text @3:176-3:177 " "
               ├─ Link @3:177-3:180 destination: "<u×1000>"
               │  └─ Text @3:178-3:179 "a"
               ├─ Text @3:180-3:181 " "
               ├─ Link @3:181-3:184 destination: "<u×1000>"
               │  └─ Text @3:182-3:183 "a"
               ├─ Text @3:184-3:185 " "
               ├─ Link @3:185-3:188 destination: "<u×1000>"
               │  └─ Text @3:186-3:187 "a"
               ├─ Text @3:188-3:189 " "
               ├─ Link @3:189-3:192 destination: "<u×1000>"
               │  └─ Text @3:190-3:191 "a"
               ├─ Text @3:192-3:193 " "
               ├─ Link @3:193-3:196 destination: "<u×1000>"
               │  └─ Text @3:194-3:195 "a"
               ├─ Text @3:196-3:197 " "
               ├─ Link @3:197-3:200 destination: "<u×1000>"
               │  └─ Text @3:198-3:199 "a"
               ├─ Text @3:200-3:201 " "
               ├─ Link @3:201-3:204 destination: "<u×1000>"
               │  └─ Text @3:202-3:203 "a"
               ├─ Text @3:204-3:205 " "
               ├─ Link @3:205-3:208 destination: "<u×1000>"
               │  └─ Text @3:206-3:207 "a"
               ├─ Text @3:208-3:209 " "
               ├─ Link @3:209-3:212 destination: "<u×1000>"
               │  └─ Text @3:210-3:211 "a"
               ├─ Text @3:212-3:213 " "
               ├─ Link @3:213-3:216 destination: "<u×1000>"
               │  └─ Text @3:214-3:215 "a"
               ├─ Text @3:216-3:217 " "
               ├─ Link @3:217-3:220 destination: "<u×1000>"
               │  └─ Text @3:218-3:219 "a"
               ├─ Text @3:220-3:221 " "
               ├─ Link @3:221-3:224 destination: "<u×1000>"
               │  └─ Text @3:222-3:223 "a"
               ├─ Text @3:224-3:225 " "
               ├─ Link @3:225-3:228 destination: "<u×1000>"
               │  └─ Text @3:226-3:227 "a"
               ├─ Text @3:228-3:229 " "
               ├─ Link @3:229-3:232 destination: "<u×1000>"
               │  └─ Text @3:230-3:231 "a"
               ├─ Text @3:232-3:233 " "
               ├─ Link @3:233-3:236 destination: "<u×1000>"
               │  └─ Text @3:234-3:235 "a"
               ├─ Text @3:236-3:237 " "
               ├─ Link @3:237-3:240 destination: "<u×1000>"
               │  └─ Text @3:238-3:239 "a"
               ├─ Text @3:240-3:241 " "
               ├─ Link @3:241-3:244 destination: "<u×1000>"
               │  └─ Text @3:242-3:243 "a"
               ├─ Text @3:244-3:245 " "
               ├─ Link @3:245-3:248 destination: "<u×1000>"
               │  └─ Text @3:246-3:247 "a"
               ├─ Text @3:248-3:249 " "
               ├─ Link @3:249-3:252 destination: "<u×1000>"
               │  └─ Text @3:250-3:251 "a"
               ├─ Text @3:252-3:253 " "
               ├─ Link @3:253-3:256 destination: "<u×1000>"
               │  └─ Text @3:254-3:255 "a"
               ├─ Text @3:256-3:257 " "
               ├─ Link @3:257-3:260 destination: "<u×1000>"
               │  └─ Text @3:258-3:259 "a"
               ├─ Text @3:260-3:261 " "
               ├─ Link @3:261-3:264 destination: "<u×1000>"
               │  └─ Text @3:262-3:263 "a"
               ├─ Text @3:264-3:265 " "
               ├─ Link @3:265-3:268 destination: "<u×1000>"
               │  └─ Text @3:266-3:267 "a"
               ├─ Text @3:268-3:269 " "
               ├─ Link @3:269-3:272 destination: "<u×1000>"
               │  └─ Text @3:270-3:271 "a"
               ├─ Text @3:272-3:273 " "
               ├─ Link @3:273-3:276 destination: "<u×1000>"
               │  └─ Text @3:274-3:275 "a"
               ├─ Text @3:276-3:277 " "
               ├─ Link @3:277-3:280 destination: "<u×1000>"
               │  └─ Text @3:278-3:279 "a"
               ├─ Text @3:280-3:281 " "
               ├─ Link @3:281-3:284 destination: "<u×1000>"
               │  └─ Text @3:282-3:283 "a"
               ├─ Text @3:284-3:285 " "
               ├─ Link @3:285-3:288 destination: "<u×1000>"
               │  └─ Text @3:286-3:287 "a"
               ├─ Text @3:288-3:289 " "
               ├─ Link @3:289-3:292 destination: "<u×1000>"
               │  └─ Text @3:290-3:291 "a"
               ├─ Text @3:292-3:293 " "
               ├─ Link @3:293-3:296 destination: "<u×1000>"
               │  └─ Text @3:294-3:295 "a"
               ├─ Text @3:296-3:297 " "
               ├─ Link @3:297-3:300 destination: "<u×1000>"
               │  └─ Text @3:298-3:299 "a"
               ├─ Text @3:300-3:301 " "
               ├─ Link @3:301-3:304 destination: "<u×1000>"
               │  └─ Text @3:302-3:303 "a"
               ├─ Text @3:304-3:305 " "
               ├─ Link @3:305-3:308 destination: "<u×1000>"
               │  └─ Text @3:306-3:307 "a"
               ├─ Text @3:308-3:309 " "
               ├─ Link @3:309-3:312 destination: "<u×1000>"
               │  └─ Text @3:310-3:311 "a"
               ├─ Text @3:312-3:313 " "
               ├─ Link @3:313-3:316 destination: "<u×1000>"
               │  └─ Text @3:314-3:315 "a"
               ├─ Text @3:316-3:317 " "
               ├─ Link @3:317-3:320 destination: "<u×1000>"
               │  └─ Text @3:318-3:319 "a"
               ├─ Text @3:320-3:321 " "
               ├─ Link @3:321-3:324 destination: "<u×1000>"
               │  └─ Text @3:322-3:323 "a"
               ├─ Text @3:324-3:325 " "
               ├─ Link @3:325-3:328 destination: "<u×1000>"
               │  └─ Text @3:326-3:327 "a"
               ├─ Text @3:328-3:329 " "
               ├─ Link @3:329-3:332 destination: "<u×1000>"
               │  └─ Text @3:330-3:331 "a"
               ├─ Text @3:332-3:333 " "
               ├─ Link @3:333-3:336 destination: "<u×1000>"
               │  └─ Text @3:334-3:335 "a"
               ├─ Text @3:336-3:337 " "
               ├─ Link @3:337-3:340 destination: "<u×1000>"
               │  └─ Text @3:338-3:339 "a"
               ├─ Text @3:340-3:341 " "
               ├─ Link @3:341-3:344 destination: "<u×1000>"
               │  └─ Text @3:342-3:343 "a"
               ├─ Text @3:344-3:345 " "
               ├─ Link @3:345-3:348 destination: "<u×1000>"
               │  └─ Text @3:346-3:347 "a"
               ├─ Text @3:348-3:349 " "
               ├─ Link @3:349-3:352 destination: "<u×1000>"
               │  └─ Text @3:350-3:351 "a"
               ├─ Text @3:352-3:353 " "
               ├─ Link @3:353-3:356 destination: "<u×1000>"
               │  └─ Text @3:354-3:355 "a"
               ├─ Text @3:356-3:357 " "
               ├─ Link @3:357-3:360 destination: "<u×1000>"
               │  └─ Text @3:358-3:359 "a"
               ├─ Text @3:360-3:361 " "
               ├─ Link @3:361-3:364 destination: "<u×1000>"
               │  └─ Text @3:362-3:363 "a"
               ├─ Text @3:364-3:365 " "
               ├─ Link @3:365-3:368 destination: "<u×1000>"
               │  └─ Text @3:366-3:367 "a"
               ├─ Text @3:368-3:369 " "
               ├─ Link @3:369-3:372 destination: "<u×1000>"
               │  └─ Text @3:370-3:371 "a"
               ├─ Text @3:372-3:373 " "
               ├─ Link @3:373-3:376 destination: "<u×1000>"
               │  └─ Text @3:374-3:375 "a"
               ├─ Text @3:376-3:377 " "
               ├─ Link @3:377-3:380 destination: "<u×1000>"
               │  └─ Text @3:378-3:379 "a"
               ├─ Text @3:380-3:381 " "
               ├─ Link @3:381-3:384 destination: "<u×1000>"
               │  └─ Text @3:382-3:383 "a"
               ├─ Text @3:384-3:385 " "
               ├─ Link @3:385-3:388 destination: "<u×1000>"
               │  └─ Text @3:386-3:387 "a"
               ├─ Text @3:388-3:389 " "
               ├─ Link @3:389-3:392 destination: "<u×1000>"
               │  └─ Text @3:390-3:391 "a"
               ├─ Text @3:392-3:393 " "
               ├─ Link @3:393-3:396 destination: "<u×1000>"
               │  └─ Text @3:394-3:395 "a"
               ├─ Text @3:396-3:397 " "
               ├─ Link @3:397-3:400 destination: "<u×1000>"
               │  └─ Text @3:398-3:399 "a"
               ├─ Text @3:400-3:401 " "
               ├─ Link @3:401-3:404 destination: "<u×1000>"
               │  └─ Text @3:402-3:403 "a"
               ├─ Text @3:404-3:405 " "
               └─ Link @3:405-3:408 destination: "<u×1000>"
                  └─ Text @3:406-3:407 "a"
            """)
    }
}
