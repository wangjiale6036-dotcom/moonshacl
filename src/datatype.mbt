///|
fn supported_datatype(datatype : String) -> Bool {
  datatype == rdf + "langString" ||
  [
    "string", "boolean", "integer", "int", "long", "short", "byte", "unsignedLong",
    "unsignedInt", "unsignedShort", "unsignedByte", "positiveInteger", "negativeInteger",
    "nonNegativeInteger", "nonPositiveInteger", "decimal", "hexBinary", "duration",
  ].any(d => datatype == xsd + d)
}

///|
fn digits(s : String) -> Bool {
  !s.is_empty() && s.iter().all(c => c >= '0' && c <= '9')
}

///|
fn unsigned_decimal(s : String) -> Bool {
  let parts = s.split(".").to_array()
  if parts.length() == 1 {
    digits(s)
  } else if parts.length() == 2 {
    (parts[0].is_empty() || digits(parts[0].to_owned())) &&
    (parts[1].is_empty() || digits(parts[1].to_owned())) &&
    !(parts[0].is_empty() && parts[1].is_empty())
  } else {
    false
  }
}

///|
fn without_sign(s : String) -> String {
  if s.has_prefix("+") || s.has_prefix("-") {
    s[1:].to_owned()
  } else {
    s
  }
}

///|
fn valid_duration(s : String) -> Bool {
  let s = if s.has_prefix("-") { s[1:].to_owned() } else { s }
  if !s.has_prefix("P") {
    return false
  }
  let mut token = ""
  let mut time = false
  let mut last = -1
  let mut components = 0
  let mut time_components = 0
  for c in s[1:].iter() {
    if c == 'T' {
      if time || !token.is_empty() {
        return false
      }
      time = true
      last = -1
    } else if (c >= '0' && c <= '9') || c == '.' {
      token = token + c.to_string()
    } else {
      let position = if time {
        match c {
          'H' => 0
          'M' => 1
          'S' => 2
          _ => -1
        }
      } else {
        match c {
          'Y' => 0
          'M' => 1
          'D' => 2
          _ => -1
        }
      }
      if position <= last || position < 0 {
        return false
      }
      if !(if time && c == 'S' {
          let parts = token.split(".").to_array()
          (parts.length() == 1 && digits(token)) ||
          (
            parts.length() == 2 &&
            digits(parts[0].to_owned()) &&
            digits(parts[1].to_owned())
          )
        } else {
          digits(token)
        }) {
        return false
      }
      components = components + 1
      if time {
        time_components = time_components + 1
      }
      last = position
      token = ""
    }
  }
  token.is_empty() && components > 0 && (!time || time_components > 0)
}

///|
fn valid_lexical(value : String, datatype : String, language : String?) -> Bool {
  if datatype == rdf + "langString" {
    return language is Some(tag) && !tag.is_empty()
  }
  if language is Some(_) {
    return false
  }
  if datatype == xsd + "string" {
    return true
  }
  let s = value.trim(chars=" \t\r\n").to_owned()
  if datatype == xsd + "boolean" {
    return ["true", "false", "1", "0"].contains(s)
  }
  if datatype == xsd + "decimal" {
    return unsigned_decimal(without_sign(s))
  }
  if datatype == xsd + "hexBinary" {
    return s.length() % 2 == 0 &&
      s
      .iter()
      .all(c => {
        (c >= '0' && c <= '9') ||
        (c >= 'a' && c <= 'f') ||
        (c >= 'A' && c <= 'F')
      })
  }
  if datatype == xsd + "duration" {
    return valid_duration(s)
  }
  if !digits(without_sign(s)) {
    return false
  }
  let numeric = if s.has_prefix("+") { s[1:].to_owned() } else { s }
  let n = @string.parse_bigint(numeric) catch { _ => return false }
  let bounds : (String, String)? = match datatype[xsd.length():].to_owned() {
    "byte" => Some(("-128", "127"))
    "short" => Some(("-32768", "32767"))
    "int" => Some(("-2147483648", "2147483647"))
    "long" => Some(("-9223372036854775808", "9223372036854775807"))
    "unsignedByte" => Some(("0", "255"))
    "unsignedShort" => Some(("0", "65535"))
    "unsignedInt" => Some(("0", "4294967295"))
    "unsignedLong" => Some(("0", "18446744073709551615"))
    "positiveInteger" => return n.compare_int(0) > 0
    "negativeInteger" => return n.compare_int(0) < 0
    "nonNegativeInteger" => return n.compare_int(0) >= 0
    "nonPositiveInteger" => return n.compare_int(0) <= 0
    "integer" => return true
    _ => return false
  }
  match bounds {
    Some((low, high)) => {
      let lo = @string.parse_bigint(low) catch { _ => return false }
      let hi = @string.parse_bigint(high) catch { _ => return false }
      n.compare(lo) >= 0 && n.compare(hi) <= 0
    }
    None => false
  }
}
