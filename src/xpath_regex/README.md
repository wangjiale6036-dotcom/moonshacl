# XPath 2.0 regular expressions in MoonBit

`compile(pattern, flags)` returns `Result[Regex, String]`; `Regex.matches(text)`
returns `Result[Bool, String]`. Matches search substrings unless anchors constrain
the match. Compilation and matching contain no host-language regular-expression
calls, network access, or platform-specific foreign functions.

The grammar follows [XPath 2.0 Functions and Operators, second edition §7.6](https://www.w3.org/TR/2010/REC-xpath-functions-20101214/#func-matches)
and [XML Schema 1.0 regular expressions](https://www.w3.org/TR/xmlschema-2/#regexs).
The dot/CR ambiguity uses the W3C correction exercised by QT3 `fn-matches-45`:
dot excludes CR and LF unless `s` is present. XML name escapes use
[XML 1.0 fifth-edition name characters](https://www.w3.org/TR/REC-xml/#NT-NameStartChar).

Supported syntax includes grouping and back-references; alternation; greedy and
reluctant `?`, `*`, `+`, and bounded repeats; anchors; Unicode ranges, general
categories and blocks; nested class subtraction; and XML `\i`, `\c`, `\s`, `\d`,
`\w` and their complements. Flags are `i`, `m`, `s`, `x`; duplicates are legal.
Illegal syntax is an error, including lookaround, named or noncapturing groups,
word-boundary/octal/hex escapes, and XPath 3.x `q` mode. The XML Schema grammar
excludes surrogate categories/blocks. Whitespace mode preserves spaces inside
classes and does not introduce Perl comments.

Unicode properties and case variants use pinned Unicode **15.0.0** UCD files.
Case variants follow equality of default full uppercase or lowercase mappings;
category and block escapes are unaffected by `i`. Historical block spellings
`Greek`, `CombiningMarksforSymbols`, and `PrivateUse` remain available. Input
iteration operates on Unicode codepoints, including supplementary planes.

Matching uses a Thompson NFA whenever capture contents cannot affect the result;
expressions with back-references use an explicit capture-aware backtracking VM.
Large bounded repeats remain compact in the VM. Nested repeated captures are
cleared according to W3C regression `p303`, including groups omitted in a later
iteration. Neither engine uses recursion proportional to input length.

Resource limits are explicit: 100,000 UTF-16 pattern units, nesting 256, 4,096
captures, repeat bounds up to 2,147,483,647, 2,000,000 UTF-16 input units, and a
2,000,000-unit execution budget (including VM state-copy cost). NFA compilation
falls back to the VM at 50,000 instructions or a bounded-repeat limit above 1,000;
that fallback is not a syntax rejection. Exhausted matching resources return
`Err`, never `Ok(false)`. For example, `(){2147483647}` compiles but matching the
empty string deterministically exhausts its work budget. Callers must propagate
that failure separately from a constraint violation.

Validation includes **146** compatible official W3C QT3 `fn:matches` cases and
**1,542** compatible W3C Perl-derived regression cases. The pinned source and
SHA-256 hashes, selected identifiers, and exclusions are recorded in
[`fixtures/regex-w3c-source.json`](../../fixtures/regex-w3c-source.json).
Excluded cases require XPath 3.x syntax, XSD 1.1 grammar, or an XPath evaluator for
outer expressions and function type checking. Seven additional test groups cover
Unicode, invalid syntax, resource errors, and agreement between the two engines
on 13,068 deterministic short-string combinations. These are regex conformance
checks, not a claim to implement an XPath query processor.

Regenerate and test from the repository root:

```sh
node scripts/generate-regex-unicode.mjs
node fixtures/regex-generate-w3c.mjs
node scripts/moon.mjs fmt src/xpath_regex
node scripts/moon.mjs test --package wangjiale6036-dotcom/moonshacl/xpath_regex --target js
node scripts/moon.mjs test --package wangjiale6036-dotcom/moonshacl/xpath_regex --target wasm-gc
node scripts/moon.mjs test --package wangjiale6036-dotcom/moonshacl/xpath_regex --target native
```

Unicode inputs and generated data are covered by
[`licenses/Unicode-DATA-LICENSE.txt`](../../licenses/Unicode-DATA-LICENSE.txt).
W3C fixtures retain their official source and are covered by
[`licenses/W3C-Software-2023.html`](../../licenses/W3C-Software-2023.html),
as referenced by the retained official test-suite overview. Original MoonSHACL
engine and generator code is Apache-2.0.
