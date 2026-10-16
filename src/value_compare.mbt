///|
// This implements value comparison, never RDF term identity. The latter is
// deliberately retained for sh:in, sh:hasValue, sh:equals and sh:disjoint.
fn compare_terms(
  left : Term,
  right : Term,
  implicit_timezone? : Int? = None,
) -> Int? {
  let (a, ad, al, b, bd, bl) = match (left, right) {
    (Literal(a, ad, al), Literal(b, bd, bl)) => (a, ad, al, b, bd, bl)
    _ => return None
  }
  if !valid_lexical(a, ad, al) || !valid_lexical(b, bd, bl) {
    return None
  }
  if al is Some(_) || bl is Some(_) {
    return None
  }
  if ad == xsd + "string" && bd == xsd + "string" {
    // Unicode codepoint collation: String's UTF-16 ordering would misorder
    // supplementary characters relative to BMP private-use characters.
    let ac = a.iter().to_array()
    let bc = b.iter().to_array()
    let count = if ac.length() < bc.length() {
      ac.length()
    } else {
      bc.length()
    }
    for i = 0; i < count; i = i + 1 {
      if ac[i] < bc[i] {
        return Some(-1)
      }
      if ac[i] > bc[i] {
        return Some(1)
      }
    }
    return Some(scalar_sign(ac.length() - bc.length()))
  }
  let a = a.trim(chars=" \t\r\n").to_owned()
  let b = b.trim(chars=" \t\r\n").to_owned()
  if numeric_datatype(ad) && numeric_datatype(bd) {
    return compare_numeric(a, ad, b, bd)
  }
  if ad != bd {
    return None
  }
  if ad == xsd + "boolean" {
    let left = a == "true" || a == "1"
    let right = b == "true" || b == "1"
    return Some(if left == right { 0 } else if left { 1 } else { -1 })
  }
  if ad == xsd + "dateTime" || ad == xsd + "date" {
    return compare_calendar(
      parse_calendar(a, ad == xsd + "dateTime").unwrap(),
      parse_calendar(b, bd == xsd + "dateTime").unwrap(),
      implicit_timezone~,
    )
  }
  None
}
