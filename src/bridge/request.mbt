///|
/// JSON is a transport boundary. All graph/shape/transaction logic runs in MoonBit.
pub fn request(input : String) -> String {
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
  let plan = match @moonshacl.compile(shapes) {
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
      "parameters": Json::array(
        @moonshacl.supported_parameters().map(Json::string),
      ),
    }
    return result.stringify()
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
  if operation == "validate" {
    let report = plan.validate(data)
    let result : Json = {
      "status": "validated",
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
