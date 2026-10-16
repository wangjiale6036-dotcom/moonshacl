///|
/// JSON is a transport boundary. All graph/shape/transaction logic runs in MoonBit.
pub fn request(input : String) -> String {
  request_checked(input) catch {
    @moonshacl.ValidationFailure(message) =>
      error("validation-failure", message)
  }
}

///|
fn request_checked(input : String) -> String raise @moonshacl.ValidationFailure {
  let json = @json.parse(input) catch {
    _ => return error("request-error", "Invalid JSON request")
  }
  let fields = match json {
    Object(m) => m
    _ => return error("request-error", "Request must be a JSON object")
  }
  for name in ["operation", "shapesBase", "dataBase"] {
    if fields.get(name) is Some(value) && !(value is String(_)) {
      return error("request-error", name + " must be a string")
    }
  }
  if fields.get("strict") is Some(value) && !(value is True || value is False) {
    return error("request-error", "strict must be a boolean")
  }
  let get = fn(name : String, fallback : String) -> String {
    match json {
      Object(m) =>
        match m.get(name) {
          Some(String(s)) => s
          _ => fallback
        }
      _ => fallback
    }
  }
  let operation = get("operation", "validate")
  if !["audit", "validate", "update"].contains(operation) {
    return error("request-error", "Unknown operation")
  }
  let required = if operation == "audit" {
    ["shapes"]
  } else if operation == "validate" {
    ["shapes", "data"]
  } else {
    ["shapes", "data", "additions", "removals"]
  }
  for name in required {
    if !(fields.get(name) is Some(String(_))) {
      return error("request-error", "Required string field: " + name)
    }
  }
  let shapes = match
    @turtle.parse(
      get("shapes", ""),
      base=get("shapesBase", "https://moonshacl.invalid/shapes/"),
      scope="shapes-",
    ) {
    Ok(g) => g
    Err(e) => return error("parse-error", e.join("\n"))
  }
  let data = match
    @turtle.parse(
      get("data", ""),
      base=get("dataBase", "https://moonshacl.invalid/data/"),
      scope="data-",
    ) {
    Ok(g) => g
    Err(e) => return error("parse-error", e.join("\n"))
  }
  let resources : Map[String, @moonshacl.Graph] = Map([])
  match fields.get("resources") {
    None => ()
    Some(Object(items)) => {
      let mut index = 0
      for iri, value in items {
        let text = match value {
          String(text) => text
          _ =>
            return error(
              "request-error", "resources must map IRIs to Turtle strings",
            )
        }
        if iri == get("shapesBase", "https://moonshacl.invalid/shapes/") {
          if text != get("shapes", "") {
            return error(
              "resource-error",
              "Resource map conflicts with the already loaded root shapes document: " +
              iri,
            )
          }
          continue
        }
        match
          @turtle.parse(
            text,
            base=iri,
            scope="resource-" + index.to_string() + "-",
          ) {
          Ok(graph) => resources[iri] = graph
          Err(e) => return error("parse-error", iri + ": " + e.join("\n"))
        }
        index = index + 1
      }
    }
    Some(_) => return error("request-error", "resources must be an object")
  }
  let shapes = match
    @moonshacl.load_shapes(
      shapes,
      data,
      resources,
      root_iri=Some(get("shapesBase", "https://moonshacl.invalid/shapes/")),
    ) {
    Ok(graph) => graph
    Err(message) => return error("resource-error", message)
  }
  let strict = fields.get("strict") is Some(True)
  let implicit_timezone = match fields.get("implicitTimezoneMinutes") {
    None => None
    Some(Number(n, ..)) if n >= -840 && n <= 840 && n == n.to_int().to_double() =>
      Some(n.to_int())
    Some(_) =>
      return error(
        "request-error", "implicitTimezoneMinutes must be an integer between -840 and 840",
      )
  }
  let plan = match @moonshacl.compile(shapes, strict~, implicit_timezone~) {
    Ok(p) => p
    Err(e) => {
      let response : Json = {
        "status": "unsupported-or-invalid-shapes",
        "problems": Json::array(e.map(p => p.to_json())),
      }
      return response.stringify()
    }
  }
  if operation == "audit" {
    let result : Json = {
      "status": "supported",
      "shapeTriples": shapes.size(),
      "shapesRdf": shapes.to_ntriples(),
      "dataRdf": data.to_ntriples(),
      "diagnostics": Json::array(plan.diagnostics().map(p => p.to_json())),
      "parameters": Json::array(
        @moonshacl.supported_parameters().map(Json::string),
      ),
    }
    return result.stringify()
  }
  if operation == "validate" {
    let report = plan.validate(data)
    let result : Json = {
      "status": "validated",
      "diagnostics": Json::array(plan.diagnostics().map(p => p.to_json())),
      "report": report.to_json(),
      "reportRdf": report.to_graph().to_ntriples(),
    }
    return result.stringify()
  }
  // Identity cannot be inferred across separately parsed blank-node documents.
  // Text deltas use stable IRIs; the Graph API accepts exact blank-node identities.
  let additions = match
    @turtle.parse(
      get("additions", ""),
      base=get("dataBase", "https://moonshacl.invalid/data/"),
      scope="data-",
    ) {
    Ok(g) => g
    Err(e) => return error("parse-error", e.join("\n"))
  }
  let removals = match
    @turtle.parse(
      get("removals", ""),
      base=get("dataBase", "https://moonshacl.invalid/data/"),
      scope="data-",
    ) {
    Ok(g) => g
    Err(e) => return error("parse-error", e.join("\n"))
  }
  // Public Graph API accepts exact blank-node identities. Text delta convenience
  // deliberately supports only IRIs/literals to avoid accidental blank-node aliasing.
  if additions
    .triples()
    .any(t => {
      t.subject is @moonshacl.Blank(_) || t.object is @moonshacl.Blank(_)
    }) ||
    removals
    .triples()
    .any(t => {
      t.subject is @moonshacl.Blank(_) || t.object is @moonshacl.Blank(_)
    }) {
    return error(
      "request-error", "Text deltas support IRI subjects and IRI/literal objects; use the Graph API for blank-node updates",
    )
  }
  let session = @moonshacl.Session::new(plan, data)
  let before = session.report()
  let update = session.apply(additions.triples(), removals.triples())
  let response : Json = {
    "status": "updated",
    "diagnostics": Json::array(plan.diagnostics().map(p => p.to_json())),
    "committed": update.committed,
    "before": before.to_json(),
    "report": update.report.to_json(),
    "graphRdf": session.graph().to_ntriples(),
    "graphTriples": session.graph().size(),
    "reportRdf": update.report.to_graph().to_ntriples(),
  }
  response.stringify()
}

///|
fn error(status : String, message : String) -> String {
  let json : Json = { "status": status, "message": message }
  json.stringify()
}
