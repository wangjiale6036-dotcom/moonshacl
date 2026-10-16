///|
/// Compiled XPath 2.0 / SPARQL 1.1 regular expression. The immutable syntax tree
/// and pinned Unicode tables are shared safely across validation sessions.
pub struct Regex {
  expression : Expr
  nfa : Nfa?
  groups : Int
  ignore_case : Bool
  multiline : Bool
  dotall : Bool
}

///|
priv enum CharSet {
  Range(Int, Int)
  Category(String)
  Block(Int, Int)
  Space
  Word
  NameStart
  NameChar
  Union(Array[CharSet])
  Negate(CharSet)
  Subtract(CharSet, CharSet)
}

///|
enum Expr {
  Character(CharSet)
  Dot
  Start
  End
  Sequence(Array[Expr])
  Alternate(Array[Expr])
  Group(Int, Int, Expr)
  BackReference(Int)
  Repeat(Expr, Int, Int?, Bool)
}

///|
priv suberror ParseError {
  Invalid(String)
}

///|
priv struct Parser {
  chars : Array[Char]
  mut pos : Int
  mut groups : Int
  closed : Array[Bool]
}

///|
fn Parser::peek(self : Parser) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
fn Parser::take(self : Parser, c : Char) -> Bool {
  if self.peek() == Some(c) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Parser::expect(self : Parser, c : Char) -> Unit raise ParseError {
  if !self.take(c) {
    raise Invalid("Expected '\{c}' at codepoint \{self.pos}")
  }
}

///|
fn white(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
// XPath x removes whitespace BEFORE parsing, including between a backslash and
// its escape letter. It does not implement Perl's # comments or \ SPACE escape.
fn strip_whitespace(chars : Array[Char]) -> Array[Char] {
  let result : Array[Char] = []
  let mut depth = 0
  let mut escaped = false
  for c in chars {
    if depth == 0 && white(c) {
      continue
    }
    result.push(c)
    if escaped {
      escaped = false
    } else if c == '\\' {
      escaped = true
    } else if c == '[' {
      depth += 1
    } else if c == ']' && depth > 0 {
      depth -= 1
    }
  }
  result
}

///|
/// Compile the syntax of fn:matches in XPath 2.0 (Second Edition), as used by
/// SPARQL 1.1 REGEX. Only the standard i/m/s/x flags are accepted; repeats are
/// allowed. Invalid syntax or a compilation resource limit is an Err.
pub fn compile(pattern : String, flags : String) -> Result[Regex, String] {
  let mut insensitive = false
  let mut multiline = false
  let mut dotall = false
  let mut extended = false
  for c in flags.iter() {
    match c {
      'i' => insensitive = true
      'm' => multiline = true
      's' => dotall = true
      'x' => extended = true
      _ =>
        return Err("FORX0001: Unknown XPath 2.0 regular expression flag '\{c}'")
    }
  }
  if pattern.length() > 100000 {
    return Err(
      "Regular expression resource limit: pattern exceeds 100000 UTF-16 units",
    )
  }
  let raw = pattern.iter().to_array()
  let chars = if extended { strip_whitespace(raw) } else { raw }
  let parser : Parser = { chars, pos: 0, groups: 0, closed: [true], }
  let expression = parser.alternation(0) catch {
    Invalid(message) => return Err("FORX0002: " + message)
  }
  if parser.pos != chars.length() {
    return Err(
      "FORX0002: Unexpected '\{chars[parser.pos]}' at codepoint \{parser.pos}",
    )
  }
  Ok({
    expression,
    nfa: make_nfa(expression),
    groups: parser.groups,
    ignore_case: insensitive,
    multiline,
    dotall,
  })
}

///|
fn Parser::alternation(self : Parser, depth : Int) -> Expr raise ParseError {
  if depth > 256 {
    raise Invalid("Regular expression nesting exceeds resource limit 256")
  }
  let branches : Array[Expr] = [self.sequence(depth)]
  while self.take('|') {
    branches.push(self.sequence(depth))
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alternate(branches)
  }
}

///|
fn Parser::sequence(self : Parser, depth : Int) -> Expr raise ParseError {
  let parts : Array[Expr] = []
  while self.peek() != None &&
        self.peek() != Some('|') &&
        self.peek() != Some(')') {
    let atom = self.atom(depth)
    let mut min = 0
    let mut max : Int? = None
    let mut repeated = true
    if self.take('?') {
      max = Some(1)
    } else if self.take('*') {
      ()
    } else if self.take('+') {
      min = 1
    } else if self.take('{') {
      min = self.number()
      if self.take(',') {
        if self.peek() != Some('}') {
          max = Some(self.number())
        }
      } else {
        max = Some(min)
      }
      self.expect('}')
      if max is Some(m) && m < min {
        raise Invalid("Quantifier maximum is below minimum")
      }
    } else {
      repeated = false
    }
    if repeated {
      let reluctant = self.take('?')
      parts.push(Repeat(atom, min, max, reluctant))
    } else {
      parts.push(atom)
    }
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    Sequence(parts)
  }
}

///|
fn Parser::number(self : Parser) -> Int raise ParseError {
  let begin = self.pos
  let mut value = 0
  while self.peek() is Some(c) && c >= '0' && c <= '9' {
    let digit = c.to_int() - 48
    if value > (2147483647 - digit) / 10 {
      raise Invalid(
        "Quantifier exceeds implementation resource limit 2147483647",
      )
    }
    value = value * 10 + digit
    self.pos += 1
  }
  if self.pos == begin {
    raise Invalid("Expected decimal quantifier at codepoint \{begin}")
  }
  value
}

///|
fn Parser::atom(self : Parser, depth : Int) -> Expr raise ParseError {
  let c = self.chars[self.pos]
  self.pos += 1
  match c {
    '(' => {
      self.groups += 1
      if self.groups > 4096 {
        raise Invalid("Capture count exceeds resource limit 4096")
      }
      let group = self.groups
      self.closed.push(false)
      let body = self.alternation(depth + 1)
      self.expect(')')
      self.closed[group] = true
      Group(group, self.groups, body)
    }
    '[' => Character(self.character_class(depth + 1))
    '.' => Dot
    '^' => Start
    '$' => End
    '\\' =>
      if self.peek() is Some(n) && n >= '1' && n <= '9' {
        self.pos += 1
        let mut group = n.to_int() - 48
        while self.peek() is Some(d) && d >= '0' && d <= '9' {
          let next = group * 10 + d.to_int() - 48
          if next > self.groups {
            break
          }
          group = next
          self.pos += 1
        }
        if group > self.groups || !self.closed[group] {
          raise Invalid(
            "Back-reference must follow its completed capturing group",
          )
        }
        BackReference(group)
      } else {
        Character(self.escape())
      }
    '?' | '*' | '+' | '{' | '}' | ']' =>
      raise Invalid("Unexpected metacharacter '\{c}'")
    _ => Character(Range(c.to_int(), c.to_int()))
  }
}

///|
fn Parser::escape(self : Parser) -> CharSet raise ParseError {
  let c = match self.peek() {
    Some(c) => c
    None => raise Invalid("Trailing backslash")
  }
  self.pos += 1
  match c {
    'n' => Range(10, 10)
    'r' => Range(13, 13)
    't' => Range(9, 9)
    '\\'
    | '|'
    | '.'
    | '?'
    | '*'
    | '+'
    | '('
    | ')'
    | '{'
    | '}'
    | '-'
    | '['
    | ']'
    | '^'
    | '$' => Range(c.to_int(), c.to_int())
    's' => Space
    'S' => Negate(Space)
    'd' => Category("Nd")
    'D' => Negate(Category("Nd"))
    'w' => Word
    'W' => Negate(Word)
    'i' => NameStart
    'I' => Negate(NameStart)
    'c' => NameChar
    'C' => Negate(NameChar)
    'p' | 'P' => {
      self.expect('{')
      let mut property = ""
      while self.peek() is Some(p) && p != '}' {
        property += p.to_string()
        self.pos += 1
      }
      self.expect('}')
      let set = if valid_category(property) {
        Category(property)
      } else if property.has_prefix("Is") {
        let name = property[2:].to_owned()
        if ["HighSurrogates", "LowSurrogates", "HighPrivateUseSurrogates"].contains(
            name,
          ) {
          raise Invalid(
            "Surrogate blocks are excluded by the XML Schema character grammar",
          )
        }
        match block_ranges.get(name) {
          Some((a, b)) => Block(a, b)
          None => raise Invalid("Unknown Unicode 15.0 block '\{name}'")
        }
      } else {
        raise Invalid("Unknown Unicode general category '\{property}'")
      }
      if c == 'P' {
        Negate(set)
      } else {
        set
      }
    }
    _ => raise Invalid("Illegal XPath escape '\\\{c}'")
  }
}

///|
fn Parser::class_item(self : Parser) -> CharSet raise ParseError {
  let c = match self.peek() {
    Some(c) => c
    None => raise Invalid("Unterminated character class")
  }
  self.pos += 1
  match c {
    '\\' => self.escape()
    '[' | ']' => raise Invalid("Unescaped bracket in character class")
    _ => Range(c.to_int(), c.to_int())
  }
}

///|
// Opening [ was consumed. Subtraction must be the final member, and can nest.
fn Parser::character_class(
  self : Parser,
  depth : Int,
) -> CharSet raise ParseError {
  if depth > 256 {
    raise Invalid("Character class nesting exceeds resource limit 256")
  }
  let negative = self.take('^')
  let members : Array[CharSet] = []
  while self.peek() != Some(']') {
    if self.peek() == None {
      raise Invalid("Unterminated character class")
    }
    if self.peek() == Some('-') &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] == '[' {
      if members.is_empty() {
        raise Invalid("Character subtraction requires a base class")
      }
      self.pos += 2
      let sub = self.character_class(depth + 1)
      self.expect(']')
      let base = Union(members)
      return Subtract(if negative { Negate(base) } else { base }, sub)
    }
    if self.peek() == Some('-') &&
      !members.is_empty() &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] != ']' {
      raise Invalid(
        "Unescaped hyphen is allowed only at a character group's ends",
      )
    }
    let leading_dash = self.peek() == Some('-')
    let first = self.class_item()
    if !leading_dash &&
      self.peek() == Some('-') &&
      self.pos + 1 < self.chars.length() &&
      self.chars[self.pos + 1] != '[' &&
      self.chars[self.pos + 1] != ']' {
      self.pos += 1
      if self.peek() == Some('-') {
        raise Invalid("Range endpoint hyphen must be escaped")
      }
      let last = self.class_item()
      match (first, last) {
        (Range(a, _), Range(b, _)) => {
          if a > b {
            raise Invalid("Descending character range")
          }
          members.push(Range(a, b))
        }
        _ => raise Invalid("Range endpoints must each be a single character")
      }
    } else {
      members.push(first)
    }
  }
  self.expect(']')
  if members.is_empty() {
    raise Invalid("Empty character class")
  }
  let set = Union(members)
  if negative {
    Negate(set)
  } else {
    set
  }
}

///|
fn valid_category(name : String) -> Bool {
  [
    "L", "Lu", "Ll", "Lt", "Lm", "Lo", "M", "Mn", "Mc", "Me", "N", "Nd", "Nl", "No",
    "P", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po", "Z", "Zs", "Zl", "Zp", "S", "Sm",
    "Sc", "Sk", "So", "C", "Cc", "Cf", "Co", "Cn",
  ].contains(name)
}

///|
fn category(cp : Int) -> String {
  let mut lo = 0
  let mut hi = category_ranges.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let (a, b, value) = category_ranges[mid]
    if cp < a {
      hi = mid
    } else if cp > b {
      lo = mid + 1
    } else {
      return value
    }
  }
  "Cn"
}

///|
fn same_case(a : Int, b : Int) -> Bool {
  a == b ||
  (match case_variants.get(a) {
    Some(xs) => xs.contains(b)
    None => false
  })
}

///|
fn xml_name_start(cp : Int) -> Bool {
  cp == 58 ||
  cp == 95 ||
  (cp >= 65 && cp <= 90) ||
  (cp >= 97 && cp <= 122) ||
  (cp >= 0xC0 && cp <= 0xD6) ||
  (cp >= 0xD8 && cp <= 0xF6) ||
  (cp >= 0xF8 && cp <= 0x2FF) ||
  (cp >= 0x370 && cp <= 0x37D) ||
  (cp >= 0x37F && cp <= 0x1FFF) ||
  (cp >= 0x200C && cp <= 0x200D) ||
  (cp >= 0x2070 && cp <= 0x218F) ||
  (cp >= 0x2C00 && cp <= 0x2FEF) ||
  (cp >= 0x3001 && cp <= 0xD7FF) ||
  (cp >= 0xF900 && cp <= 0xFDCF) ||
  (cp >= 0xFDF0 && cp <= 0xFFFD) ||
  (cp >= 0x10000 && cp <= 0xEFFFF)
}

///|
fn CharSet::accepts(self : CharSet, cp : Int, insensitive : Bool) -> Bool {
  match self {
    Range(a, b) =>
      (cp >= a && cp <= b) ||
      (
        insensitive &&
        (match case_variants.get(cp) {
          Some(xs) => xs.any(v => v >= a && v <= b)
          None => false
        })
      )
    Block(a, b) => cp >= a && cp <= b
    Category(name) => category(cp).has_prefix(name)
    Space => cp == 32 || cp == 9 || cp == 10 || cp == 13
    Word => {
      let cat = category(cp)
      !(cat.has_prefix("P") || cat.has_prefix("Z") || cat.has_prefix("C"))
    }
    NameStart => xml_name_start(cp)
    NameChar =>
      xml_name_start(cp) ||
      cp == 45 ||
      cp == 46 ||
      (cp >= 48 && cp <= 57) ||
      cp == 0xB7 ||
      (cp >= 0x300 && cp <= 0x36F) ||
      (cp >= 0x203F && cp <= 0x2040)
    Union(sets) => sets.any(s => s.accepts(cp, insensitive))
    Negate(set) => !set.accepts(cp, insensitive)
    Subtract(base, sub) =>
      base.accepts(cp, insensitive) && !sub.accepts(cp, insensitive)
  }
}

///|
priv enum Work {
  Eval(Expr)
  CaptureEnd(Int, Int)
  Again(Expr, Int, Int?, Bool, Int, Int)
}

///|
priv struct State {
  mut pos : Int
  work : Array[Work]
  captures : Array[(Int, Int)]
}

///|
fn State::copy(self : State) -> State {
  { pos: self.pos, work: self.work.copy(), captures: self.captures.copy(), }
}

///|
/// Search for a match using Unicode codepoints and an explicit backtracking VM.
/// Runtime resource exhaustion returns Err; it is never reported as non-match.
pub fn Regex::matches(self : Regex, text : String) -> Result[Bool, String] {
  if text.length() > 2000000 {
    return Err(
      "Regular expression resource limit: input exceeds 2000000 UTF-16 units",
    )
  }
  let chars = text.iter().map(c => c.to_int()).to_array()
  if self.nfa is Some(program) {
    return self.match_nfa(program, chars)
  }
  let mut steps = 0
  for start = 0; start <= chars.length(); start = start + 1 {
    steps += self.groups + 1
    if steps > 2000000 {
      return Err(
        "Regular expression resource limit: matching work budget exhausted",
      )
    }
    let pending : Array[State] = [
      {
        pos: start,
        work: [Eval(self.expression)],
        captures: Array::make(self.groups + 1, (-1, -1)),
      },
    ]
    while pending.pop() is Some(state) {
      let mut failed = false
      while !state.work.is_empty() && !failed {
        steps += 1
        if steps > 2000000 ||
          pending.length() > 100000 ||
          state.work.length() > 100000 {
          return Err(
            "Regular expression resource limit: matching work budget exhausted",
          )
        }
        let work = state.work.pop().unwrap()
        match work {
          Eval(expr) =>
            match expr {
              Character(set) =>
                if state.pos < chars.length() &&
                  set.accepts(chars[state.pos], self.ignore_case) {
                  state.pos += 1
                } else {
                  failed = true
                }
              Dot =>
                // W3C erratum 15594 clarifies the XML Schema dot rule: CR and LF.
                if state.pos < chars.length() &&
                  (
                    self.dotall ||
                    (chars[state.pos] != 10 && chars[state.pos] != 13)
                  ) {
                  state.pos += 1
                } else {
                  failed = true
                }
              Start =>
                if !(state.pos == 0 ||
                  (
                    self.multiline &&
                    state.pos < chars.length() &&
                    chars[state.pos - 1] == 10
                  )) {
                  failed = true
                }
              End => {
                let end = if self.multiline {
                  (state.pos < chars.length() && chars[state.pos] == 10) ||
                  (
                    state.pos == chars.length() &&
                    (chars.is_empty() || chars[chars.length() - 1] != 10)
                  )
                } else {
                  state.pos == chars.length()
                }
                if !end {
                  failed = true
                }
              }
              Sequence(parts) =>
                for i = parts.length() - 1; i >= 0; i = i - 1 {
                  state.work.push(Eval(parts[i]))
                }
              Alternate(branches) => {
                for i = branches.length() - 1; i >= 1; i = i - 1 {
                  steps += state.work.length() + state.captures.length()
                  if steps > 2000000 {
                    return Err(
                      "Regular expression resource limit: matching work budget exhausted",
                    )
                  }
                  let alternative = state.copy()
                  alternative.work.push(Eval(branches[i]))
                  pending.push(alternative)
                }
                state.work.push(Eval(branches[0]))
              }
              Group(id, last, body) => {
                // A new iteration of an enclosing group clears captures of
                // nested groups that may not participate in this iteration.
                for group = id; group <= last; group = group + 1 {
                  state.captures[group] = (-1, -1)
                }
                state.work.push(CaptureEnd(id, state.pos))
                state.work.push(Eval(body))
              }
              BackReference(id) => {
                let (a, b) = state.captures[id]
                if a >= 0 {
                  if state.pos + b - a > chars.length() {
                    failed = true
                  } else {
                    for i = a; i < b; i = i + 1 {
                      let equal = if self.ignore_case {
                        same_case(chars[i], chars[state.pos + i - a])
                      } else {
                        chars[i] == chars[state.pos + i - a]
                      }
                      if !equal {
                        failed = true
                        break
                      }
                    }
                    if !failed {
                      state.pos += b - a
                    }
                  }
                }
              }
              Repeat(body, min, max, reluctant) =>
                state.work.push(Again(body, min, max, reluctant, 0, -1))
            }
          CaptureEnd(id, begin) => state.captures[id] = (begin, state.pos)
          Again(body, min, max, reluctant, count, previous) => {
            let can_stop = count >= min
            let can_repeat = !(max is Some(m) && count >= m) &&
              !(previous == state.pos && can_stop)
            if can_repeat {
              if can_stop {
                steps += state.work.length() + state.captures.length()
                if steps > 2000000 {
                  return Err(
                    "Regular expression resource limit: matching work budget exhausted",
                  )
                }
                let alternative = state.copy()
                if reluctant {
                  alternative.work.push(
                    Again(body, min, max, reluctant, count + 1, state.pos),
                  )
                  alternative.work.push(Eval(body))
                  pending.push(alternative)
                } else {
                  pending.push(alternative)
                  state.work.push(
                    Again(body, min, max, reluctant, count + 1, state.pos),
                  )
                  state.work.push(Eval(body))
                }
              } else {
                state.work.push(
                  Again(body, min, max, reluctant, count + 1, state.pos),
                )
                state.work.push(Eval(body))
              }
            } else if !can_stop {
              failed = true
            }
          }
        }
      }
      if !failed {
        return Ok(true)
      }
    }
  }
  Ok(false)
}
