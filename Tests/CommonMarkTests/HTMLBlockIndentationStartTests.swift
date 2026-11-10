/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// HTML blocks whose first line is indented by up to three columns within their container.
///
/// Per HTML blocks, the start condition may be preceded by up to three spaces of indentation, which the block keeps
/// as content; per Tabs, a tab in that indentation counts as the columns to the next tab stop and stays a tab. The
/// block therefore starts at the first byte of that indentation. Indentation the container consumes, including the
/// whitespace after a list marker or a footnote label on the container's first line, is not content, so with none left
/// over the block starts at its `<`. Four columns of indentation make the line indented code instead. The block also
/// starts at its indentation when it interrupts a paragraph, except a type 7 HTML block, which cannot interrupt one.
@Suite("An HTML block starts at the first byte of its indentation")
struct HTMLBlockIndentationStartTests {

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let source: String
        let expected: String

        init(_ name: String, _ source: String, _ expected: String) {
            self.name = name
            self.source = source
            self.expected = expected
        }

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            "top level, no indentation, type 1",
            "<pre>\n",
            """
            document @1:1-2:1
              html_block "<pre>\\n" @1:1-1:6

            """
        ),
        Case(
            "top level, no indentation, type 2",
            "<!-- x -->\n",
            """
            document @1:1-2:1
              html_block "<!-- x -->\\n" @1:1-1:11

            """
        ),
        Case(
            "top level, no indentation, type 3",
            "<?x?>\n",
            """
            document @1:1-2:1
              html_block "<?x?>\\n" @1:1-1:6

            """
        ),
        Case(
            "top level, no indentation, type 4",
            "<!X>\n",
            """
            document @1:1-2:1
              html_block "<!X>\\n" @1:1-1:5

            """
        ),
        Case(
            "top level, no indentation, type 5",
            "<![CDATA[x]]>\n",
            """
            document @1:1-2:1
              html_block "<![CDATA[x]]>\\n" @1:1-1:14

            """
        ),
        Case(
            "top level, no indentation, type 6",
            "<div>\n",
            """
            document @1:1-2:1
              html_block "<div>\\n" @1:1-1:6

            """
        ),
        Case(
            "top level, no indentation, type 7",
            "<a>\n",
            """
            document @1:1-2:1
              html_block "<a>\\n" @1:1-1:4

            """
        ),
        Case(
            "top level, 1 space, type 1",
            " <pre>\n",
            """
            document @1:1-2:1
              html_block " <pre>\\n" @1:1-1:7

            """
        ),
        Case(
            "top level, 1 space, type 2",
            " <!-- x -->\n",
            """
            document @1:1-2:1
              html_block " <!-- x -->\\n" @1:1-1:12

            """
        ),
        Case(
            "top level, 1 space, type 3",
            " <?x?>\n",
            """
            document @1:1-2:1
              html_block " <?x?>\\n" @1:1-1:7

            """
        ),
        Case(
            "top level, 1 space, type 4",
            " <!X>\n",
            """
            document @1:1-2:1
              html_block " <!X>\\n" @1:1-1:6

            """
        ),
        Case(
            "top level, 1 space, type 5",
            " <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              html_block " <![CDATA[x]]>\\n" @1:1-1:15

            """
        ),
        Case(
            "top level, 1 space, type 6",
            " <div>\n",
            """
            document @1:1-2:1
              html_block " <div>\\n" @1:1-1:7

            """
        ),
        Case(
            "top level, 1 space, type 7",
            " <a>\n",
            """
            document @1:1-2:1
              html_block " <a>\\n" @1:1-1:5

            """
        ),
        Case(
            "top level, 2 spaces, type 1",
            "  <pre>\n",
            """
            document @1:1-2:1
              html_block "  <pre>\\n" @1:1-1:8

            """
        ),
        Case(
            "top level, 2 spaces, type 2",
            "  <!-- x -->\n",
            """
            document @1:1-2:1
              html_block "  <!-- x -->\\n" @1:1-1:13

            """
        ),
        Case(
            "top level, 2 spaces, type 3",
            "  <?x?>\n",
            """
            document @1:1-2:1
              html_block "  <?x?>\\n" @1:1-1:8

            """
        ),
        Case(
            "top level, 2 spaces, type 4",
            "  <!X>\n",
            """
            document @1:1-2:1
              html_block "  <!X>\\n" @1:1-1:7

            """
        ),
        Case(
            "top level, 2 spaces, type 5",
            "  <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              html_block "  <![CDATA[x]]>\\n" @1:1-1:16

            """
        ),
        Case(
            "top level, 2 spaces, type 6",
            "  <div>\n",
            """
            document @1:1-2:1
              html_block "  <div>\\n" @1:1-1:8

            """
        ),
        Case(
            "top level, 2 spaces, type 7",
            "  <a>\n",
            """
            document @1:1-2:1
              html_block "  <a>\\n" @1:1-1:6

            """
        ),
        Case(
            "top level, 3 spaces, type 1",
            "   <pre>\n",
            """
            document @1:1-2:1
              html_block "   <pre>\\n" @1:1-1:9

            """
        ),
        Case(
            "top level, 3 spaces, type 2",
            "   <!-- x -->\n",
            """
            document @1:1-2:1
              html_block "   <!-- x -->\\n" @1:1-1:14

            """
        ),
        Case(
            "top level, 3 spaces, type 3",
            "   <?x?>\n",
            """
            document @1:1-2:1
              html_block "   <?x?>\\n" @1:1-1:9

            """
        ),
        Case(
            "top level, 3 spaces, type 4",
            "   <!X>\n",
            """
            document @1:1-2:1
              html_block "   <!X>\\n" @1:1-1:8

            """
        ),
        Case(
            "top level, 3 spaces, type 5",
            "   <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              html_block "   <![CDATA[x]]>\\n" @1:1-1:17

            """
        ),
        Case(
            "top level, 3 spaces, type 6",
            "   <div>\n",
            """
            document @1:1-2:1
              html_block "   <div>\\n" @1:1-1:9

            """
        ),
        Case(
            "top level, 3 spaces, type 7",
            "   <a>\n",
            """
            document @1:1-2:1
              html_block "   <a>\\n" @1:1-1:7

            """
        ),
        Case(
            "top level, 4 spaces: indented code",
            "    <div>\n",
            """
            document @1:1-2:1
              code_block "" "<div>\\n" @1:5-1:10

            """
        ),
        Case(
            "block quote, no indentation, type 1",
            "> <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block "<pre>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, no indentation, type 2",
            "> <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:13
                html_block "<!-- x -->\\n" @1:3-1:13

            """
        ),
        Case(
            "block quote, no indentation, type 3",
            "> <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block "<?x?>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, no indentation, type 4",
            "> <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:7
                html_block "<!X>\\n" @1:3-1:7

            """
        ),
        Case(
            "block quote, no indentation, type 5",
            "> <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:16
                html_block "<![CDATA[x]]>\\n" @1:3-1:16

            """
        ),
        Case(
            "block quote, no indentation, type 6",
            "> <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block "<div>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, no indentation, type 7",
            "> <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:6
                html_block "<a>\\n" @1:3-1:6

            """
        ),
        Case(
            "block quote, 1 space, type 1",
            ">  <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block " <pre>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, 1 space, type 2",
            ">  <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:14
                html_block " <!-- x -->\\n" @1:3-1:14

            """
        ),
        Case(
            "block quote, 1 space, type 3",
            ">  <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block " <?x?>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, 1 space, type 4",
            ">  <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block " <!X>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, 1 space, type 5",
            ">  <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:17
                html_block " <![CDATA[x]]>\\n" @1:3-1:17

            """
        ),
        Case(
            "block quote, 1 space, type 6",
            ">  <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block " <div>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, 1 space, type 7",
            ">  <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:7
                html_block " <a>\\n" @1:3-1:7

            """
        ),
        Case(
            "block quote, 2 spaces, type 1",
            ">   <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "  <pre>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, 2 spaces, type 2",
            ">   <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:15
                html_block "  <!-- x -->\\n" @1:3-1:15

            """
        ),
        Case(
            "block quote, 2 spaces, type 3",
            ">   <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "  <?x?>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, 2 spaces, type 4",
            ">   <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block "  <!X>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, 2 spaces, type 5",
            ">   <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:18
                html_block "  <![CDATA[x]]>\\n" @1:3-1:18

            """
        ),
        Case(
            "block quote, 2 spaces, type 6",
            ">   <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "  <div>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, 2 spaces, type 7",
            ">   <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block "  <a>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, 3 spaces, type 1",
            ">    <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                html_block "   <pre>\\n" @1:3-1:11

            """
        ),
        Case(
            "block quote, 3 spaces, type 2",
            ">    <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:16
                html_block "   <!-- x -->\\n" @1:3-1:16

            """
        ),
        Case(
            "block quote, 3 spaces, type 3",
            ">    <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                html_block "   <?x?>\\n" @1:3-1:11

            """
        ),
        Case(
            "block quote, 3 spaces, type 4",
            ">    <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "   <!X>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, 3 spaces, type 5",
            ">    <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:19
                html_block "   <![CDATA[x]]>\\n" @1:3-1:19

            """
        ),
        Case(
            "block quote, 3 spaces, type 6",
            ">    <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                html_block "   <div>\\n" @1:3-1:11

            """
        ),
        Case(
            "block quote, 3 spaces, type 7",
            ">    <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block "   <a>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, a tab, type 1",
            "> \t<pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block "\\t<pre>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, a tab, type 2",
            "> \t<!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:14
                html_block "\\t<!-- x -->\\n" @1:3-1:14

            """
        ),
        Case(
            "block quote, a tab, type 3",
            "> \t<?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block "\\t<?x?>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, a tab, type 4",
            "> \t<!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block "\\t<!X>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, a tab, type 5",
            "> \t<![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:17
                html_block "\\t<![CDATA[x]]>\\n" @1:3-1:17

            """
        ),
        Case(
            "block quote, a tab, type 6",
            "> \t<div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block "\\t<div>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, a tab, type 7",
            "> \t<a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:7
                html_block "\\t<a>\\n" @1:3-1:7

            """
        ),
        Case(
            "block quote, a space and a tab, type 1",
            ">  \t<pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block " \\t<pre>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, a space and a tab, type 2",
            ">  \t<!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:15
                html_block " \\t<!-- x -->\\n" @1:3-1:15

            """
        ),
        Case(
            "block quote, a space and a tab, type 3",
            ">  \t<?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block " \\t<?x?>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, a space and a tab, type 4",
            ">  \t<!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block " \\t<!X>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, a space and a tab, type 5",
            ">  \t<![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:18
                html_block " \\t<![CDATA[x]]>\\n" @1:3-1:18

            """
        ),
        Case(
            "block quote, a space and a tab, type 6",
            ">  \t<div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block " \\t<div>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, a space and a tab, type 7",
            ">  \t<a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block " \\t<a>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, a tab and a space, type 1",
            "> \t <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "\\t <pre>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, a tab and a space, type 2",
            "> \t <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:15
                html_block "\\t <!-- x -->\\n" @1:3-1:15

            """
        ),
        Case(
            "block quote, a tab and a space, type 3",
            "> \t <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "\\t <?x?>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, a tab and a space, type 4",
            "> \t <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                html_block "\\t <!X>\\n" @1:3-1:9

            """
        ),
        Case(
            "block quote, a tab and a space, type 5",
            "> \t <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:18
                html_block "\\t <![CDATA[x]]>\\n" @1:3-1:18

            """
        ),
        Case(
            "block quote, a tab and a space, type 6",
            "> \t <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                html_block "\\t <div>\\n" @1:3-1:10

            """
        ),
        Case(
            "block quote, a tab and a space, type 7",
            "> \t <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                html_block "\\t <a>\\n" @1:3-1:8

            """
        ),
        Case(
            "block quote, 4 spaces: indented code",
            ">     <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:12
                code_block "" "<div>\\n" @1:7-1:12

            """
        ),
        Case(
            "bullet item, no indentation, type 1",
            "- a\n\n  <pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<pre>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, no indentation, type 2",
            "- a\n\n  <!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:13
                item @1:1-3:13
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<!-- x -->\\n" @3:3-3:13

            """
        ),
        Case(
            "bullet item, no indentation, type 3",
            "- a\n\n  <?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<?x?>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, no indentation, type 4",
            "- a\n\n  <!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:7
                item @1:1-3:7
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<!X>\\n" @3:3-3:7

            """
        ),
        Case(
            "bullet item, no indentation, type 5",
            "- a\n\n  <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:16
                item @1:1-3:16
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<![CDATA[x]]>\\n" @3:3-3:16

            """
        ),
        Case(
            "bullet item, no indentation, type 6",
            "- a\n\n  <div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<div>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, no indentation, type 7",
            "- a\n\n  <a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "<a>\\n" @3:3-3:6

            """
        ),
        Case(
            "bullet item, 1 space, type 1",
            "- a\n\n   <pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <pre>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, 1 space, type 2",
            "- a\n\n   <!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:14
                item @1:1-3:14
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <!-- x -->\\n" @3:3-3:14

            """
        ),
        Case(
            "bullet item, 1 space, type 3",
            "- a\n\n   <?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <?x?>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, 1 space, type 4",
            "- a\n\n   <!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <!X>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, 1 space, type 5",
            "- a\n\n   <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:17
                item @1:1-3:17
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <![CDATA[x]]>\\n" @3:3-3:17

            """
        ),
        Case(
            "bullet item, 1 space, type 6",
            "- a\n\n   <div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <div>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, 1 space, type 7",
            "- a\n\n   <a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:7
                item @1:1-3:7
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <a>\\n" @3:3-3:7

            """
        ),
        Case(
            "bullet item, 2 spaces, type 1",
            "- a\n\n    <pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <pre>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, 2 spaces, type 2",
            "- a\n\n    <!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:15
                item @1:1-3:15
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <!-- x -->\\n" @3:3-3:15

            """
        ),
        Case(
            "bullet item, 2 spaces, type 3",
            "- a\n\n    <?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <?x?>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, 2 spaces, type 4",
            "- a\n\n    <!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <!X>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, 2 spaces, type 5",
            "- a\n\n    <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:18
                item @1:1-3:18
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <![CDATA[x]]>\\n" @3:3-3:18

            """
        ),
        Case(
            "bullet item, 2 spaces, type 6",
            "- a\n\n    <div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <div>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, 2 spaces, type 7",
            "- a\n\n    <a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "  <a>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, 3 spaces, type 1",
            "- a\n\n     <pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <pre>\\n" @3:3-3:11

            """
        ),
        Case(
            "bullet item, 3 spaces, type 2",
            "- a\n\n     <!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:16
                item @1:1-3:16
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <!-- x -->\\n" @3:3-3:16

            """
        ),
        Case(
            "bullet item, 3 spaces, type 3",
            "- a\n\n     <?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <?x?>\\n" @3:3-3:11

            """
        ),
        Case(
            "bullet item, 3 spaces, type 4",
            "- a\n\n     <!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <!X>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, 3 spaces, type 5",
            "- a\n\n     <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:19
                item @1:1-3:19
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <![CDATA[x]]>\\n" @3:3-3:19

            """
        ),
        Case(
            "bullet item, 3 spaces, type 6",
            "- a\n\n     <div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <div>\\n" @3:3-3:11

            """
        ),
        Case(
            "bullet item, 3 spaces, type 7",
            "- a\n\n     <a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "   <a>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, a tab, type 1",
            "- a\n\n  \t<pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<pre>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, a tab, type 2",
            "- a\n\n  \t<!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:14
                item @1:1-3:14
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<!-- x -->\\n" @3:3-3:14

            """
        ),
        Case(
            "bullet item, a tab, type 3",
            "- a\n\n  \t<?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<?x?>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, a tab, type 4",
            "- a\n\n  \t<!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<!X>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, a tab, type 5",
            "- a\n\n  \t<![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:17
                item @1:1-3:17
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<![CDATA[x]]>\\n" @3:3-3:17

            """
        ),
        Case(
            "bullet item, a tab, type 6",
            "- a\n\n  \t<div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<div>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, a tab, type 7",
            "- a\n\n  \t<a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:7
                item @1:1-3:7
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t<a>\\n" @3:3-3:7

            """
        ),
        Case(
            "bullet item, a space and a tab, type 1",
            "- a\n\n   \t<pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<pre>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, a space and a tab, type 2",
            "- a\n\n   \t<!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:15
                item @1:1-3:15
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<!-- x -->\\n" @3:3-3:15

            """
        ),
        Case(
            "bullet item, a space and a tab, type 3",
            "- a\n\n   \t<?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<?x?>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, a space and a tab, type 4",
            "- a\n\n   \t<!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<!X>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, a space and a tab, type 5",
            "- a\n\n   \t<![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:18
                item @1:1-3:18
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<![CDATA[x]]>\\n" @3:3-3:18

            """
        ),
        Case(
            "bullet item, a space and a tab, type 6",
            "- a\n\n   \t<div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<div>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, a space and a tab, type 7",
            "- a\n\n   \t<a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " \\t<a>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, a tab and a space, type 1",
            "- a\n\n  \t <pre>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <pre>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, a tab and a space, type 2",
            "- a\n\n  \t <!-- x -->\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:15
                item @1:1-3:15
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <!-- x -->\\n" @3:3-3:15

            """
        ),
        Case(
            "bullet item, a tab and a space, type 3",
            "- a\n\n  \t <?x?>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <?x?>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, a tab and a space, type 4",
            "- a\n\n  \t <!X>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <!X>\\n" @3:3-3:9

            """
        ),
        Case(
            "bullet item, a tab and a space, type 5",
            "- a\n\n  \t <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:18
                item @1:1-3:18
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <![CDATA[x]]>\\n" @3:3-3:18

            """
        ),
        Case(
            "bullet item, a tab and a space, type 6",
            "- a\n\n  \t <div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <div>\\n" @3:3-3:10

            """
        ),
        Case(
            "bullet item, a tab and a space, type 7",
            "- a\n\n  \t <a>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block "\\t <a>\\n" @3:3-3:8

            """
        ),
        Case(
            "bullet item, 4 spaces: indented code",
            "- a\n\n      <div>\n",
            """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:12
                item @1:1-3:12
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  code_block "" "<div>\\n" @3:7-3:12

            """
        ),
        Case(
            "ordered item, no indentation, type 1",
            "1. a\n\n   <pre>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<pre>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, no indentation, type 2",
            "1. a\n\n   <!-- x -->\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:14
                item @1:1-3:14
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<!-- x -->\\n" @3:4-3:14

            """
        ),
        Case(
            "ordered item, no indentation, type 3",
            "1. a\n\n   <?x?>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<?x?>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, no indentation, type 4",
            "1. a\n\n   <!X>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<!X>\\n" @3:4-3:8

            """
        ),
        Case(
            "ordered item, no indentation, type 5",
            "1. a\n\n   <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:17
                item @1:1-3:17
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<![CDATA[x]]>\\n" @3:4-3:17

            """
        ),
        Case(
            "ordered item, no indentation, type 6",
            "1. a\n\n   <div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<div>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, no indentation, type 7",
            "1. a\n\n   <a>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:7
                item @1:1-3:7
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "<a>\\n" @3:4-3:7

            """
        ),
        Case(
            "ordered item, 1 space, type 1",
            "1. a\n\n    <pre>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <pre>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, 1 space, type 2",
            "1. a\n\n    <!-- x -->\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:15
                item @1:1-3:15
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <!-- x -->\\n" @3:4-3:15

            """
        ),
        Case(
            "ordered item, 1 space, type 3",
            "1. a\n\n    <?x?>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <?x?>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, 1 space, type 4",
            "1. a\n\n    <!X>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <!X>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, 1 space, type 5",
            "1. a\n\n    <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:18
                item @1:1-3:18
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <![CDATA[x]]>\\n" @3:4-3:18

            """
        ),
        Case(
            "ordered item, 1 space, type 6",
            "1. a\n\n    <div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <div>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, 1 space, type 7",
            "1. a\n\n    <a>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block " <a>\\n" @3:4-3:8

            """
        ),
        Case(
            "ordered item, 2 spaces, type 1",
            "1. a\n\n     <pre>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <pre>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, 2 spaces, type 2",
            "1. a\n\n     <!-- x -->\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:16
                item @1:1-3:16
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <!-- x -->\\n" @3:4-3:16

            """
        ),
        Case(
            "ordered item, 2 spaces, type 3",
            "1. a\n\n     <?x?>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <?x?>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, 2 spaces, type 4",
            "1. a\n\n     <!X>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <!X>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, 2 spaces, type 5",
            "1. a\n\n     <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:19
                item @1:1-3:19
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <![CDATA[x]]>\\n" @3:4-3:19

            """
        ),
        Case(
            "ordered item, 2 spaces, type 6",
            "1. a\n\n     <div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <div>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, 2 spaces, type 7",
            "1. a\n\n     <a>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "  <a>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, 3 spaces, type 1",
            "1. a\n\n      <pre>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:12
                item @1:1-3:12
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <pre>\\n" @3:4-3:12

            """
        ),
        Case(
            "ordered item, 3 spaces, type 2",
            "1. a\n\n      <!-- x -->\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:17
                item @1:1-3:17
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <!-- x -->\\n" @3:4-3:17

            """
        ),
        Case(
            "ordered item, 3 spaces, type 3",
            "1. a\n\n      <?x?>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:12
                item @1:1-3:12
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <?x?>\\n" @3:4-3:12

            """
        ),
        Case(
            "ordered item, 3 spaces, type 4",
            "1. a\n\n      <!X>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <!X>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, 3 spaces, type 5",
            "1. a\n\n      <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:20
                item @1:1-3:20
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <![CDATA[x]]>\\n" @3:4-3:20

            """
        ),
        Case(
            "ordered item, 3 spaces, type 6",
            "1. a\n\n      <div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:12
                item @1:1-3:12
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <div>\\n" @3:4-3:12

            """
        ),
        Case(
            "ordered item, 3 spaces, type 7",
            "1. a\n\n      <a>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "   <a>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, a tab, type 1",
            "1. a\n\n   \t<pre>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<pre>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, a tab, type 2",
            "1. a\n\n   \t<!-- x -->\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:15
                item @1:1-3:15
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<!-- x -->\\n" @3:4-3:15

            """
        ),
        Case(
            "ordered item, a tab, type 3",
            "1. a\n\n   \t<?x?>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<?x?>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, a tab, type 4",
            "1. a\n\n   \t<!X>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<!X>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, a tab, type 5",
            "1. a\n\n   \t<![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:18
                item @1:1-3:18
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<![CDATA[x]]>\\n" @3:4-3:18

            """
        ),
        Case(
            "ordered item, a tab, type 6",
            "1. a\n\n   \t<div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<div>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, a tab, type 7",
            "1. a\n\n   \t<a>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:8
                item @1:1-3:8
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t<a>\\n" @3:4-3:8

            """
        ),
        Case(
            "ordered item, a tab and a space, type 1",
            "1. a\n\n   \t <pre>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <pre>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, a tab and a space, type 2",
            "1. a\n\n   \t <!-- x -->\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:16
                item @1:1-3:16
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <!-- x -->\\n" @3:4-3:16

            """
        ),
        Case(
            "ordered item, a tab and a space, type 3",
            "1. a\n\n   \t <?x?>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <?x?>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, a tab and a space, type 4",
            "1. a\n\n   \t <!X>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:10
                item @1:1-3:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <!X>\\n" @3:4-3:10

            """
        ),
        Case(
            "ordered item, a tab and a space, type 5",
            "1. a\n\n   \t <![CDATA[x]]>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:19
                item @1:1-3:19
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <![CDATA[x]]>\\n" @3:4-3:19

            """
        ),
        Case(
            "ordered item, a tab and a space, type 6",
            "1. a\n\n   \t <div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:11
                item @1:1-3:11
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <div>\\n" @3:4-3:11

            """
        ),
        Case(
            "ordered item, a tab and a space, type 7",
            "1. a\n\n   \t <a>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:9
                item @1:1-3:9
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  html_block "\\t <a>\\n" @3:4-3:9

            """
        ),
        Case(
            "ordered item, 4 spaces: indented code",
            "1. a\n\n       <div>\n",
            """
            document @1:1-4:1
              list ordered start=1 delim=period loose @1:1-3:13
                item @1:1-3:13
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  code_block "" "<div>\\n" @3:8-3:13

            """
        ),
        Case(
            "footnote definition, no indentation, type 1",
            "[^a]\n\n[^a]: x\n\n    <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<pre>\\n" @5:5-5:10

            """
        ),
        Case(
            "footnote definition, no indentation, type 2",
            "[^a]\n\n[^a]: x\n\n    <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:15
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<!-- x -->\\n" @5:5-5:15

            """
        ),
        Case(
            "footnote definition, no indentation, type 3",
            "[^a]\n\n[^a]: x\n\n    <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<?x?>\\n" @5:5-5:10

            """
        ),
        Case(
            "footnote definition, no indentation, type 4",
            "[^a]\n\n[^a]: x\n\n    <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:9
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<!X>\\n" @5:5-5:9

            """
        ),
        Case(
            "footnote definition, no indentation, type 5",
            "[^a]\n\n[^a]: x\n\n    <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:18
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<![CDATA[x]]>\\n" @5:5-5:18

            """
        ),
        Case(
            "footnote definition, no indentation, type 6",
            "[^a]\n\n[^a]: x\n\n    <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<div>\\n" @5:5-5:10

            """
        ),
        Case(
            "footnote definition, no indentation, type 7",
            "[^a]\n\n[^a]: x\n\n    <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<a>\\n" @5:5-5:8

            """
        ),
        Case(
            "footnote definition, 1 space, type 1",
            "[^a]\n\n[^a]: x\n\n     <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:11
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <pre>\\n" @5:5-5:11

            """
        ),
        Case(
            "footnote definition, 1 space, type 2",
            "[^a]\n\n[^a]: x\n\n     <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:16
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <!-- x -->\\n" @5:5-5:16

            """
        ),
        Case(
            "footnote definition, 1 space, type 3",
            "[^a]\n\n[^a]: x\n\n     <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:11
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <?x?>\\n" @5:5-5:11

            """
        ),
        Case(
            "footnote definition, 1 space, type 4",
            "[^a]\n\n[^a]: x\n\n     <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <!X>\\n" @5:5-5:10

            """
        ),
        Case(
            "footnote definition, 1 space, type 5",
            "[^a]\n\n[^a]: x\n\n     <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:19
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <![CDATA[x]]>\\n" @5:5-5:19

            """
        ),
        Case(
            "footnote definition, 1 space, type 6",
            "[^a]\n\n[^a]: x\n\n     <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:11
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <div>\\n" @5:5-5:11

            """
        ),
        Case(
            "footnote definition, 1 space, type 7",
            "[^a]\n\n[^a]: x\n\n     <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:9
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <a>\\n" @5:5-5:9

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 1",
            "[^a]\n\n[^a]: x\n\n      <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:12
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <pre>\\n" @5:5-5:12

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 2",
            "[^a]\n\n[^a]: x\n\n      <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:17
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <!-- x -->\\n" @5:5-5:17

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 3",
            "[^a]\n\n[^a]: x\n\n      <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:12
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <?x?>\\n" @5:5-5:12

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 4",
            "[^a]\n\n[^a]: x\n\n      <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:11
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <!X>\\n" @5:5-5:11

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 5",
            "[^a]\n\n[^a]: x\n\n      <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:20
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <![CDATA[x]]>\\n" @5:5-5:20

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 6",
            "[^a]\n\n[^a]: x\n\n      <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:12
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <div>\\n" @5:5-5:12

            """
        ),
        Case(
            "footnote definition, 2 spaces, type 7",
            "[^a]\n\n[^a]: x\n\n      <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <a>\\n" @5:5-5:10

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 1",
            "[^a]\n\n[^a]: x\n\n       <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:13
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <pre>\\n" @5:5-5:13

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 2",
            "[^a]\n\n[^a]: x\n\n       <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:18
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <!-- x -->\\n" @5:5-5:18

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 3",
            "[^a]\n\n[^a]: x\n\n       <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:13
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <?x?>\\n" @5:5-5:13

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 4",
            "[^a]\n\n[^a]: x\n\n       <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:12
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <!X>\\n" @5:5-5:12

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 5",
            "[^a]\n\n[^a]: x\n\n       <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:21
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <![CDATA[x]]>\\n" @5:5-5:21

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 6",
            "[^a]\n\n[^a]: x\n\n       <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:13
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <div>\\n" @5:5-5:13

            """
        ),
        Case(
            "footnote definition, 3 spaces, type 7",
            "[^a]\n\n[^a]: x\n\n       <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:11
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <a>\\n" @5:5-5:11

            """
        ),
        Case(
            "footnote definition, 4 spaces: indented code",
            "[^a]\n\n[^a]: x\n\n        <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:14
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                code_block "" "<div>\\n" @5:9-5:14

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 1",
            "[^a]\n\n[^a]: x\n\n\t<pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:7
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<pre>\\n" @5:2-5:7

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 2",
            "[^a]\n\n[^a]: x\n\n\t<!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:12
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<!-- x -->\\n" @5:2-5:12

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 3",
            "[^a]\n\n[^a]: x\n\n\t<?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:7
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<?x?>\\n" @5:2-5:7

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 4",
            "[^a]\n\n[^a]: x\n\n\t<!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:6
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<!X>\\n" @5:2-5:6

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 5",
            "[^a]\n\n[^a]: x\n\n\t<![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:15
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<![CDATA[x]]>\\n" @5:2-5:15

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 6",
            "[^a]\n\n[^a]: x\n\n\t<div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:7
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<div>\\n" @5:2-5:7

            """
        ),
        Case(
            "footnote definition, content indentation a tab, no indentation, type 7",
            "[^a]\n\n[^a]: x\n\n\t<a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:5
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "<a>\\n" @5:2-5:5

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 1",
            "[^a]\n\n[^a]: x\n\n\t <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <pre>\\n" @5:2-5:8

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 2",
            "[^a]\n\n[^a]: x\n\n\t <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:13
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <!-- x -->\\n" @5:2-5:13

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 3",
            "[^a]\n\n[^a]: x\n\n\t <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <?x?>\\n" @5:2-5:8

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 4",
            "[^a]\n\n[^a]: x\n\n\t <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:7
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <!X>\\n" @5:2-5:7

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 5",
            "[^a]\n\n[^a]: x\n\n\t <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:16
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <![CDATA[x]]>\\n" @5:2-5:16

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 6",
            "[^a]\n\n[^a]: x\n\n\t <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <div>\\n" @5:2-5:8

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 1 space, type 7",
            "[^a]\n\n[^a]: x\n\n\t <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:6
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block " <a>\\n" @5:2-5:6

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 1",
            "[^a]\n\n[^a]: x\n\n\t  <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:9
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <pre>\\n" @5:2-5:9

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 2",
            "[^a]\n\n[^a]: x\n\n\t  <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:14
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <!-- x -->\\n" @5:2-5:14

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 3",
            "[^a]\n\n[^a]: x\n\n\t  <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:9
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <?x?>\\n" @5:2-5:9

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 4",
            "[^a]\n\n[^a]: x\n\n\t  <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <!X>\\n" @5:2-5:8

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 5",
            "[^a]\n\n[^a]: x\n\n\t  <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:17
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <![CDATA[x]]>\\n" @5:2-5:17

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 6",
            "[^a]\n\n[^a]: x\n\n\t  <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:9
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <div>\\n" @5:2-5:9

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 2 spaces, type 7",
            "[^a]\n\n[^a]: x\n\n\t  <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:7
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "  <a>\\n" @5:2-5:7

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 1",
            "[^a]\n\n[^a]: x\n\n\t   <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <pre>\\n" @5:2-5:10

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 2",
            "[^a]\n\n[^a]: x\n\n\t   <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:15
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <!-- x -->\\n" @5:2-5:15

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 3",
            "[^a]\n\n[^a]: x\n\n\t   <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <?x?>\\n" @5:2-5:10

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 4",
            "[^a]\n\n[^a]: x\n\n\t   <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:9
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <!X>\\n" @5:2-5:9

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 5",
            "[^a]\n\n[^a]: x\n\n\t   <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:18
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <![CDATA[x]]>\\n" @5:2-5:18

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 6",
            "[^a]\n\n[^a]: x\n\n\t   <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:10
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <div>\\n" @5:2-5:10

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 3 spaces, type 7",
            "[^a]\n\n[^a]: x\n\n\t   <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:8
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                html_block "   <a>\\n" @5:2-5:8

            """
        ),
        Case(
            "footnote definition, content indentation a tab, 4 spaces: indented code",
            "[^a]\n\n[^a]: x\n\n\t    <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-5:11
                paragraph @3:7-3:8
                  text "x" @3:7-3:8
                code_block "" "<div>\\n" @5:6-5:11

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 1",
            ">> <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block "<pre>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 2",
            ">> <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:14
                block_quote @1:2-1:14
                  html_block "<!-- x -->\\n" @1:4-1:14

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 3",
            ">> <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block "<?x?>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 4",
            ">> <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                block_quote @1:2-1:8
                  html_block "<!X>\\n" @1:4-1:8

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 5",
            ">> <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:17
                block_quote @1:2-1:17
                  html_block "<![CDATA[x]]>\\n" @1:4-1:17

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 6",
            ">> <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block "<div>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, no indentation, type 7",
            ">> <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:7
                block_quote @1:2-1:7
                  html_block "<a>\\n" @1:4-1:7

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 1",
            ">>  <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block " <pre>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 2",
            ">>  <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:15
                block_quote @1:2-1:15
                  html_block " <!-- x -->\\n" @1:4-1:15

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 3",
            ">>  <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block " <?x?>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 4",
            ">>  <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block " <!X>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 5",
            ">>  <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:18
                block_quote @1:2-1:18
                  html_block " <![CDATA[x]]>\\n" @1:4-1:18

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 6",
            ">>  <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block " <div>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, 1 space, type 7",
            ">>  <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                block_quote @1:2-1:8
                  html_block " <a>\\n" @1:4-1:8

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 1",
            ">>   <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "  <pre>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 2",
            ">>   <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:16
                block_quote @1:2-1:16
                  html_block "  <!-- x -->\\n" @1:4-1:16

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 3",
            ">>   <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "  <?x?>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 4",
            ">>   <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block "  <!X>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 5",
            ">>   <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:19
                block_quote @1:2-1:19
                  html_block "  <![CDATA[x]]>\\n" @1:4-1:19

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 6",
            ">>   <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "  <div>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, 2 spaces, type 7",
            ">>   <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block "  <a>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 1",
            ">>    <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:12
                block_quote @1:2-1:12
                  html_block "   <pre>\\n" @1:4-1:12

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 2",
            ">>    <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:17
                block_quote @1:2-1:17
                  html_block "   <!-- x -->\\n" @1:4-1:17

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 3",
            ">>    <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:12
                block_quote @1:2-1:12
                  html_block "   <?x?>\\n" @1:4-1:12

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 4",
            ">>    <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "   <!X>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 5",
            ">>    <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:20
                block_quote @1:2-1:20
                  html_block "   <![CDATA[x]]>\\n" @1:4-1:20

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 6",
            ">>    <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:12
                block_quote @1:2-1:12
                  html_block "   <div>\\n" @1:4-1:12

            """
        ),
        Case(
            "block quote in a block quote, 3 spaces, type 7",
            ">>    <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block "   <a>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 1",
            ">> \t<pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block "\\t<pre>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 2",
            ">> \t<!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:15
                block_quote @1:2-1:15
                  html_block "\\t<!-- x -->\\n" @1:4-1:15

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 3",
            ">> \t<?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block "\\t<?x?>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 4",
            ">> \t<!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block "\\t<!X>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 5",
            ">> \t<![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:18
                block_quote @1:2-1:18
                  html_block "\\t<![CDATA[x]]>\\n" @1:4-1:18

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 6",
            ">> \t<div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block "\\t<div>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, a tab, type 7",
            ">> \t<a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:8
                block_quote @1:2-1:8
                  html_block "\\t<a>\\n" @1:4-1:8

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 1",
            ">> \t <pre>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "\\t <pre>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 2",
            ">> \t <!-- x -->\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:16
                block_quote @1:2-1:16
                  html_block "\\t <!-- x -->\\n" @1:4-1:16

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 3",
            ">> \t <?x?>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "\\t <?x?>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 4",
            ">> \t <!X>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:10
                block_quote @1:2-1:10
                  html_block "\\t <!X>\\n" @1:4-1:10

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 5",
            ">> \t <![CDATA[x]]>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:19
                block_quote @1:2-1:19
                  html_block "\\t <![CDATA[x]]>\\n" @1:4-1:19

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 6",
            ">> \t <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:11
                block_quote @1:2-1:11
                  html_block "\\t <div>\\n" @1:4-1:11

            """
        ),
        Case(
            "block quote in a block quote, a tab and a space, type 7",
            ">> \t <a>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:9
                block_quote @1:2-1:9
                  html_block "\\t <a>\\n" @1:4-1:9

            """
        ),
        Case(
            "block quote in a block quote, 4 spaces: indented code",
            ">>     <div>\n",
            """
            document @1:1-2:1
              block_quote @1:1-1:13
                block_quote @1:2-1:13
                  code_block "" "<div>\\n" @1:8-1:13

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 1",
            "[^a]\n\n> [^a]: x\n>\n>     <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<pre>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 2",
            "[^a]\n\n> [^a]: x\n>\n>     <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:17
              footnote_definition "a" @3:3-5:17
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<!-- x -->\\n" @5:7-5:17

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 3",
            "[^a]\n\n> [^a]: x\n>\n>     <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<?x?>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 4",
            "[^a]\n\n> [^a]: x\n>\n>     <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:11
              footnote_definition "a" @3:3-5:11
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<!X>\\n" @5:7-5:11

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 5",
            "[^a]\n\n> [^a]: x\n>\n>     <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:20
              footnote_definition "a" @3:3-5:20
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<![CDATA[x]]>\\n" @5:7-5:20

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 6",
            "[^a]\n\n> [^a]: x\n>\n>     <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<div>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, no indentation, type 7",
            "[^a]\n\n> [^a]: x\n>\n>     <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:10
              footnote_definition "a" @3:3-5:10
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "<a>\\n" @5:7-5:10

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 1",
            "[^a]\n\n> [^a]: x\n>\n>      <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <pre>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 2",
            "[^a]\n\n> [^a]: x\n>\n>      <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:18
              footnote_definition "a" @3:3-5:18
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <!-- x -->\\n" @5:7-5:18

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 3",
            "[^a]\n\n> [^a]: x\n>\n>      <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <?x?>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 4",
            "[^a]\n\n> [^a]: x\n>\n>      <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <!X>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 5",
            "[^a]\n\n> [^a]: x\n>\n>      <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:21
              footnote_definition "a" @3:3-5:21
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <![CDATA[x]]>\\n" @5:7-5:21

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 6",
            "[^a]\n\n> [^a]: x\n>\n>      <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <div>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, 1 space, type 7",
            "[^a]\n\n> [^a]: x\n>\n>      <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:11
              footnote_definition "a" @3:3-5:11
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " <a>\\n" @5:7-5:11

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 1",
            "[^a]\n\n> [^a]: x\n>\n>       <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <pre>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 2",
            "[^a]\n\n> [^a]: x\n>\n>       <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:19
              footnote_definition "a" @3:3-5:19
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <!-- x -->\\n" @5:7-5:19

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 3",
            "[^a]\n\n> [^a]: x\n>\n>       <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <?x?>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 4",
            "[^a]\n\n> [^a]: x\n>\n>       <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <!X>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 5",
            "[^a]\n\n> [^a]: x\n>\n>       <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:22
              footnote_definition "a" @3:3-5:22
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <![CDATA[x]]>\\n" @5:7-5:22

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 6",
            "[^a]\n\n> [^a]: x\n>\n>       <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <div>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, 2 spaces, type 7",
            "[^a]\n\n> [^a]: x\n>\n>       <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "  <a>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 1",
            "[^a]\n\n> [^a]: x\n>\n>        <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:15
              footnote_definition "a" @3:3-5:15
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <pre>\\n" @5:7-5:15

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 2",
            "[^a]\n\n> [^a]: x\n>\n>        <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:20
              footnote_definition "a" @3:3-5:20
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <!-- x -->\\n" @5:7-5:20

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 3",
            "[^a]\n\n> [^a]: x\n>\n>        <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:15
              footnote_definition "a" @3:3-5:15
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <?x?>\\n" @5:7-5:15

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 4",
            "[^a]\n\n> [^a]: x\n>\n>        <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <!X>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 5",
            "[^a]\n\n> [^a]: x\n>\n>        <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:23
              footnote_definition "a" @3:3-5:23
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <![CDATA[x]]>\\n" @5:7-5:23

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 6",
            "[^a]\n\n> [^a]: x\n>\n>        <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:15
              footnote_definition "a" @3:3-5:15
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <div>\\n" @5:7-5:15

            """
        ),
        Case(
            "footnote definition in a block quote, 3 spaces, type 7",
            "[^a]\n\n> [^a]: x\n>\n>        <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "   <a>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 1",
            "[^a]\n\n> [^a]: x\n>\n>     \t<pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<pre>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 2",
            "[^a]\n\n> [^a]: x\n>\n>     \t<!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:18
              footnote_definition "a" @3:3-5:18
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<!-- x -->\\n" @5:7-5:18

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 3",
            "[^a]\n\n> [^a]: x\n>\n>     \t<?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<?x?>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 4",
            "[^a]\n\n> [^a]: x\n>\n>     \t<!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<!X>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 5",
            "[^a]\n\n> [^a]: x\n>\n>     \t<![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:21
              footnote_definition "a" @3:3-5:21
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<![CDATA[x]]>\\n" @5:7-5:21

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 6",
            "[^a]\n\n> [^a]: x\n>\n>     \t<div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<div>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, a tab, type 7",
            "[^a]\n\n> [^a]: x\n>\n>     \t<a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:11
              footnote_definition "a" @3:3-5:11
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t<a>\\n" @5:7-5:11

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 1",
            "[^a]\n\n> [^a]: x\n>\n>      \t<pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<pre>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 2",
            "[^a]\n\n> [^a]: x\n>\n>      \t<!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:19
              footnote_definition "a" @3:3-5:19
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<!-- x -->\\n" @5:7-5:19

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 3",
            "[^a]\n\n> [^a]: x\n>\n>      \t<?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<?x?>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 4",
            "[^a]\n\n> [^a]: x\n>\n>      \t<!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<!X>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 5",
            "[^a]\n\n> [^a]: x\n>\n>      \t<![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:22
              footnote_definition "a" @3:3-5:22
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<![CDATA[x]]>\\n" @5:7-5:22

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 6",
            "[^a]\n\n> [^a]: x\n>\n>      \t<div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<div>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, a space and a tab, type 7",
            "[^a]\n\n> [^a]: x\n>\n>      \t<a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block " \\t<a>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 1",
            "[^a]\n\n> [^a]: x\n>\n>     \t <pre>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <pre>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 2",
            "[^a]\n\n> [^a]: x\n>\n>     \t <!-- x -->\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:19
              footnote_definition "a" @3:3-5:19
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <!-- x -->\\n" @5:7-5:19

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 3",
            "[^a]\n\n> [^a]: x\n>\n>     \t <?x?>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <?x?>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 4",
            "[^a]\n\n> [^a]: x\n>\n>     \t <!X>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:13
              footnote_definition "a" @3:3-5:13
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <!X>\\n" @5:7-5:13

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 5",
            "[^a]\n\n> [^a]: x\n>\n>     \t <![CDATA[x]]>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:22
              footnote_definition "a" @3:3-5:22
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <![CDATA[x]]>\\n" @5:7-5:22

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 6",
            "[^a]\n\n> [^a]: x\n>\n>     \t <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:14
              footnote_definition "a" @3:3-5:14
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <div>\\n" @5:7-5:14

            """
        ),
        Case(
            "footnote definition in a block quote, a tab and a space, type 7",
            "[^a]\n\n> [^a]: x\n>\n>     \t <a>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:12
              footnote_definition "a" @3:3-5:12
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                html_block "\\t <a>\\n" @5:7-5:12

            """
        ),
        Case(
            "footnote definition in a block quote, 4 spaces: indented code",
            "[^a]\n\n> [^a]: x\n>\n>         <div>\n",
            """
            document @1:1-6:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              block_quote @3:1-5:16
              footnote_definition "a" @3:3-5:16
                paragraph @3:9-3:10
                  text "x" @3:9-3:10
                code_block "" "<div>\\n" @5:11-5:16

            """
        ),
        Case(
            "bullet item first line, spaces after the marker",
            "-   <div>\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
                  html_block "<div>\\n" @1:5-1:10

            """
        ),
        Case(
            "bullet item first line, a tab after the marker",
            "-\t<div>\n",
            """
            document @1:1-2:1
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  html_block "<div>\\n" @1:3-1:8

            """
        ),
        Case(
            "ordered item first line, spaces after the marker",
            "1.  <div>\n",
            """
            document @1:1-2:1
              list ordered start=1 delim=period tight @1:1-1:10
                item @1:1-1:10
                  html_block "<div>\\n" @1:5-1:10

            """
        ),
        Case(
            "footnote definition first line, spaces after the label",
            "[^a]\n\n[^a]:   <div>\n",
            """
            document @1:1-4:1
              paragraph @1:1-1:5
                footnote_reference "1" @1:1-1:5
              footnote_definition "a" @3:1-3:14
                html_block "<div>\\n" @3:9-3:14

            """
        ),
        Case(
            "top level, 2 spaces, interrupting a paragraph",
            "a\n  <div>\n",
            """
            document @1:1-3:1
              paragraph @1:1-1:2
                text "a" @1:1-1:2
              html_block "  <div>\\n" @2:1-2:8

            """
        ),
        Case(
            "top level, 2 spaces, type 7 after a paragraph line: inline HTML",
            "a\n  <a>\n",
            """
            document @1:1-3:1
              paragraph @1:1-2:6
                text "a" @1:1-1:2
                softbreak @-
                html_inline "<a>" @2:3-2:6

            """
        ),
        Case(
            "block quote, 2 spaces, interrupting a paragraph",
            "> a\n>   <div>\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:10
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
                html_block "  <div>\\n" @2:3-2:10

            """
        ),
        Case(
            "block quote, 2 spaces, after a blank line",
            ">\n>   <div>\n",
            """
            document @1:1-3:1
              block_quote @1:1-2:10
                html_block "  <div>\\n" @2:3-2:10

            """
        ),
        Case(
            "bullet item, 1 space, interrupting a paragraph",
            "- a\n   <div>\n",
            """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:9
                item @1:1-2:9
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  html_block " <div>\\n" @2:3-2:9

            """
        ),
        Case(
            "top level, 2 spaces, after a block quote",
            "> a\n  <div>\n",
            """
            document @1:1-3:1
              block_quote @1:1-1:4
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
              html_block "  <div>\\n" @2:1-2:8

            """
        ),
    ]

    @Test(arguments: cases)
    func tree(_ c: Case) {
        #expect(TreeDump.dump(c.source, options: [.sourcePosition, .footnotes], sourceRanges: true) == c.expected)
    }
}
