///|
fn check_match(
  pattern : String,
  flags : String,
  text : String,
  expected : Bool,
) -> Unit raise {
  let compiled = @xpath_regex.compile(pattern, flags)
  match compiled {
    Err(message) =>
      fail("Unexpected compilation error for '\{pattern}': \{message}")
    Ok(regex) =>
      assert_eq(
        regex.matches(text),
        Ok(expected),
        msg="pattern=\{pattern}, flags=\{flags}, text=\{text}",
      )
  }
}

///|
test "XPath syntax quantifiers groups backreferences and empty matches" {
  for
    (pattern, text, expected) in [
      ("bra", "abracadabra", true),
      ("^bra", "abracadabra", false),
      ("^a.*a$", "abracadabra", true),
      ("", "anything", true),
      ("^$", "", true),
      ("^$", "x", false),
      ("^(ab|cd){2,3}$", "abcdab", true),
      ("^(ab|cd){2,3}$", "ab", false),
      ("^(ab|cd){2,3}$", "abababab", false),
      ("^a{0}$", "", true),
      ("^a{2,}$", "aaaa", true),
      ("^a{2,}$", "a", false),
      ("^a??a$", "aa", true),
      ("^a*?a$", "aaaa", true),
      ("^a+?a$", "a", false),
      ("^a{2,3}?a$", "aaaa", true),
      ("^a{2}?a$", "aaa", true),
      ("^(a|)b$", "b", true),
      ("^(a|)b$", "ab", true),
      ("^(()*)*$", "", true),
      ("^(){2}$", "", true),
      ("^(){2,3}$", "a", false),
      ("^(['\"]).*\\1$", "'abc'", true),
      ("^(['\"]).*\\1$", "'abc\"", false),
      ("^(ab+)\\1$", "abbabb", true),
      ("^(ab+)\\1$", "abbab", false),
      ("^(a)?b\\1$", "b", true),
      ("^(a)?b\\1$", "aba", true),
      ("^(a)?b\\1$", "ab", false),
      ("^(a)\\12$", "aa2", true),
      ("^((((((((((a))))))))))\\10$", "aa", true),
      (
        "^\\$\\^\\.\\[\\]\\(\\)\\{\\}\\|\\?\\*\\+\\-\\\\$", "$^.[](){}|?*+-\\", true,
      ),
      ("^.$", "😀", true),
      ("^..$", "😀", false),
    ] {
    check_match(pattern, "", text, expected)
  }
}

///|
test "XPath flags and newline rules" {
  for
    (pattern, flags, text, expected) in [
      ("^hello$", "i", "HeLlO", true),
      ("^hello$", "ii", "HeLlO", true),
      ("^a.b$", "", "a\nb", false),
      ("^a.b$", "s", "a\nb", true),
      ("^a.b$", "", "a\rb", false),
      ("^b$", "m", "a\nb\nc", true),
      ("^b$", "", "a\nb\nc", false),
      ("^b$", "m", "a\rb\rc", false),
      ("a$", "", "a\n", false),
      ("a$", "m", "a\n", true),
      ("\\n$", "m", "a\n", false),
      ("^$", "m", "a\n", false),
      ("^$", "m", "\n", true),
      ("^$", "m", "", true),
      ("^ h e l l o $", "x", "hello", true),
      ("^hello[ ]world$", "x", "hello world", true),
      ("^hello[ ]world$", "x", "helloworld", false),
      ("^hello\\ sworld$", "x", "hello world", true),
      ("^a#b$", "x", "a#b", true),
      ("^ [a-z -[aeiou]]+ $", "x", "b c", true),
      ("^ [a-z -[aeiou]]+ $", "x", "a c", false),
    ] {
    check_match(pattern, flags, text, expected)
  }
}

///|
test "XML character classes subtraction categories and blocks" {
  for
    (pattern, text, expected) in [
      ("^[a-z-[aeiou]]+$", "rhythm", true),
      ("^[a-z-[aeiou]]+$", "hello", false),
      ("^[a-z-[b-d-[c]]]+$", "ace", true),
      ("^[a-z-[b-d-[c]]]+$", "bed", false),
      ("^[^a-z-[0-9]]+$", "汉字", true),
      ("^[^a-z-[0-9]]+$", "3", false),
      ("^[-a]+$", "-aaa", true),
      ("^[a-]+$", "a--", true),
      ("^[a-z\\-]+$", "a-b", true),
      ("^[a^]+$", "a^a", true),
      ("^\\d+$", "١٢３", true),
      ("^\\D+$", "汉字", true),
      ("^\\d+$", "²", false),
      ("^\\p{L}+$", "汉字Ωé", true),
      ("^\\p{L}+$", "42", false),
      ("^\\p{M}+$", "\u0301", true),
      ("^\\p{P}$", "_", true),
      ("^\\p{S}$", "😀", true),
      ("^\\p{Z}$", "\u00A0", true),
      ("^\\p{C}$", "\u0001", true),
      ("^\\p{Cn}$", "\u0378", true),
      ("^\\P{L}+$", "42_", true),
      ("^\\p{IsBasicLatin}+$", "ABC123", true),
      ("^\\p{IsBasicLatin}+$", "é", false),
      ("^\\p{IsGreek}+$", "αΩ", true),
      ("^\\p{IsGreekandCoptic}+$", "αΩ", true),
      ("^\\p{IsEmoticons}$", "😀", true),
      ("^\\p{IsCJKUnifiedIdeographs}+$", "汉字", true),
      ("^\\p{IsCombiningMarksforSymbols}$", "\u20D0", true),
      ("^\\p{IsPrivateUse}$", "\uE000", true),
      ("^\\w+$", "汉字42€", true),
      ("^\\w+$", "hello_world", false),
      ("^\\w+$", "\u00A0", false),
      ("^\\W+$", "_ \u0001", true),
      ("^\\s+$", " \t\r\n", true),
      ("^\\s+$", "\u00A0", false),
      ("^\\i\\c*$", "名字:abc-1.2", true),
      ("^\\i\\c*$", "9name", false),
      ("^\\i$", "_", true),
      ("^\\I$", "9", true),
      ("^\\C$", " ", true),
    ] {
    check_match(pattern, "", text, expected)
  }
}

///|
test "Unicode case variants apply to ranges but not category and block escapes" {
  for
    (pattern, text, expected) in [
      ("^k$", "K", true),
      ("^[A-Z]$", "K", true),
      ("^[A-Z-[IO]]$", "i", false),
      ("^[^Q]$", "q", false),
      ("^σ$", "ς", true),
      ("^𐐀$", "𐐨", true),
      ("^i$", "ı", true),
      ("^i$", "İ", false),
      ("^ß$", "ẞ", true),
      ("^ß$", "ss", false),
      ("^ﬅ$", "ﬆ", true),
      ("^\\p{Lu}$", "a", false),
      ("^[\\p{Lu}]$", "a", false),
      ("^\\p{IsBasicLatin}$", "K", false),
      ("^([md])[aeiou]\\1$", "Mum", true),
      ("^(k)\\1$", "kK", true),
      ("^(i)\\1$", "iİ", false),
    ] {
    check_match(pattern, "i", text, expected)
  }
}

///|
test "XPath invalid syntax is an error rather than JS extension or silent false" {
  for
    pattern in [
      "(", ")", "[", "[]", "[^]", "[z-a]", "[a-z-[x]y]", "[a-z-[x]", "[a-b-c]", "[\\d-a]",
      "[a-\\p{L}]", "[a--b]", "[\\1]", "a{,2}", "a{2,1}", "a{1", "a{1,2,3}", "a{2147483648}",
      "a**", "a++", "a?+", "*a", "a}", "\\", "\\0", "\\1", "(a\\1)", "(a)\\2", "\\a",
      "\\b", "\\u0041", "\\x41", "(?=a)", "(?!a)", "(?<=a)", "(?:a)", "(?i)a", "(?>a)",
      "(?<name>a)", "\\p{Letter}", "\\p{IsNoSuchBlock}", "\\p{L", "\\pL", "\\ ",
      "\\p{Cs}", "\\p{IsHighSurrogates}", "\\p{IsLowSurrogates}", "\\p{IsHighPrivateUseSurrogates}",
    ] {
    assert_true(@xpath_regex.compile(pattern, "") is Err(_), msg=pattern)
  }
  for flag in ["g", "u", "q", "I", " ", "\n", "imq"] {
    assert_true(@xpath_regex.compile("a", flag) is Err(_), msg=flag)
  }
}

///|
test "Runtime budget reports an error for pathological backtracking" {
  let regex = @xpath_regex.compile("^(a|aa)+\\1b$", "").unwrap()
  assert_true(regex.matches("aaaaaaaaaaaaaaaaaaaaaaaaaaac") is Err(_))
  let repeated_empty = @xpath_regex.compile("(){2147483647}", "").unwrap()
  assert_true(repeated_empty.matches("") is Err(_))
  assert_true(
    @xpath_regex.compile("(".repeat(300) + ")".repeat(300), "") is Err(_),
  )
  assert_true(@xpath_regex.compile("a".repeat(100001), "") is Err(_))
}
