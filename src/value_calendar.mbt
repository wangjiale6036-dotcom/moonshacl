///|
priv struct CalendarValue {
  seconds : BigInt
  fraction : String
  has_timezone : Bool
}

///|
fn calendar_floor_div(n : BigInt, d : Int) -> BigInt {
  let divisor = BigInt::from_int(d)
  let quotient = n / divisor
  if n.compare_int(0) < 0 && !(n % divisor).is_zero() {
    quotient - BigInt::from_int(1)
  } else {
    quotient
  }
}

///|
fn calendar_two_digits(s : String) -> Int? {
  if s.length() != 2 || !digits(s) {
    return None
  }
  Some(@string.parse_int(s) catch { _ => return None })
}

///|
// XML Schema 1.0 lexical/calendar rules, as referenced by SPARQL 1.1:
// https://www.w3.org/TR/2004/REC-xmlschema-2-20041028/#dateTime
// SHACL's approved minInclusive-003 fixture requires mixed timezone values
// to remain incomparable when timezone uncertainty can change the ordering.
// Apply the XSD section 3.2.7.4 +/-14h partial order, without inventing a host
// timezone. Both explicitly zoned values are normalized to UTC.
// This default is an explicit SHACL-fixture compatibility choice: XPath 2.0
// section 10.4 instead supplies a dynamic implicit timezone and a total order.
// compare_calendar's optional context implements that latter rule when given.
// Do not describe these two modes as identical, or infer all-host conformance
// from passing the pinned SHACL test suite in compatibility mode.
// https://www.w3.org/TR/2007/REC-xpath-functions-20070123/#comp.datetime
// https://github.com/w3c/data-shapes/blob/07458ebb1ece6addc664636d70b08444a7b66609/data-shapes-test-suite/tests/core/node/minInclusive-003.ttl
fn parse_calendar(s : String, datetime : Bool) -> CalendarValue? {
  let mut body = s
  let mut offset = 0
  let mut has_timezone = false
  if body.has_suffix("Z") {
    has_timezone = true
    body = body[:body.length() - 1].to_owned()
  } else if body.length() >= 6 {
    let tail = body[body.length() - 6:].to_owned()
    if (tail.has_prefix("+") || tail.has_prefix("-")) && tail[3:4] == ":" {
      has_timezone = true
      let hours = match calendar_two_digits(tail[1:3].to_owned()) {
        Some(n) => n
        None => return None
      }
      let minutes = match calendar_two_digits(tail[4:6].to_owned()) {
        Some(n) => n
        None => return None
      }
      if hours > 14 || minutes > 59 || (hours == 14 && minutes != 0) {
        return None
      }
      offset = (hours * 60 + minutes) * 60
      if tail.has_prefix("-") {
        offset = -offset
      }
      body = body[:body.length() - 6].to_owned()
    }
  }
  let fields = body.split("T").to_array()
  if fields.length() != (if datetime { 2 } else { 1 }) {
    return None
  }
  let date = fields[0].to_owned()
  let negative_year = date.has_prefix("-")
  let date = if negative_year { date[1:].to_owned() } else { date }
  let date_fields = date.split("-").to_array()
  if date_fields.length() != 3 {
    return None
  }
  let year_text = date_fields[0].to_owned()
  if year_text.length() < 4 ||
    !digits(year_text) ||
    (year_text.length() > 4 && year_text.has_prefix("0")) {
    return None
  }
  let year = match parse_integer(year_text) {
    Some(n) => n
    None => return None
  }
  if year.is_zero() {
    return None
  }
  // Gregorian arithmetic uses astronomical numbering; XML Schema 1.0 does
  // not have a year zero, so -0001 (1 BCE) maps to astronomical year zero.
  let year = if negative_year { BigInt::from_int(1) - year } else { year }
  let month = match calendar_two_digits(date_fields[1].to_owned()) {
    Some(n) => n
    None => return None
  }
  let day = match calendar_two_digits(date_fields[2].to_owned()) {
    Some(n) => n
    None => return None
  }
  if month < 1 || month > 12 || day < 1 {
    return None
  }
  let leap = (year % BigInt::from_int(4)).is_zero() &&
    (
      !(year % BigInt::from_int(100)).is_zero() ||
      (year % BigInt::from_int(400)).is_zero()
    )
  let months = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  if day > months[month - 1] {
    return None
  }
  let previous = year - BigInt::from_int(1)
  let mut days = previous * BigInt::from_int(365) +
    calendar_floor_div(previous, 4) -
    calendar_floor_div(previous, 100) +
    calendar_floor_div(previous, 400)
  for i = 0; i < month - 1; i = i + 1 {
    days = days + BigInt::from_int(months[i])
  }
  days = days + BigInt::from_int(day - 1)
  let mut time_seconds = 0
  let mut fraction = ""
  if datetime {
    let time = fields[1].split(":").to_array()
    if time.length() != 3 {
      return None
    }
    let hours = match calendar_two_digits(time[0].to_owned()) {
      Some(n) => n
      None => return None
    }
    let minutes = match calendar_two_digits(time[1].to_owned()) {
      Some(n) => n
      None => return None
    }
    let second_parts = time[2].split(".").to_array()
    if second_parts.length() > 2 {
      return None
    }
    let seconds = match calendar_two_digits(second_parts[0].to_owned()) {
      Some(n) => n
      None => return None
    }
    if second_parts.length() == 2 {
      fraction = second_parts[1].to_owned()
      if !digits(fraction) {
        return None
      }
    }
    if hours > 24 || minutes > 59 || seconds > 59 {
      return None
    }
    if hours == 24 &&
      (minutes != 0 || seconds != 0 || fraction.iter().any(c => c != '0')) {
      return None
    }
    time_seconds = hours * 3600 + minutes * 60 + seconds
  }
  Some({
    seconds: days * BigInt::from_int(86400) +
    BigInt::from_int(time_seconds - offset),
    fraction,
    has_timezone,
  })
}

///|
fn compare_calendar_instant(a : CalendarValue, b : CalendarValue) -> Int {
  let seconds = scalar_sign(a.seconds.compare(b.seconds))
  if seconds != 0 {
    return seconds
  }
  // Fractional seconds are exact and may exceed host floating point precision.
  let left = parse_decimal(
    "0." + (if a.fraction.is_empty() { "0" } else { a.fraction }),
  ).unwrap()
  let right = parse_decimal(
    "0." + (if b.fraction.is_empty() { "0" } else { b.fraction }),
  ).unwrap()
  compare_decimal(left, right)
}

///|
fn compare_calendar(
  a : CalendarValue,
  b : CalendarValue,
  implicit_timezone? : Int? = None,
) -> Int? {
  if implicit_timezone is Some(minutes) {
    if minutes < -840 || minutes > 840 {
      return None
    }
    let shift = BigInt::from_int(minutes * 60)
    let left = if a.has_timezone {
      a
    } else {
      { ..a, seconds: a.seconds - shift, }
    }
    let right = if b.has_timezone {
      b
    } else {
      { ..b, seconds: b.seconds - shift, }
    }
    return Some(compare_calendar_instant(left, right))
  }
  if a.has_timezone == b.has_timezone {
    return Some(compare_calendar_instant(a, b))
  }
  if !a.has_timezone {
    return compare_calendar(b, a).map(n => -n)
  }
  let earliest = { ..b, seconds: b.seconds - BigInt::from_int(50400), }
  let latest = { ..b, seconds: b.seconds + BigInt::from_int(50400), }
  if compare_calendar_instant(a, earliest) < 0 {
    return Some(-1)
  }
  if compare_calendar_instant(a, latest) > 0 {
    return Some(1)
  }
  None
}
