///|
test "Regex execution failure propagates through nested constraints and never commits" {
  // This legal expression exceeds the deterministic step budget on empty text.
  let plan = plan_from(
    (
      #|@prefix sh: <http://www.w3.org/ns/shacl#> .
      #|<urn:S> sh:targetNode <urn:item>; sh:property [sh:path <urn:code>;
      #| sh:or ([sh:pattern "(){2147483647}"] [sh:nodeKind sh:Literal])] .
    ),
  )
  let empty = @moonshacl.Graph::new([])
  let session = @moonshacl.Session::new(plan, empty)
  let addition = parse("<urn:item> <urn:code> \"\" .") |> Result::unwrap
  let before = session.report().to_json().stringify()
  let failed_full = try {
    ignore(plan.validate(addition))
    false
  } catch {
    @moonshacl.ValidationFailure(_) => true
  }
  assert_true(failed_full)
  let failed_preview = try {
    ignore(session.preview(addition.triples(), []))
    false
  } catch {
    @moonshacl.ValidationFailure(_) => true
  }
  assert_true(failed_preview)
  let failed_apply = try {
    ignore(session.apply(addition.triples(), []))
    false
  } catch {
    @moonshacl.ValidationFailure(_) => true
  }
  assert_true(failed_apply)
  assert_eq(session.graph().size(), 0)
  assert_eq(session.report().to_json().stringify(), before)
  assert_true(
    plan.validate_node(
      addition,
      @moonshacl.Iri("urn:S"),
      @moonshacl.Iri("urn:item"),
    )
    is Err(_),
  )
}
