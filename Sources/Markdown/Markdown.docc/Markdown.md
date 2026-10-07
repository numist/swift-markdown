# ``Markdown``

Swift `Markdown` is a Swift package for parsing, building, editing, and analyzing Markdown documents.

## Overview

The parser follows the [GitHub Flavored Markdown spec](https://github.github.com/gfm/): CommonMark plus the tables, strikethrough, and task list item extensions. As the needs of the community change, the effective dialect implemented by this library may change.

The markup tree provided by this package is comprised of immutable/persistent, thread-safe, copy-on-write value types that only copy substructure that has changed. Other examples of the main strategy behind this library can be seen in [SwiftSyntax](https://github.com/swiftlang/swift-syntax).

## Topics

### Snippets

A quick overview of examples showing tasks you can achieve with Swift Markdown.

- <doc:Snippets>

### Getting Started

- <doc:Parsing-Building-and-Modifying-Markup-Trees>
- <doc:Visitors-Walkers-and-Rewriters>

### Essentials

- ``Markup``
- ``MarkupChildren``
- ``ChildIndexPath``
- ``TypedChildIndexPath``
- ``DirectiveArgument``
- ``DirectiveArgumentText``
- ``Document``
- ``LiteralMarkup``
- ``PlainTextConvertibleMarkup``

### Markup Types

- <doc:BlockMarkup>
- <doc:InlineMarkup>
- ``Aside``

### Infrastructure

- <doc:Infrastructure> 

### Visit Markup

- <doc:VisitMarkup> 
- <doc:FormatterAndOptions>

<!-- Copyright (c) 2021-2022 Apple Inc and the Swift Project authors. All Rights Reserved. -->
