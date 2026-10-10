///|
test "Literal delimiter and rdf:type compatibility regressions" {
  let text =
    #|@prefix ex: <urn:> .
    #|ex:s a ex:Person; ex:p "a;,#"@en,"b"@fr; ex:q '''long;"text"''' .
  let g = @turtle.parse(text) |> Result::unwrap
  assert_eq(g.size(), 4)
  assert_true(
    g
    .objects(@moonshacl.Iri("urn:s"), @moonshacl.rdf + "type")
    .contains(@moonshacl.Iri("urn:Person")),
  )
  assert_true(
    g
    .objects(@moonshacl.Iri("urn:s"), "urn:p")
    .contains(@moonshacl.lang_literal("a;,#", "en")),
  )
}

///|
test "No lenient grammar acceptance or named graph flattening" {
  for
    input in [
      "@prefix ex: <urn:> . ex:s ex:p \"x\" , .", "@prefix ex: <urn:> . ex:s ex:p ex:o garbage .",
      "@prefix ex: <urn:> . ex:s missing:p ex:o .", "@prefix ex: <urn:> . ex:g { ex:s ex:p ex:o . }",
      "@prefix ex: <urn:> . \"literal\" ex:p ex:o .",
    ] {
    match @turtle.parse(input) {
      Err(_) => ()
      Ok(_) => fail("accepted malformed/out-of-profile input: " + input)
    }
  }
}
