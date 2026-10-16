///|
fn expected_path(graph : @moonshacl.Graph, node : @moonshacl.Term) -> Json {
  let shape = @moonshacl.Iri("urn:test:shape")
  let augmented = graph.triples()
  augmented.push({
    subject: shape,
    predicate: @moonshacl.sh + "path",
    object: node,
  })
  augmented.push({
    subject: shape,
    predicate: @moonshacl.sh + "hasValue",
    object: @moonshacl.Iri("urn:missing"),
  })
  match @moonshacl.compile(@moonshacl.Graph::new(augmented)) {
    Ok(p) =>
      match
        p.validate_node(
          @moonshacl.Graph::new([]),
          shape,
          @moonshacl.Iri("urn:focus"),
        ) {
        Ok(r) =>
          match r.results.get(0) {
            Some(r) =>
              match r.path {
                Some(path) => path.to_json()
                None => Json::null()
              }
            None => Json::null()
          }
        Err(_) => Json::null()
      }
    Err(_) => Json::null()
  }
}

///|
fn signature(graph : @moonshacl.Graph, node : @moonshacl.Term) -> String {
  let get = fn(p : String) -> Json {
    match graph.objects(node, @moonshacl.sh + p).get(0) {
      Some(n) => n.to_json()
      None => Json::null()
    }
  }
  let result_path = match
    graph.objects(node, @moonshacl.sh + "resultPath").get(0) {
    Some(@moonshacl.Iri(p)) => @moonshacl.Path::Predicate(p).to_json()
    Some(n) => expected_path(graph, n)
    None => Json::null()
  }
  let json : Json = {
    "focus": get("focusNode"),
    "shape": get("sourceShape"),
    "component": get("sourceConstraintComponent"),
    "severity": get("resultSeverity"),
    "value": get("value"),
    "path": result_path,
  }
  json.stringify()
}

///|
fn actual_signature(r : @moonshacl.ValidationResult) -> String {
  let json : Json = {
    "focus": r.focus_node.to_json(),
    "shape": r.source_shape.to_json(),
    "component": @moonshacl.Iri(r.component).to_json(),
    "severity": r.severity.to_json(),
    "value": match r.value {
      Some(v) => v.to_json()
      None => Json::null()
    },
    "path": match r.path {
      Some(p) => p.to_json()
      None => Json::null()
    },
  }
  json.stringify()
}

///|
test "W3C official full Core conformance" {
  let rows : Array[Json] = []
  let mut passed = 0
  let mut rejected = 0
  let mut failed = 0
  let resources = official_resources()
  for (name, text) in official_fixtures() {
    let graph = match
      @turtle.parse(text, base="http://datashapes.org/sh/tests/core/" + name) {
      Ok(g) => g
      Err(errors) => {
        rows.push({
          "name": name,
          "status": "parser-rejected",
          "errors": Json::array(errors.map(Json::string)),
        })
        rejected = rejected + 1
        continue
      }
    }
    let test_node = @moonshacl.Iri(
      "http://datashapes.org/sh/tests/core/" + name.replace(old=".ttl", new=""),
    )
    let action = graph.objects(
        test_node, "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action",
      )[0]
    let graphs : Array[@moonshacl.Graph] = []
    let mut resource_error = false
    for predicate in ["shapesGraph", "dataGraph"] {
      let resource_ref = graph.objects(
          action,
          "http://www.w3.org/ns/shacl-test#" + predicate,
        )[0]
      if resource_ref ==
        @moonshacl.Iri("http://datashapes.org/sh/tests/core/" + name) {
        graphs.push(graph)
      } else {
        match resource_ref {
          @moonshacl.Iri(url) =>
            match resources.get(url) {
              Some(resource) =>
                match @turtle.parse(resource, base=url) {
                  Ok(g) => graphs.push(g)
                  Err(errors) => {
                    rows.push({
                      "name": name,
                      "status": "parser-rejected",
                      "errors": Json::array(errors.map(Json::string)),
                    })
                    rejected = rejected + 1
                    resource_error = true
                  }
                }
              None => {
                failed = failed + 1
                resource_error = true
                rows.push({ "name": name, "status": "missing-resource" })
              }
            }
          _ => {
            failed = failed + 1
            resource_error = true
          }
        }
      }
    }
    if resource_error {
      continue
    }
    let plan = match @moonshacl.compile(graphs[0]) {
      Ok(p) => p
      Err(errors) => {
        rows.push({
          "name": name,
          "status": "profile-rejected",
          "errors": Json::array(errors.map(e => e.to_json())),
        })
        rejected = rejected + 1
        continue
      }
    }
    let report = plan.validate(graphs[1])
    let result_nodes = graph.objects(
      @moonshacl.Iri(
        "http://datashapes.org/sh/tests/core/" +
        name.replace(old=".ttl", new=""),
      ),
      "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#result",
    )
    let result_node = match result_nodes.get(0) {
      Some(n) => n
      None => {
        failed = failed + 1
        rows.push({ "name": name, "status": "missing-manifest-result" })
        continue
      }
    }
    let expected_conforms = graph
      .objects(result_node, @moonshacl.sh + "conforms")
      .contains(@moonshacl.Literal("true", @moonshacl.xsd + "boolean", None))
    let expected = graph
      .objects(result_node, @moonshacl.sh + "result")
      .map(n => signature(graph, n))
    let actual = report.results.map(actual_signature)
    expected.sort()
    actual.sort()
    // Expected messages must be present. Processors may add their own messages.
    let messages_ok = graph
      .objects(result_node, @moonshacl.sh + "result")
      .all(n => {
        let expected_messages = graph.objects(
          n,
          @moonshacl.sh + "resultMessage",
        )
        report.results.any(r => {
          actual_signature(r) == signature(graph, n) &&
          expected_messages.all(m => r.messages.contains(m))
        })
      })
    let success = expected_conforms == report.conforms &&
      expected == actual &&
      messages_ok
    if success {
      passed = passed + 1
    } else {
      failed = failed + 1
    }
    rows.push({
      "name": name,
      "status": if success {
        "passed"
      } else {
        "failed"
      },
      "expectedConforms": expected_conforms,
      "actualConforms": report.conforms,
      "expected": Json::array(expected.map(Json::string)),
      "actual": Json::array(actual.map(Json::string)),
    })
  }
  let output : Json = {
    "passed": passed,
    "rejected": rejected,
    "failed": failed,
    "cases": Json::array(rows),
  }
  println("CONFORMANCE_JSON=" + output.stringify())
  assert_eq(failed, 0)
  assert_eq(passed, 98)
  assert_eq(rejected, 0)
}

///|
test "Official DCAT-AP base shapes compile" {
  let graph = match @turtle.parse(dcat_shapes_text(), scope="shapes-") {
    Ok(g) => g
    Err(errors) => {
      fail(errors.join("\n"))
      return
    }
  }
  match @moonshacl.compile(graph) {
    Ok(_) => ()
    Err(errors) => fail(errors.map(e => e.message).join("\n"))
  }
}
