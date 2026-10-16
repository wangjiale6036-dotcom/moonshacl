///|
// Numeric promotion follows SPARQL 1.1 section 17.3 and XPath 2.0 section 6.
// Decimal/integer ordering remains exact. Binary floats are rounded once to
// their own IEEE value space before promotion; in particular float -> double
// does not recover decimal precision lost on float construction.
fn valid_float_lexical(s : String) -> Bool {
  if ["INF", "-INF", "NaN"].contains(s) {
    return true
  }
  let parts = s.to_lower().split("e").to_array()
  if parts.length() < 1 || parts.length() > 2 {
    return false
  }
  unsigned_decimal(without_sign(parts[0].to_owned())) &&
  (parts.length() == 1 || digits(without_sign(parts[1].to_owned())))
}

///|
priv struct DecimalValue {
  coefficient : BigInt
  scale : Int
}

///|
fn parse_decimal(s : String) -> DecimalValue? {
  if !unsigned_decimal(without_sign(s)) {
    return None
  }
  let negative = s.has_prefix("-")
  let parts = without_sign(s).split(".").to_array()
  let scale = if parts.length() == 2 { parts[1].length() } else { 0 }
  let text = parts.map(p => p.to_owned()).join("")
  let n = @string.parse_bigint(text) catch { _ => return None }
  Some({ coefficient: if negative { -n } else { n }, scale, })
}

///|
fn decimal_power(n : Int) -> BigInt {
  BigInt::from_int(10).pow(BigInt::from_int(n))
}

///|
fn compare_decimal(a : DecimalValue, b : DecimalValue) -> Int {
  let scale = if a.scale > b.scale { a.scale } else { b.scale }
  let left = a.coefficient * decimal_power(scale - a.scale)
  let right = b.coefficient * decimal_power(scale - b.scale)
  scalar_sign(left.compare(right))
}

///|
fn scalar_sign(n : Int) -> Int {
  if n < 0 {
    -1
  } else if n > 0 {
    1
  } else {
    0
  }
}

///|
fn numeric_datatype(d : String) -> Bool {
  integer_datatype(d) ||
  d == xsd + "decimal" ||
  d == xsd + "float" ||
  d == xsd + "double"
}

///|
// Convert a finite decimal lexical form directly to binary32/binary64 using
// integer rational arithmetic and round-to-nearest, ties-to-even. This avoids
// host parsing differences and decimal -> double -> float double rounding.
fn binary_number(s : String, single : Bool) -> Double {
  let negative = s.has_prefix("-")
  let sign64 : UInt64 = if negative { 0x8000000000000000UL } else { 0UL }
  let infinity = (sign64 | 0x7ff0000000000000UL).reinterpret_as_double()
  if s == "NaN" {
    return 0x7ff8000000000000UL.reinterpret_as_double()
  }
  if s == "INF" || s == "-INF" {
    return infinity
  }
  let parts = without_sign(s).to_lower().split("e").to_array()
  let decimal = match parse_decimal(parts[0].to_owned()) {
    Some(d) => d
    None => return 0x7ff8000000000000UL.reinterpret_as_double()
  }
  let coefficient = decimal.coefficient
  if coefficient.is_zero() {
    return sign64.reinterpret_as_double()
  }
  let raw_exponent = if parts.length() == 2 {
    parse_integer(parts[1].to_owned()).unwrap()
  } else {
    BigInt::from_int(0)
  }
  let exponent = raw_exponent - BigInt::from_int(decimal.scale)
  let decimal_magnitude = exponent +
    BigInt::from_int(coefficient.to_string().length())
  if decimal_magnitude.compare_int(400) > 0 {
    return infinity
  }
  if decimal_magnitude.compare_int(-400) < 0 {
    return sign64.reinterpret_as_double()
  }
  // The preceding magnitude bounds also make this conversion to Int safe:
  // the coefficient length and scale cannot exceed the size of the input.
  let power = exponent.to_int()
  let numerator = if power >= 0 {
    coefficient * decimal_power(power)
  } else {
    coefficient
  }
  let denominator = if power < 0 {
    decimal_power(-power)
  } else {
    BigInt::from_int(1)
  }
  let mut exponent2 = numerator.bit_length() - denominator.bit_length()
  let below = if exponent2 >= 0 {
    numerator < denominator << exponent2
  } else {
    numerator << -exponent2 < denominator
  }
  if below {
    exponent2 = exponent2 - 1
  }
  let precision = if single { 24 } else { 53 }
  let max_exponent = if single { 127 } else { 1023 }
  let min_exponent = if single { -126 } else { -1022 }
  if exponent2 > max_exponent {
    return infinity
  }
  let normal_exponent = if exponent2 < min_exponent {
    min_exponent
  } else {
    exponent2
  }
  let unit_exponent = normal_exponent - (precision - 1)
  let n = if unit_exponent < 0 {
    numerator << -unit_exponent
  } else {
    numerator
  }
  let d = if unit_exponent > 0 {
    denominator << unit_exponent
  } else {
    denominator
  }
  let mut mantissa = n / d
  let twice_remainder = n % d * BigInt::from_int(2)
  if twice_remainder > d ||
    (twice_remainder == d && !(mantissa % BigInt::from_int(2)).is_zero()) {
    mantissa = mantissa + BigInt::from_int(1)
  }
  let mut e = normal_exponent
  if mantissa.bit_length() > precision {
    mantissa = mantissa >> 1
    e = e + 1
  }
  if e > max_exponent {
    return infinity
  }
  let hidden = BigInt::from_int(1) << (precision - 1)
  let biased = if mantissa < hidden { 0 } else { e - min_exponent + 1 }
  let fraction = if biased == 0 { mantissa } else { mantissa - hidden }
  if single {
    let sign : UInt = if negative { 0x80000000U } else { 0U }
    let bits = sign | (biased.reinterpret_as_uint() << 23) | fraction.to_uint()
    Float::reinterpret_from_uint(bits).to_double()
  } else {
    let bits = sign64 | (biased.to_uint64() << 52) | fraction.to_uint64()
    bits.reinterpret_as_double()
  }
}

///|
fn compare_numeric(a : String, ad : String, b : String, bd : String) -> Int? {
  let double = ad == xsd + "double" || bd == xsd + "double"
  let floating = double || ad == xsd + "float" || bd == xsd + "float"
  if !floating {
    return Some(
      compare_decimal(parse_decimal(a).unwrap(), parse_decimal(b).unwrap()),
    )
  }
  let left = binary_number(a, ad == xsd + "float" || !double)
  let right = binary_number(b, bd == xsd + "float" || !double)
  if left.is_nan() || right.is_nan() {
    return None
  }
  Some(if left < right { -1 } else if left > right { 1 } else { 0 })
}
