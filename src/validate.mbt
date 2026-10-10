///|
fn violation(
  shape : Shape,
  focus : Term,
  component : String,
  value : Term?,
  details? : Array[ValidationResult] = [],
  override_path? : Path? = None,
) -> ValidationResult {
  {
    focus_node: focus,
    source_shape: shape.id,
    component: sh + component + "ConstraintComponent",
    severity: shape.severity,
    path: (if override_path is Some(_) { override_path } else { shape.path }).map(
      copy_path,
    ),
    value,
    messages: shape.messages.copy(),
    details,
  }
}

///|
fn kind_matches(value : Term, kind : String) -> Bool {
  match value {
    Iri(_) => ["IRI", "BlankNodeOrIRI", "IRIOrLiteral"].any(k => kind == sh + k)
    Blank(_) =>
      ["BlankNode", "BlankNodeOrIRI", "BlankNodeOrLiteral"].any(k => {
        kind == sh + k
      })
    Literal(_, _, _) =>
      ["Literal", "BlankNodeOrLiteral", "IRIOrLiteral"].any(k => kind == sh + k)
  }
}

///|
fn siblings(plan : Plan, shape : Term, qualified : Term) -> Array[Term] {
  let result = []
  for parent in plan.parents.get_or_default(shape, []) {
    for rule in plan.shapes[parent].rules {
      match rule {
        Property(child) =>
          match plan.shapes[child].qualified_value {
            Some(q) if q != qualified => result.push(q)
            _ => ()
          }
        _ => ()
      }
    }
  }
  unique(result)
}

///|
fn evaluate_shape(
  plan : Plan,
  id : Term,
  focus : Term,
  reader : Reader,
) -> Array[ValidationResult] {
  let shape = plan.shapes[id]
  if shape.deactivated {
    return []
  }
  let values = match shape.path {
    None => [focus]
    Some(path) => evaluate_path(reader, focus, path, false)
  }
  let results = []
  for rule in shape.rules {
    match rule {
      Class(class) =>
        for value in values {
          if !is_instance(reader, value, class) {
            results.push(violation(shape, focus, "Class", Some(value)))
          }
        }
      Datatype(datatype) =>
        for value in values {
          let valid = match value {
            Literal(s, d, language) =>
              d == datatype && valid_lexical(s, d, language)
            _ => false
          }
          if !valid {
            results.push(violation(shape, focus, "Datatype", Some(value)))
          }
        }
      NodeKind(kind) =>
        for value in values {
          if !kind_matches(value, kind) {
            results.push(violation(shape, focus, "NodeKind", Some(value)))
          }
        }
      MinCount(n) =>
        if values.length() < n {
          results.push(violation(shape, focus, "MinCount", None))
        }
      MaxCount(n) =>
        if values.length() > n {
          results.push(violation(shape, focus, "MaxCount", None))
        }
      MinLength(n) | MaxLength(n) =>
        for value in values {
          let length = match value {
            Iri(s) | Literal(s, _, _) => Some(s.iter().count())
            Blank(_) => None
          }
          let is_min = rule is MinLength(_)
          let valid = match length {
            Some(length) => if is_min { length >= n } else { length <= n }
            None => false
          }
          if !valid {
            results.push(
              violation(
                shape,
                focus,
                if is_min {
                  "MinLength"
                } else {
                  "MaxLength"
                },
                Some(value),
              ),
            )
          }
        }
      LanguageIn(ranges) =>
        for value in values {
          let valid = match value {
            Literal(_, _, Some(tag)) =>
              ranges.any(range => {
                range == "*" ||
                tag.to_lower() == range ||
                tag.to_lower().has_prefix(range + "-")
              })
            _ => false
          }
          if !valid {
            results.push(violation(shape, focus, "LanguageIn", Some(value)))
          }
        }
      UniqueLang => {
        let counts : Map[String, Int] = Map([])
        let languages : Array[String] = []
        for value in values {
          match value {
            Literal(_, _, Some(tag)) => {
              let tag = tag.to_lower()
              if !counts.contains(tag) {
                languages.push(tag)
              }
              counts[tag] = counts.get_or_default(tag, 0) + 1
            }
            _ => ()
          }
        }
        for language in languages {
          if counts[language] > 1 {
            results.push(violation(shape, focus, "UniqueLang", None))
          }
        }
      }
      HasValue(required) =>
        if !values.contains(required) {
          results.push(violation(shape, focus, "HasValue", None))
        }
      In(allowed) =>
        for value in values {
          if !allowed.contains(value) {
            results.push(violation(shape, focus, "In", Some(value)))
          }
        }
      Property(child) =>
        for value in values {
          results.append(evaluate_shape(plan, child, value, reader))
        }
      Node(child) =>
        for value in values {
          let details = evaluate_shape(plan, child, value, reader)
          if !details.is_empty() {
            results.push(violation(shape, focus, "Node", Some(value), details~))
          }
        }
      Not(child) =>
        for value in values {
          if evaluate_shape(plan, child, value, reader).is_empty() {
            results.push(violation(shape, focus, "Not", Some(value)))
          }
        }
      And(children) | Or(children) | Xone(children) =>
        for value in values {
          let mut conforming = 0
          let details = []
          for child in children {
            let child_results = evaluate_shape(plan, child, value, reader)
            if child_results.is_empty() {
              conforming = conforming + 1
            } else {
              details.append(child_results)
            }
          }
          let (valid, name) = match rule {
            And(_) => (conforming == children.length(), "And")
            Or(_) => (conforming > 0, "Or")
            _ => (conforming == 1, "Xone")
          }
          if !valid {
            results.push(violation(shape, focus, name, Some(value), details~))
          }
        }
      Equals(p) => {
        let other = reader.objects(focus, p)
        for value in values {
          if !other.contains(value) {
            results.push(violation(shape, focus, "Equals", Some(value)))
          }
        }
        for value in other {
          if !values.contains(value) {
            results.push(violation(shape, focus, "Equals", Some(value)))
          }
        }
      }
      Disjoint(p) => {
        let other = reader.objects(focus, p)
        for value in values {
          if other.contains(value) {
            results.push(violation(shape, focus, "Disjoint", Some(value)))
          }
        }
      }
      Closed(allowed) =>
        for value in values {
          for t in reader.outgoing(value) {
            if !allowed.contains(t.predicate) {
              results.push(
                violation(
                  shape,
                  focus,
                  "Closed",
                  Some(t.object),
                  override_path=Some(Predicate(t.predicate)),
                ),
              )
            }
          }
        }
      Qualified(qualified, minimum, maximum, disjoint) => {
        let other = if disjoint { siblings(plan, id, qualified) } else { [] }
        let mut count = 0
        for value in values {
          let conforms = evaluate_shape(plan, qualified, value, reader).is_empty()
          // Do not short-circuit dependencies: exclusion relies on every sibling.
          let mut excluded = false
          for sibling in other {
            if evaluate_shape(plan, sibling, value, reader).is_empty() {
              excluded = true
            }
          }
          if conforms && !excluded {
            count = count + 1
          }
        }
        match minimum {
          Some(n) =>
            if count < n {
              results.push(violation(shape, focus, "QualifiedMinCount", None))
            }
          None => ()
        }
        match maximum {
          Some(n) =>
            if count > n {
              results.push(violation(shape, focus, "QualifiedMaxCount", None))
            }
          None => ()
        }
      }
    }
  }
  results
}

///|
/// Validation includes all severities in the W3C conforms flag.
pub fn Plan::validate(self : Plan, graph : Graph) -> Report {
  let results = []
  let mut checked = 0
  for id in self.shape_order {
    for focus in target_nodes(self.shapes[id], graph) {
      checked = checked + 1
      results.append(evaluate_shape(self, id, focus, { graph, reads: [], }))
    }
  }
  { conforms: results.is_empty(), results, checked, reused: 0, }
}

///|
/// Explicit focus validation does not depend on target declarations.
pub fn Plan::validate_node(
  self : Plan,
  graph : Graph,
  shape : Term,
  focus : Term,
) -> Result[Report, String] {
  if !self.shapes.contains(shape) {
    return Err("Unknown compiled shape")
  }
  let results = evaluate_shape(self, shape, focus, { graph, reads: [], })
  Ok({ conforms: results.is_empty(), results, checked: 1, reused: 0, })
}
