///|
/// Stable JSON encoding preserves RDF term identity, including ill-typed literals.
pub fn Term::to_json(self : Term) -> Json {
  match self {
    Iri(value) => { "termType": "NamedNode", "value": value }
    Blank(value) => { "termType": "BlankNode", "value": value }
    Literal(value, datatype, language) =>
      {
        "termType": "Literal",
        "value": value,
        "datatype": datatype,
        "language": match language {
          Some(s) => Json::string(s)
          None => Json::null()
        },
      }
  }
}

///|
pub fn Path::to_json(self : Path) -> Json {
  match self {
    Predicate(p) => { "predicate": p }
    Inverse(p) => { "inverse": p.to_json() }
    Sequence(ps) => { "sequence": Json::array(ps.map(p => p.to_json())) }
    Alternative(ps) => { "alternative": Json::array(ps.map(p => p.to_json())) }
    ZeroOrMore(p) => { "zeroOrMore": p.to_json() }
    OneOrMore(p) => { "oneOrMore": p.to_json() }
    ZeroOrOne(p) => { "zeroOrOne": p.to_json() }
  }
}

///|
pub fn ValidationResult::to_json(self : ValidationResult) -> Json {
  {
    "focusNode": self.focus_node.to_json(),
    "sourceShape": self.source_shape.to_json(),
    "sourceConstraintComponent": self.component,
    "resultSeverity": self.severity.to_json(),
    "resultPath": match self.path {
      Some(p) => p.to_json()
      None => Json::null()
    },
    "value": match self.value {
      Some(v) => v.to_json()
      None => Json::null()
    },
    "resultMessage": Json::array(self.messages.map(m => m.to_json())),
    "detail": Json::array(self.details.map(r => r.to_json())),
  }
}

///|
pub fn Report::to_json(self : Report) -> Json {
  {
    "conforms": self.conforms,
    "results": Json::array(self.results.map(r => r.to_json())),
    "work": { "checked": self.checked, "reused": self.reused },
  }
}

///|
pub fn Problem::to_json(self : Problem) -> Json {
  {
    "node": self.node.to_json(),
    "predicate": self.predicate,
    "message": self.message,
  }
}

///|
fn path_triples(
  path : Path,
  next : Array[Int],
  triples : Array[Triple],
) -> Term {
  match path {
    Predicate(p) => Iri(p)
    Inverse(p) | ZeroOrMore(p) | OneOrMore(p) | ZeroOrOne(p) => {
      let n = Blank("path" + next[0].to_string())
      next[0] = next[0] + 1
      let predicate = match path {
        Inverse(_) => "inversePath"
        ZeroOrMore(_) => "zeroOrMorePath"
        OneOrMore(_) => "oneOrMorePath"
        _ => "zeroOrOnePath"
      }
      let object = path_triples(p, next, triples)
      triples.push({ subject: n, predicate: sh + predicate, object, })
      n
    }
    Sequence(ps) | Alternative(ps) => {
      let head = Blank("path" + next[0].to_string())
      next[0] = next[0] + 1
      let items = ps.map(p => path_triples(p, next, triples))
      let mut current = head
      for i, item in items {
        let rest = if i + 1 == items.length() {
          Iri(rdf + "nil")
        } else {
          let node = Blank("path" + next[0].to_string())
          next[0] = next[0] + 1
          node
        }
        triples.push({
          subject: current,
          predicate: rdf + "first",
          object: item,
        })
        triples.push({
          subject: current,
          predicate: rdf + "rest",
          object: rest,
        })
        current = rest
      }
      if path is Alternative(_) {
        let node = Blank("path" + next[0].to_string())
        next[0] = next[0] + 1
        triples.push({
          subject: node,
          predicate: sh + "alternativePath",
          object: head,
        })
        node
      } else {
        head
      }
    }
  }
}

///| Reports are standalone RDF graphs; input blank nodes are relabelled consistently

///|
/// so generated report/path nodes cannot alias caller-supplied blank-node labels.
pub fn Report::to_graph(self : Report) -> Graph {
  let triples = []
  let renamed : Map[Term, Term] = Map([])
  let rename = fn(term : Term) {
    match term {
      Blank(_) =>
        renamed.get_or_init(term, () => {
          Blank("input" + renamed.length().to_string())
        })
      _ => term
    }
  }
  let report = Blank("report")
  triples.push({
    subject: report,
    predicate: rdf + "type",
    object: Iri(sh + "ValidationReport"),
  })
  triples.push({
    subject: report,
    predicate: sh + "conforms",
    object: Literal(self.conforms.to_string(), xsd + "boolean", None),
  })
  let next = [0]
  fn add_result(
    r : ValidationResult,
    parent : Term,
    predicate : String,
  ) -> Unit {
    let node = Blank("result" + next[0].to_string())
    next[0] = next[0] + 1
    triples.push({ subject: parent, predicate, object: node, })
    triples.push({
      subject: node,
      predicate: rdf + "type",
      object: Iri(sh + "ValidationResult"),
    })
    for
      (predicate, object) in [
        ("focusNode", r.focus_node),
        ("sourceShape", r.source_shape),
        ("sourceConstraintComponent", Iri(r.component)),
        ("resultSeverity", r.severity),
      ] {
      triples.push({
        subject: node,
        predicate: sh + predicate,
        object: rename(object),
      })
    }
    match r.path {
      Some(path) =>
        triples.push({
          subject: node,
          predicate: sh + "resultPath",
          object: path_triples(path, next, triples),
        })
      None => ()
    }
    match r.value {
      Some(value) =>
        triples.push({
          subject: node,
          predicate: sh + "value",
          object: rename(value),
        })
      None => ()
    }
    for message in r.messages {
      triples.push({
        subject: node,
        predicate: sh + "resultMessage",
        object: rename(message),
      })
    }
    for detail in r.details {
      add_result(detail, node, sh + "detail")
    }
  }
  for result in self.results {
    add_result(result, report, sh + "result")
  }
  Graph::new(triples)
}

///|
pub fn Graph::to_ntriples(self : Graph) -> String {
  self.triples
  .map(t => {
    t.subject.to_ntriples() +
    " <" +
    t.predicate +
    "> " +
    t.object.to_ntriples() +
    " ."
  })
  .join("\n")
}
