///|
test "NFA and capture VM agree on exhaustive short strings with nested empty repeats" {
  let strings : Array[String] = [""]
  let mut frontier : Array[String] = [""]
  for length = 0; length < 4; length = length + 1 {
    let next : Array[String] = []
    for prefix in frontier {
      for c in ["a", "b", "\n"] {
        let text = prefix + c
        strings.push(text)
        next.push(text)
      }
    }
    frontier = next
  }
  for
    pattern in [
      "a", "a|b", "a?b*", "(a*)*", "(a+)+", "(a|)*b", "((a|b)*)*", "^(a?|b)*$", "(a?){2,3}b",
      "(a|ab){0,3}", "((a?)*)+b", "a{2,3}b?", "^$", "^a", "b$", "^.*$", "(^|a)$",
      "^a.b$", "a|^b", "[ab-[b]]+", "[a-z-[ab]]*", "a??b*?", "a{0}b", "(ab){2}",
      "(a{2}){2,3}", "(a|b){0,2}?a", "((a|)b?){2,}",
    ] {
    for flags in ["", "m", "s", "ms"] {
      let fast = compile(pattern, flags).unwrap()
      assert_true(fast.nfa is Some(_), msg=pattern)
      let slow : Regex = {
        expression: fast.expression,
        nfa: None,
        groups: fast.groups,
        ignore_case: fast.ignore_case,
        multiline: fast.multiline,
        dotall: fast.dotall,
      }
      for text in strings {
        assert_eq(
          fast.matches(text),
          slow.matches(text),
          msg="\{pattern},\{flags},\{text}",
        )
      }
    }
  }
}
