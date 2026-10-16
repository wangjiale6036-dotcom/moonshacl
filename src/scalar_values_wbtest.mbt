///|
fn scalar_literal(s : String, datatype : String) -> Term {
  Literal(s, xsd + datatype, None)
}

///|
fn scalar_compare(a : String, ad : String, b : String, bd : String) -> Int? {
  compare_terms(scalar_literal(a, ad), scalar_literal(b, bd))
}

///|
test "scalar explicit XPath implicit timezone context and compatibility default" {
  let unzoned = scalar_literal("2026-10-16T08:00:00", "dateTime")
  let utc = scalar_literal("2026-10-16T08:00:00Z", "dateTime")
  let midnight = scalar_literal("2026-10-16T00:00:00Z", "dateTime")
  assert_eq(compare_terms(unzoned, utc), None)
  assert_eq(compare_terms(unzoned, utc, implicit_timezone=Some(0)), Some(0))
  assert_eq(compare_terms(unzoned, utc, implicit_timezone=Some(480)), Some(-1))
  assert_eq(
    compare_terms(unzoned, midnight, implicit_timezone=Some(480)),
    Some(0),
  )
  assert_eq(compare_terms(utc, unzoned, implicit_timezone=Some(480)), Some(1))
  assert_eq(compare_terms(unzoned, utc, implicit_timezone=Some(-480)), Some(1))
  assert_eq(compare_terms(unzoned, utc, implicit_timezone=Some(841)), None)
  assert_eq(compare_terms(unzoned, utc, implicit_timezone=Some(-841)), None)
  assert_eq(compare_terms(utc, midnight, implicit_timezone=Some(480)), Some(1))
  let later_local = scalar_literal("2026-10-16T09:00:00", "dateTime")
  assert_eq(compare_terms(unzoned, later_local), Some(-1))
  assert_eq(
    compare_terms(unzoned, later_local, implicit_timezone=Some(-840)),
    Some(-1),
  )
  assert_eq(
    compare_terms(
      scalar_literal("2026-10-16", "date"),
      scalar_literal("2026-10-16Z", "date"),
      implicit_timezone=Some(0),
    ),
    Some(0),
  )
}

///|
fn scalar_property_plan(rule : String, parameter : Term) -> Plan {
  let shape = Iri("urn:scalar:shape")
  compile(
    Graph::new([
      {
        subject: shape,
        predicate: sh + "targetNode",
        object: Iri("urn:scalar:focus"),
      },
      {
        subject: shape,
        predicate: sh + "path",
        object: Iri("urn:scalar:left"),
      },
      { subject: shape, predicate: sh + rule, object: parameter, },
    ]),
  ).unwrap()
}

///|
fn scalar_graph(left : Array[Term], right : Array[Term]) -> Graph {
  let triples : Array[Triple] = []
  for value in left {
    triples.push({
      subject: Iri("urn:scalar:focus"),
      predicate: "urn:scalar:left",
      object: value,
    })
  }
  for value in right {
    triples.push({
      subject: Iri("urn:scalar:focus"),
      predicate: "urn:scalar:right",
      object: value,
    })
  }
  Graph::new(triples)
}

///|
test "scalar range integration retains exact values and reports NaN ill typed" {
  let bound = scalar_literal("1000.000000000000001", "decimal")
  let report = scalar_property_plan("minInclusive", bound).validate(
    scalar_graph(
      [
        scalar_literal("1000", "integer"),
        scalar_literal("bad", "decimal"),
        scalar_literal("NaN", "double"),
        scalar_literal("INF", "float"),
        bound,
      ],
      [],
    ),
  )
  assert_false(report.conforms)
  assert_eq(report.results.length(), 3)
  assert_true(
    report.results.all(r => {
      r.component == sh + "MinInclusiveConstraintComponent"
    }),
  )
  assert_true(
    report.results.any(r => r.value == Some(scalar_literal("1000", "integer"))),
  )
  assert_true(
    report.results.any(r => r.value == Some(scalar_literal("bad", "decimal"))),
  )
  assert_true(
    report.results.any(r => r.value == Some(scalar_literal("NaN", "double"))),
  )
}

///|
test "scalar pair integration emits each failing pair and accepts empty reference" {
  let plan = scalar_property_plan("lessThan", Iri("urn:scalar:right"))
  let left = [scalar_literal("3", "integer"), scalar_literal("NaN", "double")]
  let report = plan.validate(
    scalar_graph(left, [
      scalar_literal("1", "integer"),
      scalar_literal("2", "integer"),
    ]),
  )
  assert_false(report.conforms)
  assert_eq(report.results.length(), 4)
  assert_true(
    report.results.all(r => r.component == sh + "LessThanConstraintComponent"),
  )
  assert_eq(report.results.filter(r => r.value == Some(left[0])).length(), 2)
  assert_eq(report.results.filter(r => r.value == Some(left[1])).length(), 2)
  assert_true(plan.validate(scalar_graph(left, [])).conforms)
}

///|
test "scalar arbitrary datatype identity remains accepted and unrelated literals fail" {
  let value = Literal("arbitrary lexical spelling", "urn:custom:datatype", None)
  let plan = scalar_property_plan("datatype", Iri("urn:custom:datatype"))
  assert_true(plan.validate(scalar_graph([value], [])).conforms)
  let report = plan.validate(
    scalar_graph([value, scalar_literal("1", "integer")], []),
  )
  assert_eq(report.results.length(), 1)
  assert_eq(report.results[0].value, Some(scalar_literal("1", "integer")))
  assert_eq(report.results[0].component, sh + "DatatypeConstraintComponent")
}

///|
test "scalar integer decimal and unknown datatype lexical spaces" {
  for
    s in [
      "0", "-0", "+0001", " 42\t", "999999999999999999999999999999999999999999",
    ] {
    assert_true(valid_lexical(s, xsd + "integer", None))
    assert_true(parse_integer(s) is Some(_))
  }
  for s in ["", "+", "1.0", "1e1", "1 2", "--1", "１２"] {
    assert_false(valid_lexical(s, xsd + "integer", None))
    assert_true(parse_integer(s) is None)
  }
  for
    (d, low, high, below, above) in [
      ("byte", "-128", "127", "-129", "128"),
      ("short", "-32768", "32767", "-32769", "32768"),
      ("int", "-2147483648", "2147483647", "-2147483649", "2147483648"),
      (
        "long", "-9223372036854775808", "9223372036854775807", "-9223372036854775809",
        "9223372036854775808",
      ),
      ("unsignedByte", "0", "255", "-1", "256"),
      ("unsignedShort", "0", "65535", "-1", "65536"),
      ("unsignedInt", "0", "4294967295", "-1", "4294967296"),
      (
        "unsignedLong", "0", "18446744073709551615", "-1", "18446744073709551616",
      ),
    ] {
    assert_true(valid_lexical(low, xsd + d, None))
    assert_true(valid_lexical(high, xsd + d, None))
    assert_false(valid_lexical(below, xsd + d, None))
    assert_false(valid_lexical(above, xsd + d, None))
  }
  for
    (d, yes, no) in [
      ("positiveInteger", "1", "0"),
      ("negativeInteger", "-1", "0"),
      ("nonNegativeInteger", "0", "-1"),
      ("nonPositiveInteger", "0", "1"),
    ] {
    assert_true(valid_lexical(yes, xsd + d, None))
    assert_false(valid_lexical(no, xsd + d, None))
  }
  for s in ["0", ".1", "1.", "+.5", "-00.01", "\n123.45\r"] {
    assert_true(valid_lexical(s, xsd + "decimal", None))
  }
  for s in [".", "1e2", "INF", "NaN", "1.2.3", "1 2"] {
    assert_false(valid_lexical(s, xsd + "decimal", None))
  }
  assert_true(valid_lexical("anything", "urn:custom-datatype", None))
  assert_true(valid_lexical("anything", xsd + "unrecognized", None))
  assert_false(valid_lexical("anything", "urn:custom-datatype", Some("en")))
  assert_true(valid_lexical("hello", rdf + "langString", Some("en")))
  assert_false(valid_lexical("hello", rdf + "langString", None))
  assert_false(valid_lexical("hello", rdf + "langString", Some("")))
  assert_true(valid_lexical("P1Y2M3DT4H5M6.7S", xsd + "duration", None))
  assert_false(valid_lexical("P1.5Y", xsd + "duration", None))
  assert_true(valid_lexical("0123aB", xsd + "hexBinary", None))
  assert_false(valid_lexical("123", xsd + "hexBinary", None))
}

///|
test "scalar exact decimal ordering preserves digits beyond binary64" {
  for
    (a, ad, b, bd, result) in [
      ("9007199254740993", "integer", "9007199254740992", "integer", 1),
      (
        "999999999999999999999.999999999999999999999", "decimal", "1000000000000000000000",
        "integer", -1,
      ),
      (
        "-999999999999999999999.999999999999999999999", "decimal", "-1000000000000000000000",
        "integer", 1,
      ),
      ("1.0000000000000000000000000000000001", "decimal", "1", "integer", 1),
      ("+001.000", "decimal", "1", "byte", 0),
      ("-0.000", "decimal", "+0", "integer", 0),
      (".0001", "decimal", "0.001", "decimal", -1),
    ] {
    assert_eq(scalar_compare(a, ad, b, bd), Some(result))
    assert_eq(scalar_compare(b, bd, a, ad), Some(-result))
  }
  assert_eq(scalar_compare("128", "byte", "128", "integer"), None)
  assert_eq(scalar_compare("1e2", "decimal", "100", "integer"), None)
}

///|
test "scalar binary floating lexical and numeric promotion" {
  for
    s in [
      "0", "-0", "+0.0", "1E+2", "-.1e-2", "1.", "INF", "-INF", "NaN", "1e999999999999999999999",
      "1e-999999999999999999999",
    ] {
    assert_true(valid_lexical(s, xsd + "float", None))
    assert_true(valid_lexical(s, xsd + "double", None))
  }
  for
    s in [
      "+INF", "inf", "+NaN", "nan", "1e", "e1", "1e1e1", "1_0", "Infinity", "0x10",
      "1 e2",
    ] {
    assert_false(valid_lexical(s, xsd + "float", None))
    assert_false(valid_lexical(s, xsd + "double", None))
  }
  for
    (a, ad, b, bd, result) in [
      ("16777217", "integer", "16777216", "float", 0),
      ("16777217", "float", "16777217", "double", -1),
      ("9007199254740993", "integer", "9007199254740992", "double", 0),
      ("0.1", "float", "0.1", "double", 1),
      ("1e-50", "float", "0", "integer", 0),
      ("1e-45", "float", "0", "integer", 1),
      ("1e50", "float", "INF", "double", 0),
      ("-1e50", "float", "-INF", "double", 0),
      ("-0", "double", "0", "integer", 0),
      ("INF", "double", "1e308", "double", 1),
      ("-INF", "float", "-1e308", "double", -1),
    ] {
    assert_eq(scalar_compare(a, ad, b, bd), Some(result))
    assert_eq(scalar_compare(b, bd, a, ad), Some(-result))
  }
  assert_eq(scalar_compare("NaN", "double", "NaN", "double"), None)
  assert_eq(scalar_compare("NaN", "float", "0", "integer"), None)
  assert_eq(scalar_compare("0", "integer", "NaN", "double"), None)
}

///|
test "scalar binary32 direct rounding and binary64 subnormals" {
  // The second decimal lies just above the exact binary32 midpoint; parsing
  // via binary64 first would round it back to that midpoint and get this wrong.
  assert_eq(binary_number("1.000000059604644775390625", true), 1.0)
  assert_eq(
    binary_number("1.00000005960464477539062500000000001", true),
    1.00000011920928955078125,
  )
  assert_eq(
    binary_number("1.000000178813934326171875", true),
    1.0000002384185791015625,
  )
  assert_eq(binary_number("5e-324", false).reinterpret_as_uint64(), 1UL)
  assert_eq(
    binary_number("2.4703282292062327e-324", false).reinterpret_as_uint64(),
    0UL,
  )
  assert_eq(
    binary_number("2.4703282292062328e-324", false).reinterpret_as_uint64(),
    1UL,
  )
  assert_eq(
    binary_number("-0", false).reinterpret_as_uint64(),
    0x8000000000000000UL,
  )
  assert_eq(
    binary_number("1.7976931348623157e308", false).reinterpret_as_uint64(),
    0x7fefffffffffffffUL,
  )
  assert_true(binary_number("1.7976931348623159e308", false).is_pos_inf())
  assert_true(binary_number("1e999999999999999999999", false).is_pos_inf())
  assert_eq(binary_number("1e-999999999999999999999", false), 0.0)
}

///|
test "scalar dateTime and date lexical calendars" {
  for
    s in [
      "2000-02-29T00:00:00Z", "2026-10-16T08:30:59.12345678901234567890+14:00", "2026-12-31T24:00:00.000-14:00",
      "2026-01-01T00:00:00", "-0001-01-01T00:00:00Z", "12345678901234567890-01-01T00:00:00Z",
    ] {
    assert_true(valid_lexical(s, xsd + "dateTime", None))
  }
  for
    s in [
      "1900-02-29T00:00:00Z", "2100-02-29T00:00:00Z", "2026-02-30T00:00:00Z", "0000-01-01T00:00:00Z",
      "-0000-01-01T00:00:00Z", "02026-01-01T00:00:00Z", "+2026-01-01T00:00:00Z",
      "2026-13-01T00:00:00Z", "2026-00-01T00:00:00Z", "2026-01-00T00:00:00Z", "2026-01-32T00:00:00Z",
      "2026-1-01T00:00:00Z", "2026-01-01t00:00:00Z", "2026-01-01T25:00:00Z", "2026-01-01T24:00:00.01Z",
      "2026-01-01T24:01:00Z", "2026-01-01T00:60:00Z", "2026-01-01T00:00:60Z", "2026-01-01T00:00:00.Z",
      "2026-01-01T00:00:00+14:01", "2026-01-01T00:00:00-15:00", "2026-01-01T00:00:00+01:60",
      "2026-01-01T00:00:00z", "2026-01-01",
    ] {
    assert_false(valid_lexical(s, xsd + "dateTime", None))
  }
  for s in ["2026-10-16", "2000-02-29Z", "2026-12-31+14:00", "-0001-01-01"] {
    assert_true(valid_lexical(s, xsd + "date", None))
  }
  for
    s in [
      "not-a-date", "2026-02-30", "1900-02-29", "2026-10-16T00:00:00", "2026-01-01+14:01",
    ] {
    assert_false(valid_lexical(s, xsd + "date", None))
  }
}

///|
test "scalar dateTime timezone partial order and exact fraction" {
  for
    (a, b, result) in [
      ("2000-01-01T00:00:00Z", "1999-12-31T19:00:00-05:00", 0),
      ("2026-12-31T24:00:00Z", "2027-01-01T00:00:00Z", 0),
      ("2000-02-28T24:00:00Z", "2000-02-29T00:00:00Z", 0),
      ("-0001-12-31T24:00:00Z", "0001-01-01T00:00:00Z", 0),
      ("2026-10-16T08:00:00", "2026-10-17T08:00:00Z", -1),
      ("2026-10-16T08:00:00Z", "2026-10-17T08:00:00", -1),
      (
        "2026-10-16T08:00:00.1000000000000000000000000000000001Z", "2026-10-16T08:00:00.1Z",
        1,
      ),
      ("2026-10-16T08:00:00.1000Z", "2026-10-16T08:00:00.1Z", 0),
      (
        "99999999999999999999-12-31T00:00:00Z", "100000000000000000000-01-01T00:00:00Z",
        -1,
      ),
    ] {
    assert_eq(scalar_compare(a, "dateTime", b, "dateTime"), Some(result))
    assert_eq(scalar_compare(b, "dateTime", a, "dateTime"), Some(-result))
  }
  assert_eq(
    scalar_compare("2026-10-16", "date", "2026-10-17", "date"),
    Some(-1),
  )
  assert_eq(
    scalar_compare("2026-10-16", "date", "2026-10-16T00:00:00Z", "dateTime"),
    None,
  )
  for
    (a, b) in [
      ("2026-10-16T08:00:00", "2026-10-16T08:00:00Z"),
      ("2026-10-16T08:00:00", "2026-10-16T08:00:00+01:00"),
      ("2026-10-16T08:00:00", "2026-10-16T22:00:00Z"),
      ("2026-10-16T08:00:00", "2026-10-15T18:00:00Z"),
    ] {
    assert_eq(scalar_compare(a, "dateTime", b, "dateTime"), None)
    assert_eq(scalar_compare(b, "dateTime", a, "dateTime"), None)
  }
  assert_eq(
    scalar_compare(
      "2026-10-16T08:00:00", "dateTime", "2026-10-16T22:00:00.000000000000000000000000000001Z",
      "dateTime",
    ),
    Some(-1),
  )
}

///|
test "scalar string boolean and incomparable terms" {
  assert_eq(scalar_compare("abc", "string", "abd", "string"), Some(-1))
  assert_eq(scalar_compare("a", "string", "aa", "string"), Some(-1))
  assert_eq(scalar_compare("𐀀", "string", "\uE000", "string"), Some(1))
  assert_eq(scalar_compare(" true ", "boolean", "1", "boolean"), Some(0))
  assert_eq(scalar_compare("false", "boolean", "1", "boolean"), Some(-1))
  assert_eq(scalar_compare("TRUE", "boolean", "false", "boolean"), None)
  assert_eq(scalar_compare("1", "string", "1", "integer"), None)
  assert_eq(compare_terms(Iri("urn:a"), Iri("urn:a")), None)
  assert_eq(compare_terms(Blank("a"), literal("a")), None)
  assert_eq(
    compare_terms(
      Literal("a", rdf + "langString", Some("en")),
      Literal("b", rdf + "langString", Some("en")),
    ),
    None,
  )
  assert_eq(
    compare_terms(
      Literal("x", "urn:custom", None),
      Literal("x", "urn:custom", None),
    ),
    None,
  )
}
