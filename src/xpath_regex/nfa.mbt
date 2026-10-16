///|
// Thompson NFA for the regular subset. Captures are irrelevant to fn:matches
// unless a back-reference reads them. Epsilon closure is visited once per input
// position, avoiding exponential repartitioning of nested repeats such as (.+)+.
priv enum Instruction {
  Accept
  Consume(CharSet, Int)
  Any(Int)
  Begin(Int)
  Finish(Int)
  Split(Int, Int)
}

///|
struct Nfa {
  code : Array[Instruction]
  entry : Int
}

///|
priv suberror NfaLimit {
  Fallback
}

///|
fn nfa_emit(code : Array[Instruction], op : Instruction) -> Int raise NfaLimit {
  if code.length() >= 50000 {
    raise Fallback
  }
  let index = code.length()
  code.push(op)
  index
}

///|
fn nfa_compile(
  expr : Expr,
  next : Int,
  code : Array[Instruction],
) -> Int raise NfaLimit {
  match expr {
    Character(set) => nfa_emit(code, Consume(set, next))
    Dot => nfa_emit(code, Any(next))
    Start => nfa_emit(code, Begin(next))
    End => nfa_emit(code, Finish(next))
    BackReference(_) => raise Fallback
    Group(_, _, body) => nfa_compile(body, next, code)
    Sequence(parts) => {
      let mut tail = next
      for i = parts.length() - 1; i >= 0; i = i - 1 {
        tail = nfa_compile(parts[i], tail, code)
      }
      tail
    }
    Alternate(branches) => {
      let mut tail = nfa_compile(branches[branches.length() - 1], next, code)
      for i = branches.length() - 2; i >= 0; i = i - 1 {
        let start = nfa_compile(branches[i], next, code)
        tail = nfa_emit(code, Split(start, tail))
      }
      tail
    }
    Repeat(body, min, max, _) => {
      // Large bounds remain compact in the backtracking VM. Falling back here
      // neither rejects valid syntax nor changes its semantics.
      if min > 1000 || (max is Some(m) && m > 1000) {
        raise Fallback
      }
      let mut tail = next
      match max {
        None => {
          let loop_at = nfa_emit(code, Accept)
          let begin = nfa_compile(body, loop_at, code)
          code[loop_at] = Split(begin, next)
          tail = loop_at
        }
        Some(bound) =>
          for i = min; i < bound; i = i + 1 {
            let begin = nfa_compile(body, tail, code)
            tail = nfa_emit(code, Split(begin, tail))
          }
      }
      for i = 0; i < min; i = i + 1 {
        tail = nfa_compile(body, tail, code)
      }
      tail
    }
  }
}

///|
fn make_nfa(expr : Expr) -> Nfa? {
  let code : Array[Instruction] = [Accept]
  let entry = nfa_compile(expr, 0, code) catch { Fallback => return None }
  Some({ code, entry, })
}

///|
fn Regex::match_nfa(
  self : Regex,
  nfa : Nfa,
  chars : Array[Int],
) -> Result[Bool, String] {
  let mut active : Array[Int] = []
  let mut steps = 0
  let visited : Array[Int] = Array::make(nfa.code.length(), -1)
  for pos = 0; pos <= chars.length(); pos = pos + 1 {
    active.push(nfa.entry)
    let next : Array[Int] = []
    while active.pop() is Some(pc) {
      if visited[pc] == pos {
        continue
      }
      visited[pc] = pos
      steps += 1
      if steps > 2000000 {
        return Err(
          "Regular expression resource limit: matching work budget exhausted",
        )
      }
      match nfa.code[pc] {
        Accept => return Ok(true)
        Split(a, b) => {
          active.push(a)
          active.push(b)
        }
        Begin(tail) =>
          if pos == 0 ||
            (self.multiline && pos < chars.length() && chars[pos - 1] == 10) {
            active.push(tail)
          }
        Finish(tail) => {
          let at_end = if self.multiline {
            (pos < chars.length() && chars[pos] == 10) ||
            (
              pos == chars.length() &&
              (chars.is_empty() || chars[chars.length() - 1] != 10)
            )
          } else {
            pos == chars.length()
          }
          if at_end {
            active.push(tail)
          }
        }
        Consume(set, tail) =>
          if pos < chars.length() && set.accepts(chars[pos], self.ignore_case) {
            next.push(tail)
          }
        Any(tail) =>
          if pos < chars.length() &&
            (self.dotall || (chars[pos] != 10 && chars[pos] != 13)) {
            next.push(tail)
          }
      }
    }
    active = next
  }
  Ok(false)
}
