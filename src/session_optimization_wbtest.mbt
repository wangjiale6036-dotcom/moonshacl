///|
fn optimization_triple(s : Term, p : String, o : Term) -> Triple {
  { subject: s, predicate: p, object: o, }
}

///|
fn optimization_results(report : Report) -> Array[String] {
  let result = report.results.map(r => r.to_json().stringify())
  result.sort()
  result
}

///|
fn optimization_mutate_nested_report(report : Report) -> Unit raise {
  let result = report.results[0]
  result.messages.clear()
  assert_eq(result.details.length(), 1)
  result.details[0].messages.clear()
  result.details.clear()
  match result.path {
    Some(Sequence(paths)) => paths.clear()
    _ => fail("Expected a sequence path on the nested violation")
  }
  report.results.clear()
}

///|
// Rebuild through the public graph constructor, independent of Session's delta
// bookkeeping. Compare every result field; counters describe different work.
fn optimization_assert_update(
  plan : Plan,
  session : Session,
  additions : Array[Triple],
  removals : Array[Triple],
) -> Unit raise {
  let before = session.graph()
  let expected_triples = before.triples().filter(t => !removals.contains(t))
  expected_triples.append(additions)
  let candidate = Graph::new(expected_triples)
  let full = plan.validate(candidate)
  let preview = session.preview(additions, removals)
  assert_eq(preview.conforms, full.conforms)
  assert_eq(optimization_results(preview), optimization_results(full))
  assert_eq(session.graph().to_ntriples(), before.to_ntriples())
  let update = session.apply(additions, removals)
  assert_eq(update.committed, full.conforms)
  assert_eq(optimization_results(update.report), optimization_results(full))
  assert_eq(
    session.graph().to_ntriples(),
    (if full.conforms { candidate } else { before }).to_ntriples(),
  )
  assert_eq(
    optimization_results(session.report()),
    optimization_results(plan.validate(session.graph())),
  )
}

///|
test "Optimized delta preserves RDF set identity and delete-before-add graph order" {
  let root = Iri("urn:delta:root")
  let shape = Iri("urn:delta:shape")
  let plan = compile(
    Graph::new([
      optimization_triple(shape, sh + "targetNode", root),
      optimization_triple(shape, sh + "path", Iri("urn:label")),
      optimization_triple(
        shape,
        sh + "minCount",
        Literal("1", xsd + "integer", None),
      ),
      optimization_triple(
        shape,
        sh + "maxCount",
        Literal("1", xsd + "integer", None),
      ),
    ]),
  ).unwrap()
  let upper = optimization_triple(
    root,
    "urn:label",
    Literal("Label", rdf + "langString", Some("EN")),
  )
  let lower = optimization_triple(
    root,
    "urn:label",
    lang_literal("Label", "en"),
  )
  let keep = optimization_triple(root, "urn:unconstrained", literal("keep"))
  let tail = optimization_triple(
    Iri("urn:delta:other"),
    "urn:note",
    literal("tail"),
  )
  let absent = optimization_triple(
    root,
    "urn:missing",
    literal("never present"),
  )
  let session = Session::new(plan, Graph::new([upper, keep, tail]))
  optimization_assert_update(plan, session, [lower, upper, keep, lower], [
    upper, lower, absent, absent,
  ])
  // Equal language tags denote one RDF value. Removing then adding it moves
  // that value after untouched triples and keeps the first addition's spelling.
  assert_eq(
    session.graph().to_ntriples(),
    Graph::new([keep, tail, lower]).to_ntriples(),
  )
  let no_change = session.preview([upper, lower], [absent, absent])
  assert_true(no_change.conforms)
  assert_eq(no_change.checked, 0)
  assert_eq(no_change.reused, 1)
  optimization_assert_update(plan, session, [upper, lower], [absent, absent])
  let extra = optimization_triple(root, "urn:label", lang_literal("Deux", "fr"))
  optimization_assert_update(plan, session, [extra, extra], [absent])
  assert_eq(
    session.graph().to_ntriples(),
    Graph::new([keep, tail, lower]).to_ntriples(),
  )
  optimization_assert_update(plan, session, [extra, extra], [upper, lower])
  assert_eq(
    session.graph().to_ntriples(),
    Graph::new([keep, tail, extra]).to_ntriples(),
  )
}

///|
test "One batch invalidates shared object, inverse and closed absence reads" {
  let person_shape = Iri("urn:batch:person-shape")
  let employer_shape = Iri("urn:batch:employer-shape")
  let company_shape = Iri("urn:batch:company-shape")
  let label_shape = Iri("urn:batch:label-shape")
  let inverse_shape = Iri("urn:batch:inverse-shape")
  let inverse_path = Blank("batch-inverse-path")
  let closed_shape = Iri("urn:batch:closed-shape")
  let allowed_shape = Iri("urn:batch:allowed-shape")
  let c1 = Iri("urn:batch:c1")
  let c2 = Iri("urn:batch:c2")
  let root = Iri("urn:batch:closed")
  let person = Iri("urn:batch:Person")
  let plan = compile(
    Graph::new([
      optimization_triple(person_shape, sh + "targetClass", person),
      optimization_triple(person_shape, sh + "property", employer_shape),
      optimization_triple(employer_shape, sh + "path", Iri("urn:employer")),
      optimization_triple(employer_shape, sh + "node", company_shape),
      optimization_triple(company_shape, sh + "property", label_shape),
      optimization_triple(label_shape, sh + "path", Iri("urn:label")),
      optimization_triple(
        label_shape,
        sh + "minCount",
        Literal("1", xsd + "integer", None),
      ),
      optimization_triple(inverse_shape, sh + "targetNode", c1),
      optimization_triple(inverse_shape, sh + "targetNode", c2),
      optimization_triple(inverse_shape, sh + "path", inverse_path),
      optimization_triple(inverse_path, sh + "inversePath", Iri("urn:employer")),
      optimization_triple(
        inverse_shape,
        sh + "maxCount",
        Literal("2", xsd + "integer", None),
      ),
      optimization_triple(closed_shape, sh + "targetNode", root),
      optimization_triple(
        closed_shape,
        sh + "closed",
        Literal("true", xsd + "boolean", None),
      ),
      optimization_triple(closed_shape, sh + "property", allowed_shape),
      optimization_triple(allowed_shape, sh + "path", Iri("urn:note")),
    ]),
  ).unwrap()
  let label = optimization_triple(c1, "urn:label", literal("First"))
  let p1 = Iri("urn:batch:p1")
  let p2 = Iri("urn:batch:p2")
  let session = Session::new(
    plan,
    Graph::new([
      optimization_triple(p1, rdf + "type", person),
      optimization_triple(p2, rdf + "type", person),
      optimization_triple(p1, "urn:employer", c1),
      optimization_triple(p2, "urn:employer", c1),
      label,
      optimization_triple(c2, "urn:label", literal("Second")),
    ]),
  )
  assert_true(session.report().conforms)
  let hires = [
    optimization_triple(Iri("urn:batch:p3"), "urn:employer", c2),
    optimization_triple(Iri("urn:batch:p4"), "urn:employer", c2),
    optimization_triple(Iri("urn:batch:p5"), "urn:employer", c2),
  ]
  let forbidden = optimization_triple(
    root,
    "urn:unexpected",
    literal("blocked"),
  )
  let invalid_batch = hires.copy()
  invalid_batch.push(forbidden)
  let preview = session.preview(invalid_batch, [label])
  assert_false(preview.conforms)
  assert_eq(preview.results.length(), 4)
  optimization_assert_update(plan, session, invalid_batch, [label])
  let repaired_label = optimization_triple(c1, "urn:label", literal("Renamed"))
  optimization_assert_update(
    plan,
    session,
    [
      hires[0],
      hires[1],
      repaired_label,
      optimization_triple(root, "urn:note", literal("allowed")),
    ],
    [label, forbidden],
  )
  assert_true(session.report().conforms)
  // The successful batch installs fresh inverse and absence dependencies.
  optimization_assert_update(plan, session, [hires[2], forbidden], [
    repaired_label,
  ])
  assert_true(session.report().conforms)
}

///|
test "Initially invalid cached nested reports isolate all mutable result arrays" {
  let shape = Iri("urn:copy:shape")
  let property = Iri("urn:copy:property")
  let child = Iri("urn:copy:child")
  let head = Blank("copy-path-1")
  let second = Blank("copy-path-2")
  let root = Iri("urn:copy:root")
  let middle = Iri("urn:copy:middle")
  let value = Iri("urn:copy:value")
  let plan = compile(
    Graph::new([
      optimization_triple(shape, sh + "targetNode", root),
      optimization_triple(shape, sh + "property", property),
      optimization_triple(property, sh + "path", head),
      optimization_triple(head, rdf + "first", Iri("urn:p")),
      optimization_triple(head, rdf + "rest", second),
      optimization_triple(second, rdf + "first", Iri("urn:q")),
      optimization_triple(second, rdf + "rest", Iri(rdf + "nil")),
      optimization_triple(property, sh + "node", child),
      optimization_triple(property, sh + "message", literal("outer message")),
      optimization_triple(child, sh + "class", Iri("urn:copy:Required")),
      optimization_triple(child, sh + "message", literal("inner message")),
    ]),
  ).unwrap()
  let initial = Graph::new([
    optimization_triple(root, "urn:p", middle),
    optimization_triple(middle, "urn:q", value),
  ])
  let session = Session::new(plan, initial)
  let expected = optimization_results(plan.validate(initial))
  assert_eq(expected.length(), 1)
  for
    report in [
      session.report(),
      session.preview([], []),
      session.apply([], []).report,
    ] {
    assert_false(report.conforms)
    assert_eq(optimization_results(report), expected)
    optimization_mutate_nested_report(report)
    assert_eq(optimization_results(session.report()), expected)
    assert_eq(optimization_results(plan.validate(initial)), expected)
  }
  // Newly evaluated preview results take a different ownership path from
  // cached results. Caller mutations must not reach the plan or either graph.
  let old_edge = optimization_triple(middle, "urn:q", value)
  let new_edge = optimization_triple(middle, "urn:q", Iri("urn:copy:other"))
  let candidate = Graph::new([
    optimization_triple(root, "urn:p", middle),
    new_edge,
  ])
  let candidate_results = optimization_results(plan.validate(candidate))
  for _ in 0..<2 {
    let report = session.preview([new_edge], [old_edge])
    assert_false(report.conforms)
    assert_eq(report.checked, 1)
    assert_eq(optimization_results(report), candidate_results)
    optimization_mutate_nested_report(report)
    assert_eq(optimization_results(plan.validate(candidate)), candidate_results)
    assert_eq(optimization_results(session.report()), expected)
    assert_eq(session.graph().to_ntriples(), initial.to_ntriples())
  }
  let repair = optimization_triple(
    value,
    rdf + "type",
    Iri("urn:copy:Required"),
  )
  optimization_assert_update(plan, session, [repair], [])
  assert_true(session.report().conforms)
}

///|
test "Failure after an earlier root is evaluated leaves invalid cache and graph intact" {
  let shape = Iri("urn:failure:shape")
  let name_shape = Iri("urn:failure:name-shape")
  let code_shape = Iri("urn:failure:code-shape")
  let a = Iri("urn:failure:a")
  let b = Iri("urn:failure:b")
  let plan = compile(
    Graph::new([
      optimization_triple(shape, sh + "targetNode", a),
      optimization_triple(shape, sh + "targetNode", b),
      optimization_triple(shape, sh + "property", name_shape),
      optimization_triple(shape, sh + "property", code_shape),
      optimization_triple(name_shape, sh + "path", Iri("urn:name")),
      optimization_triple(
        name_shape,
        sh + "minCount",
        Literal("1", xsd + "integer", None),
      ),
      optimization_triple(name_shape, sh + "datatype", Iri(xsd + "string")),
      optimization_triple(code_shape, sh + "path", Iri("urn:code")),
      optimization_triple(code_shape, sh + "pattern", literal("(){2147483647}")),
    ]),
  ).unwrap()
  let bad_name = optimization_triple(
    a,
    "urn:name",
    Literal("7", xsd + "integer", None),
  )
  let good_name = optimization_triple(a, "urn:name", literal("Alice"))
  let initial = Graph::new([
    bad_name,
    optimization_triple(b, "urn:name", literal("Bob")),
  ])
  let session = Session::new(plan, initial)
  let original = optimization_results(plan.validate(initial))
  assert_eq(original.length(), 1)
  let dangerous = optimization_triple(b, "urn:code", literal(""))
  let candidate = Graph::new([
    good_name,
    optimization_triple(b, "urn:name", literal("Bob")),
    dangerous,
  ])
  let full_failed = try {
    ignore(plan.validate(candidate))
    false
  } catch {
    ValidationFailure(_) => true
  }
  assert_true(full_failed)
  for preview in [true, false] {
    let failed = try {
      if preview {
        ignore(session.preview([good_name, dangerous], [bad_name]))
      } else {
        ignore(session.apply([good_name, dangerous], [bad_name]))
      }
      false
    } catch {
      ValidationFailure(_) => true
    }
    assert_true(failed)
    assert_eq(session.graph().to_ntriples(), initial.to_ntriples())
    assert_eq(optimization_results(session.report()), original)
  }
  // A different rejected report must not replace the original datatype result.
  optimization_assert_update(plan, session, [], [bad_name])
  assert_eq(optimization_results(session.report()), original)
  optimization_assert_update(plan, session, [good_name], [bad_name, dangerous])
  assert_true(session.report().conforms)
  optimization_assert_update(plan, session, [], [good_name])
  assert_true(session.report().conforms)
}
