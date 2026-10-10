///|
test "RDF term conversion preserves value and identity" {
  let text =
    #|@prefix ex: <http://example.org/> .
    #|ex:s ex:p "a\n\U0001F680"@EN, "01"^^<http://www.w3.org/2001/XMLSchema#integer> .
    #|ex:s ex:p [ex:p "nested"] .
  let graph = match @turtle.parse(text) {
    Ok(g) => g
    Err(errors) => {
      fail(errors.join("\n"))
      return
    }
  }
  let values = graph.objects(
    @moonshacl.Iri("http://example.org/s"),
    "http://example.org/p",
  )
  assert_true(values.contains(@moonshacl.lang_literal("a\n🚀", "en")))
  assert_true(
    values.contains(@moonshacl.Literal("01", @moonshacl.xsd + "integer", None)),
  )
  assert_eq(graph.size(), 4)
}

///|
test "Parse errors do not produce partial valid graphs" {
  match @turtle.parse("<http://ex/s> <http://ex/p> <http://ex/o> . @broken") {
    Err(_) => ()
    Ok(_) => fail("must reject partial input")
  }
}
