///| MoonTTL owns Turtle parsing; this adapter converts its materialized RDF terms.

///| MoonTTL 0.3.0's literal suffix lexer includes adjacent comma/semicolon,

///| while its TriG engine compensates only for a trailing dot. Add whitespace

///| around these grammar delimiters, preserving strings, IRIs, comments and

///| escaped local-name punctuation. Grammar and materialization stay in MoonTTL.

///|
/// Parse error offsets refer to this lexically equivalent normalized document.
fn separate_delimiters(text : String) -> String {
  let chars = text.iter().to_array()
  let out = StringBuilder()
  let mut i = 0
  let mut quote : Char? = None
  let mut width = 1
  let mut in_iri = false
  let mut comment = false
  while i < chars.length() {
    let c = chars[i]
    if comment {
      out.write_char(c)
      if c == '\n' || c == '\r' {
        comment = false
      }
    } else if c == '\\' && i + 1 < chars.length() {
      out.write_char(c)
      i = i + 1
      out.write_char(chars[i])
    } else if quote is Some(q) {
      out.write_char(c)
      if c == q &&
        (
          width == 1 ||
          (i + 2 < chars.length() && chars[i + 1] == q && chars[i + 2] == q)
        ) {
        for _ in 1..<width {
          i = i + 1
          out.write_char(chars[i])
        }
        quote = None
      }
    } else if in_iri {
      out.write_char(c)
      if c == '>' {
        in_iri = false
      }
    } else if c == '"' || c == '\'' {
      quote = Some(c)
      width = if i + 2 < chars.length() &&
        chars[i + 1] == c &&
        chars[i + 2] == c {
        3
      } else {
        1
      }
      out.write_char(c)
      for _ in 1..<width {
        i = i + 1
        out.write_char(chars[i])
      }
    } else if c == '<' {
      in_iri = true
      out.write_char(c)
    } else if c == '#' {
      comment = true
      out.write_char(c)
    } else if c == ',' || c == ';' {
      out.write_string(" " + c.to_string() + " ")
    } else {
      out.write_char(c)
    }
    i = i + 1
  }
  out.to_string()
}

///|
fn unescape(s : String) -> Result[String, String] {
  let out = StringBuilder()
  let chars = s.iter().to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    i = i + 1
    if c != '\\' {
      out.write_char(c)
      continue
    }
    if i >= chars.length() {
      return Err("Truncated RDF escape")
    }
    let escaped = chars[i]
    i = i + 1
    match escaped {
      'n' => out.write_char('\n')
      'r' => out.write_char('\r')
      't' => out.write_char('\t')
      'b' => out.write_char('\u0008')
      'f' => out.write_char('\u000C')
      '\\' => out.write_char('\\')
      '"' => out.write_char('"')
      '\'' => out.write_char('\'')
      'u' | 'U' => {
        let count = if escaped == 'u' { 4 } else { 8 }
        if i + count > chars.length() {
          return Err("Truncated Unicode escape")
        }
        let mut scalar = 0
        for j in i..<(i + count) {
          let c = chars[j]
          let digit = if c >= '0' && c <= '9' {
            c.to_int() - '0'.to_int()
          } else if c >= 'a' && c <= 'f' {
            c.to_int() - 'a'.to_int() + 10
          } else if c >= 'A' && c <= 'F' {
            c.to_int() - 'A'.to_int() + 10
          } else {
            return Err("Invalid Unicode escape")
          }
          if scalar > 0x10FFFF / 16 {
            return Err("Unicode scalar outside RDF range")
          }
          scalar = scalar * 16 + digit
        }
        if scalar >= 0xD800 && scalar <= 0xDFFF {
          return Err("Surrogates are not RDF Unicode scalars")
        }
        match scalar.to_char() {
          Some(c) => out.write_char(c)
          None => return Err("Invalid Unicode scalar")
        }
        i = i + count
      }
      _ => return Err("Unknown RDF escape")
    }
  }
  Ok(out.to_string())
}

///|
fn iri(text : String) -> Result[String, String] {
  let text = if text.has_prefix("<") && text.has_suffix(">") {
    text[1:text.length() - 1].to_owned()
  } else {
    text
  }
  unescape(text)
}

///|
fn term(
  kind : @gen_nquads.TermKind,
  view : ArrayView[Byte],
  scope : String,
) -> Result[@moonshacl.Term, String] {
  let text = @utf8.decode(Bytes::from_array(view)) catch {
    _ => return Err("Malformed UTF-8 in RDF term")
  }
  match kind {
    Iri =>
      match iri(text) {
        Ok(s) => Ok(@moonshacl.Iri(s))
        Err(e) => Err(e)
      }
    BNode =>
      Ok(
        @moonshacl.Blank(
          scope +
          (if text.has_prefix("_:") { text[2:].to_owned() } else { text }),
        ),
      )
    Literal => {
      let quote : UInt16 = if text.has_prefix("\"") {
        0x22
      } else if text.has_prefix("'") {
        0x27
      } else {
        return Err("Materialized literal must be in RDF quoted form")
      }
      let width = if text.has_prefix("\"\"\"") || text.has_prefix("'''") {
        3
      } else {
        1
      }
      let mut end = width
      while end < text.length() {
        if text[end] == quote &&
          (
            width == 1 ||
            (
              end + 2 < text.length() &&
              text[end + 1] == quote &&
              text[end + 2] == quote
            )
          ) {
          break
        }
        if text[end] == 0x5C {
          end = end + 1
        }
        end = end + 1
      }
      if end >= text.length() {
        return Err("Unterminated materialized literal")
      }
      let value = match unescape(text[width:end].to_owned()) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let suffix = text[end + width:].to_owned()
      if suffix.is_empty() {
        return Ok(@moonshacl.literal(value))
      }
      if suffix.has_prefix("@") {
        let tag = suffix[1:].to_owned()
        if tag.contains("--") {
          return Err(
            "RDF 1.2 directional literals are outside the RDF 1.1 profile",
          )
        }
        return Ok(@moonshacl.lang_literal(value, tag))
      }
      if suffix.has_prefix("^^") {
        match iri(suffix[2:].to_owned()) {
          Ok(datatype) => Ok(@moonshacl.Literal(value, datatype, None))
          Err(e) => Err(e)
        }
      } else {
        Err("Unsupported materialized literal suffix")
      }
    }
    _ =>
      Err(
        "RDF 1.2 triple terms, formulas and variables are outside the RDF 1.1 profile",
      )
  }
}

///| Reject every parse/materialization error; never validate a partial graph.

///|
/// Use separate scopes when the shapes and data are separate RDF documents.
pub fn parse(
  text : String,
  base? : String = "https://moonshacl.invalid/input/",
  scope? : String = "",
) -> Result[@moonshacl.Graph, Array[String]] {
  let data = @utf8.encode(separate_delimiters(text)).to_array()
  let engine = @gen_trig.TrigEngine::from_bytes(
    data,
    dialect=@gen_trig.TrigDialect::Turtle,
  )
  // Validate fully materialized terms below; the slice-level prefix check in
  // MoonTTL 0.3.0 incorrectly rejects bare `a` when no rdf: prefix is declared.
  // This switch bypasses unresolved-term checks, not the grammar state machine.
  let parser = @gen_trig.TrigSliceParser::new(engine, data[:], lenient=true)
  let (quads, errors) = parser.parse_all()
  if !errors.is_empty() {
    return Err(errors.map(e => e.to_string()))
  }
  // At end-of-statement MoonTTL 0.3.0 can reset the KwA tag before emission.
  // The grammar has already identified predicate slots; the bare token `a`
  // in those slots unambiguously denotes rdf:type in the Turtle dialect.
  let quads = quads.map(q => {
    if q.p.1 == 1 && data[q.p.0] == b'a' {
      { ..q, pk: @gen_trig.PredKind::KwA, }
    } else {
      q
    }
  })
  let materializer = @gen_trig.TrigMaterializer::new(
    data[:],
    parser.prefixes(),
    bases=parser.bases(),
    base_fallback=Some(base),
  )
  let (emits, errors) = materializer.materialize_all(
    quads,
    deep_validate=true,
    mode=@gen_nquads.ValidateMode::Deep,
  )
  if !errors.is_empty() {
    return Err(errors.map(e => e.to_string()))
  }
  let triples : Array[@moonshacl.Triple] = []
  for emit in emits {
    if emit.g_kind != @gen_nquads.TermKind::DefaultGraph {
      return Err([
        "Named graphs require an explicit graph-selection policy and are outside this Turtle adapter",
      ])
    }
    let subject = match term(emit.s_kind, emit.s_view, scope) {
      Ok(s) => s
      Err(e) => return Err([e])
    }
    if subject is @moonshacl.Literal(_, _, _) {
      return Err(["RDF subjects cannot be literals"])
    }
    let object = match term(emit.o_kind, emit.o_view, scope) {
      Ok(o) => o
      Err(e) => return Err([e])
    }
    let predicate = @utf8.decode(Bytes::from_array(emit.predicate)) catch {
      _ => return Err(["Malformed predicate UTF-8"])
    }
    let predicate = match iri(predicate) {
      Ok(p) => p
      Err(e) => return Err([e])
    }
    triples.push({ subject, predicate, object, })
  }
  Ok(@moonshacl.Graph::new(triples))
}
