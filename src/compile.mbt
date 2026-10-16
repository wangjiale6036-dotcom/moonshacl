///|
priv enum Target {
  Node(Term)
  Class(Term)
  SubjectsOf(String)
  ObjectsOf(String)
}

///|
priv enum Rule {
  Class(Term)
  Datatype(String)
  NodeKind(String)
  MinCount(BigInt)
  MaxCount(BigInt)
  MinLength(BigInt)
  MaxLength(BigInt)
  Pattern(@xpath_regex.Regex)
  MinExclusive(Term)
  MinInclusive(Term)
  MaxExclusive(Term)
  MaxInclusive(Term)
  LanguageIn(Array[String])
  UniqueLang
  HasValue(Term)
  In(Array[Term])
  Node(Term)
  Property(Term)
  Not(Term)
  And(Array[Term])
  Or(Array[Term])
  Xone(Array[Term])
  Equals(String)
  Disjoint(String)
  LessThan(String)
  LessThanOrEquals(String)
  Closed(Array[String])
  Qualified(Term, BigInt?, BigInt?, Bool)
}

///|
struct Shape {
  id : Term
  path : Path?
  targets : Array[Target]
  rules : Array[Rule]
  deactivated : Bool
  severity : Term
  messages : Array[Term]
  qualified_value : Term?
}

///|
/// Compiled shapes are reusable and isolated from caller-owned arrays.
pub struct Plan {
  shapes : Map[Term, Shape]
  shape_order : Array[Term]
  parents : Map[Term, Array[Term]]
  diagnostics : Array[Problem]
  implicit_timezone : Int?
}

///|
priv struct Compiler {
  graph : Graph
  problems : Array[Problem]
  diagnostics : Array[Problem]
  strict : Bool
  max_depth : Int
}

///|
/// Returns ignored-extension notices without exposing the plan's owned array.
pub fn Plan::diagnostics(self : Plan) -> Array[Problem] {
  self.diagnostics.copy()
}

///|
fn Compiler::extension(
  self : Compiler,
  node : Term,
  predicate : String,
) -> Unit {
  let message = "Extension is not executed by the SHACL 2017 Core processor"
  if self.strict {
    self.error(node, predicate, message)
  } else if !self.diagnostics.any(p => {
      p.node == node && p.predicate == predicate
    }) {
    self.diagnostics.push({ node, predicate, message, })
  }
}

///|
fn Compiler::error(
  self : Compiler,
  node : Term,
  predicate : String,
  message : String,
) -> Unit {
  self.problems.push({ node, predicate, message, })
}

///|
fn Compiler::one(self : Compiler, node : Term, name : String) -> Term? {
  let values = self.graph.objects(node, sh + name)
  if values.length() > 1 {
    self.error(node, sh + name, "Expected at most one parameter value")
  }
  values.get(0)
}

///|
fn Compiler::integer(self : Compiler, node : Term, name : String) -> BigInt? {
  match self.one(node, name) {
    None => None
    Some(Literal(s, d, None)) if d == xsd + "integer" =>
      match parse_integer(s) {
        Some(n) => Some(n)
        None => {
          self.error(node, sh + name, "Expected a well-formed xsd:integer")
          None
        }
      }
    Some(_) => {
      self.error(node, sh + name, "Expected an xsd:integer")
      None
    }
  }
}

///|
fn Compiler::boolean(self : Compiler, node : Term, name : String) -> Bool {
  match self.one(node, name) {
    None => false
    Some(Literal(s, d, None)) if d == xsd + "boolean" &&
      valid_lexical(s, d, None) &&
      (name != "deactivated" || s == "true" || s == "false") => s == "true"
    Some(_) => {
      self.error(node, sh + name, "Expected a well-formed xsd:boolean")
      false
    }
  }
}

///|
fn Compiler::list(
  self : Compiler,
  node : Term,
  head : Term,
  name : String,
) -> Array[Term] {
  let result = []
  let seen : Array[Term] = []
  let mut current = head
  if self.graph.objects(Iri(rdf + "nil"), rdf + "first").length() > 0 ||
    self.graph.objects(Iri(rdf + "nil"), rdf + "rest").length() > 0 {
    self.error(node, sh + name, "rdf:nil must not have rdf:first or rdf:rest")
  }
  while current != Iri(rdf + "nil") {
    if current is Literal(_, _, _) {
      self.error(node, sh + name, "RDF list nodes must be IRIs or blank nodes")
      break
    }
    if seen.contains(current) {
      self.error(node, sh + name, "Cyclic RDF list")
      break
    }
    seen.push(current)
    let first = self.graph.objects(current, rdf + "first")
    let rest = self.graph.objects(current, rdf + "rest")
    if first.length() != 1 || rest.length() != 1 {
      self.error(
        node,
        sh + name,
        "Malformed RDF list: exactly one rdf:first and rdf:rest required",
      )
      break
    }
    result.push(first[0])
    current = rest[0]
  }
  result
}

///|
fn Compiler::path(self : Compiler, node : Term, active : Array[Term]) -> Path? {
  match node {
    Iri(s) => return Some(Predicate(s))
    Literal(_, _, _) => {
      self.error(node, sh + "path", "A path must be an IRI or blank node")
      return None
    }
    Blank(_) => ()
  }
  if active.contains(node) {
    self.error(node, sh + "path", "Cyclic SHACL property path")
    return None
  }
  if active.length() >= self.max_depth {
    self.error(
      node,
      sh + "path",
      "Resource limit: property path nesting exceeds max_depth",
    )
    return None
  }
  let active = active.copy()
  active.push(node)
  let outgoing = self.graph.triples.filter(t => t.subject == node)
  if self.graph.objects(node, rdf + "first").length() > 0 {
    let items = self.list(node, node, "path")
    if items.length() < 2 {
      self.error(
        node,
        sh + "path",
        "Sequence path requires at least two members",
      )
    }
    let paths = []
    for item in items {
      match self.path(item, active) {
        Some(p) => paths.push(p)
        None => ()
      }
    }
    return Some(Sequence(paths))
  }
  if outgoing.length() != 1 {
    self.error(
      node,
      sh + "path",
      "Path operator must have exactly one defining triple",
    )
    return None
  }
  let t = outgoing[0]
  if t.predicate == sh + "alternativePath" {
    let items = self.list(node, t.object, "alternativePath")
    if items.length() < 2 {
      self.error(
        node,
        t.predicate,
        "Alternative path requires at least two members",
      )
    }
    let paths = []
    for item in items {
      match self.path(item, active) {
        Some(p) => paths.push(p)
        None => ()
      }
    }
    return Some(Alternative(paths))
  }
  match self.path(t.object, active) {
    None => None
    Some(p) =>
      if t.predicate == sh + "inversePath" {
        Some(Inverse(p))
      } else if t.predicate == sh + "zeroOrMorePath" {
        Some(ZeroOrMore(p))
      } else if t.predicate == sh + "oneOrMorePath" {
        Some(OneOrMore(p))
      } else if t.predicate == sh + "zeroOrOnePath" {
        Some(ZeroOrOne(p))
      } else {
        self.error(node, t.predicate, "Unsupported path operator")
        None
      }
  }
}

///|
fn rule_references(rule : Rule) -> Array[Term] {
  match rule {
    Node(n) | Property(n) | Not(n) | Qualified(n, _, _, _) => [n]
    And(ns) | Or(ns) | Xone(ns) => ns.copy()
    _ => []
  }
}

///|
fn Compiler::shape(self : Compiler, id : Term) -> Shape {
  let allowed = [
    "targetNode", "targetClass", "targetSubjectsOf", "targetObjectsOf", "path", "class",
    "datatype", "nodeKind", "minCount", "maxCount", "minLength", "maxLength", "languageIn",
    "uniqueLang", "hasValue", "in", "node", "property", "not", "and", "or", "xone",
    "equals", "disjoint", "closed", "ignoredProperties", "qualifiedValueShape", "qualifiedMinCount",
    "qualifiedMaxCount", "qualifiedValueShapesDisjoint", "severity", "message", "deactivated",
    "name", "description", "order", "group", "defaultValue", "pattern", "flags",
    "minExclusive", "minInclusive", "maxExclusive", "maxInclusive", "lessThan", "lessThanOrEquals",
    "entailment", "shapesGraph",
  ]
  for t in self.graph.triples {
    if t.subject == id &&
      t.predicate.has_prefix(sh) &&
      !allowed.contains(t.predicate[sh.length():].to_owned()) {
      self.extension(id, t.predicate)
    }
  }
  match id {
    Literal(_, _, _) =>
      self.error(
        id,
        rdf + "type",
        "Shape identifiers must be IRIs or blank nodes",
      )
    _ => ()
  }
  let type_reader : Reader = { graph: self.graph, reads: [], }
  let path = match self.one(id, "path") {
    None => None
    Some(p) => self.path(p, [])
  }
  if is_instance(type_reader, id, Iri(sh + "NodeShape")) && path is Some(_) {
    self.error(id, sh + "path", "NodeShape cannot have sh:path")
  }
  if is_instance(type_reader, id, Iri(sh + "PropertyShape")) && path is None {
    self.error(id, sh + "path", "PropertyShape requires sh:path")
  }
  let targets : Array[Target] = []
  for t in self.graph.triples {
    if t.subject != id {
      continue
    }
    if t.predicate == sh + "targetNode" {
      if t.object is Blank(_) {
        self.error(id, t.predicate, "targetNode must be an IRI or literal")
      } else {
        targets.push(Target::Node(t.object))
      }
    }
    if t.predicate == sh + "targetClass" {
      match t.object {
        Iri(_) => targets.push(Target::Class(t.object))
        _ => self.error(id, t.predicate, "targetClass must be an IRI")
      }
    }
    if t.predicate == sh + "targetSubjectsOf" ||
      t.predicate == sh + "targetObjectsOf" {
      match t.object {
        Iri(p) =>
          if t.predicate == sh + "targetSubjectsOf" {
            targets.push(SubjectsOf(p))
          } else {
            targets.push(ObjectsOf(p))
          }
        _ => self.error(id, t.predicate, "Target predicate must be an IRI")
      }
    }
  }
  if is_instance(type_reader, id, Iri(rdfs + "Class")) &&
    (
      is_instance(type_reader, id, Iri(sh + "NodeShape")) ||
      is_instance(type_reader, id, Iri(sh + "PropertyShape"))
    ) {
    match id {
      Iri(_) => targets.push(Target::Class(id))
      _ =>
        self.error(
          id,
          rdf + "type",
          "An implicit class target shape must be an IRI",
        )
    }
  }
  let rules : Array[Rule] = []
  for t in self.graph.triples {
    if t.subject != id {
      continue
    }
    let p = t.predicate
    if p == sh + "class" {
      match t.object {
        Iri(_) => rules.push(Rule::Class(t.object))
        _ => self.error(id, p, "Class must be an IRI")
      }
    }
    if p == sh + "datatype" {
      match t.object {
        Iri(d) => rules.push(Datatype(d))
        _ => self.error(id, p, "Datatype must be an IRI")
      }
    }
    if p == sh + "nodeKind" {
      match t.object {
        Iri(k) if [
            "IRI", "BlankNode", "Literal", "BlankNodeOrIRI", "BlankNodeOrLiteral",
            "IRIOrLiteral",
          ].any(n => k == sh + n) => rules.push(NodeKind(k))
        _ => self.error(id, p, "Unknown nodeKind")
      }
    }
    if p == sh + "property" || p == sh + "node" || p == sh + "not" {
      if p == sh + "property" {
        rules.push(Property(t.object))
      }
      if p == sh + "node" {
        rules.push(Node(t.object))
      }
      if p == sh + "not" {
        rules.push(Not(t.object))
      }
    }
    if p == sh + "and" || p == sh + "or" || p == sh + "xone" {
      let ns = self.list(id, t.object, p[sh.length():].to_owned())
      if p == sh + "and" {
        rules.push(And(ns))
      }
      if p == sh + "or" {
        rules.push(Or(ns))
      }
      if p == sh + "xone" {
        rules.push(Xone(ns))
      }
    }
    if p == sh + "hasValue" {
      rules.push(HasValue(t.object))
    }
    if ["equals", "disjoint", "lessThan", "lessThanOrEquals"].any(n => {
        p == sh + n
      }) {
      match t.object {
        Iri(value) =>
          if p == sh + "equals" {
            rules.push(Equals(value))
          } else if p == sh + "disjoint" {
            rules.push(Disjoint(value))
          } else if p == sh + "lessThan" {
            rules.push(LessThan(value))
          } else {
            rules.push(LessThanOrEquals(value))
          }
        _ => self.error(id, p, "Comparison predicate must be an IRI")
      }
    }
  }
  for
    name in [
      "datatype", "nodeKind", "minCount", "maxCount", "minLength", "maxLength", "languageIn",
      "uniqueLang", "in", "closed", "ignoredProperties", "qualifiedValueShape", "qualifiedMinCount",
      "qualifiedMaxCount", "qualifiedValueShapesDisjoint", "pattern", "flags", "minExclusive",
      "minInclusive", "maxExclusive", "maxInclusive",
    ] {
    ignore(self.one(id, name))
  }
  let pattern = match self.one(id, "pattern") {
    Some(Literal(s, d, None)) if d == xsd + "string" => Some(s)
    Some(_) => {
      self.error(id, sh + "pattern", "Pattern must be an xsd:string")
      None
    }
    None => None
  }
  let flags = match self.one(id, "flags") {
    Some(Literal(s, d, None)) if d == xsd + "string" => s
    Some(_) => {
      self.error(id, sh + "flags", "Flags must be an xsd:string")
      ""
    }
    None => ""
  }
  match pattern {
    Some(pattern) =>
      match @xpath_regex.compile(pattern, flags) {
        Ok(regex) => rules.push(Pattern(regex))
        Err(message) => self.error(id, sh + "pattern", message)
      }
    None => ()
  }
  for name in ["minExclusive", "minInclusive", "maxExclusive", "maxInclusive"] {
    match self.one(id, name) {
      Some(value) if value is Literal(_, _, _) =>
        match name {
          "minExclusive" => rules.push(MinExclusive(value))
          "minInclusive" => rules.push(MinInclusive(value))
          "maxExclusive" => rules.push(MaxExclusive(value))
          _ => rules.push(MaxInclusive(value))
        }
      Some(_) => self.error(id, sh + name, "Range boundary must be a literal")
      None => ()
    }
  }
  match self.integer(id, "minCount") {
    Some(n) => rules.push(MinCount(n))
    None => ()
  }
  match self.integer(id, "maxCount") {
    Some(n) => rules.push(MaxCount(n))
    None => ()
  }
  match self.integer(id, "minLength") {
    Some(n) => rules.push(MinLength(n))
    None => ()
  }
  match self.integer(id, "maxLength") {
    Some(n) => rules.push(MaxLength(n))
    None => ()
  }
  if path is None &&
    (
      self.one(id, "minCount") is Some(_) ||
      self.one(id, "maxCount") is Some(_) ||
      self.one(id, "uniqueLang") is Some(_) ||
      self.one(id, "qualifiedValueShape") is Some(_) ||
      !self.graph.objects(id, sh + "lessThan").is_empty() ||
      !self.graph.objects(id, sh + "lessThanOrEquals").is_empty()
    ) {
    self.error(id, sh + "path", "Property-only constraint used on a node shape")
  }
  match self.one(id, "in") {
    Some(head) => rules.push(In(self.list(id, head, "in")))
    None => ()
  }
  match self.one(id, "languageIn") {
    Some(head) => {
      let languages = []
      for item in self.list(id, head, "languageIn") {
        match item {
          Literal(s, d, None) if d == xsd + "string" =>
            languages.push(s.to_lower())
          _ =>
            self.error(
              id,
              sh + "languageIn",
              "Language range must be an xsd:string",
            )
        }
      }
      rules.push(LanguageIn(languages))
    }
    None => ()
  }
  if self.boolean(id, "uniqueLang") {
    rules.push(UniqueLang)
  }
  let allowed_properties = []
  match self.one(id, "ignoredProperties") {
    Some(head) =>
      for item in self.list(id, head, "ignoredProperties") {
        match item {
          Iri(p) => allowed_properties.push(p)
          _ =>
            self.error(
              id,
              sh + "ignoredProperties",
              "Ignored property must be an IRI",
            )
        }
      }
    None => ()
  }
  if self.boolean(id, "closed") {
    for property in self.graph.objects(id, sh + "property") {
      match self.one(property, "path") {
        Some(Iri(p)) => allowed_properties.push(p)
        _ => ()
      }
    }
    rules.push(Closed(allowed_properties))
  }
  let minimum = self.integer(id, "qualifiedMinCount")
  let maximum = self.integer(id, "qualifiedMaxCount")
  let disjoint = self.boolean(id, "qualifiedValueShapesDisjoint")
  let qualified_value = self.one(id, "qualifiedValueShape")
  match qualified_value {
    Some(n) =>
      if minimum is Some(_) || maximum is Some(_) {
        rules.push(Qualified(n, minimum, maximum, disjoint))
      }
    // A SHACL constraint component is instantiated only when all mandatory
    // parameters are present. Standalone qualified counts are valid annotations.
    None => ()
  }
  let severity = match self.one(id, "severity") {
    Some(Iri(s)) => Iri(s)
    Some(_) => {
      self.error(id, sh + "severity", "Severity must be an IRI")
      Iri(sh + "Violation")
    }
    None => Iri(sh + "Violation")
  }
  let messages = self.graph.objects(id, sh + "message")
  for message in messages {
    match message {
      Literal(_, d, _) if d == xsd + "string" || d == rdf + "langString" => ()
      _ => self.error(id, sh + "message", "Message must be a string literal")
    }
  }
  {
    id,
    path,
    targets,
    rules,
    severity,
    messages,
    qualified_value,
    deactivated: self.boolean(id, "deactivated"),
  }
}

///|
fn check_cycle(
  id : Term,
  shapes : Map[Term, Shape],
  parents : Map[Term, Array[Term]],
  done : Map[Term, Bool],
  c : Compiler,
) -> Unit {
  if done.contains(id) {
    return
  }
  let active : Map[Term, Bool] = Map([])
  let stack : Array[(Term, Bool)] = [(id, false)]
  let sibling_plan : Plan = {
    shapes,
    parents,
    shape_order: [],
    diagnostics: [],
    implicit_timezone: None,
  }
  while !stack.is_empty() {
    let (current, leaving) = stack.pop().unwrap()
    if leaving {
      active.remove(current)
      done[current] = true
      continue
    }
    if done.contains(current) {
      continue
    }
    if active.contains(current) {
      c.error(
        current,
        sh + "node",
        "Validation failure: recursive shapes are not supported",
      )
      return
    }
    active[current] = true
    stack.push((current, true))
    let s = shapes[current]
    let references : Array[Term] = []
    match s.qualified_value {
      Some(q) => references.push(q)
      None => ()
    }
    for rule in s.rules {
      references.append(rule_references(rule))
      match rule {
        Qualified(q, _, _, true) =>
          references.append(siblings(sibling_plan, current, q))
        _ => ()
      }
    }
    for reference in unique(references).rev() {
      stack.push((reference, false))
    }
  }
}

///|
/// Compile SHACL 2017 Core. Strict audit rejects ignored extension constructs.
/// Graph imports must already be resolved and their link triples removed.
/// max_depth is a configurable resource budget, not a SHACL syntax limit.
pub fn compile(
  graph : Graph,
  strict? : Bool = false,
  max_depth? : Int = 1024,
  implicit_timezone? : Int? = None,
) -> Result[Plan, Array[Problem]] {
  let c : Compiler = {
    graph,
    problems: [],
    diagnostics: [],
    strict,
    max_depth,
  }
  if max_depth <= 0 {
    return Err([
      {
        node: Iri(sh + "Shape"),
        predicate: sh + "path",
        message: "max_depth must be positive",
      },
    ])
  }
  if implicit_timezone is Some(minutes) && (minutes < -840 || minutes > 840) {
    return Err([
      {
        node: Iri(sh + "Shape"),
        predicate: sh + "datatype",
        message: "XPath implicit timezone must be between -840 and 840 minutes",
      },
    ])
  }
  let type_reader : Reader = { graph, reads: [], }
  let ids : Array[Term] = []
  let shape_parameters = supported_parameters()
  shape_parameters.append([
    "targetNode", "targetClass", "targetSubjectsOf", "targetObjectsOf",
  ])
  for t in graph.triples {
    if (
        t.predicate == rdf + "type" &&
        (
          is_instance(type_reader, t.subject, Iri(sh + "NodeShape")) ||
          is_instance(type_reader, t.subject, Iri(sh + "PropertyShape"))
        )
      ) ||
      shape_parameters.any(p => t.predicate == sh + p) {
      if !ids.contains(t.subject) {
        ids.push(t.subject)
      }
    }
    if t.predicate == rdf + "type" &&
      is_instance(type_reader, t.subject, Iri(sh + "ConstraintComponent")) {
      c.extension(t.subject, t.predicate)
    }
    if ["sparql", "js", "rule", "target"].any(p => t.predicate == sh + p) {
      c.extension(t.subject, t.predicate)
    }
    if t.predicate == sh + "entailment" {
      c.error(
        t.subject,
        t.predicate,
        "Validation failure: unsupported entailment regime",
      )
    }
    if t.predicate == "http://www.w3.org/2002/07/owl#imports" ||
      t.predicate == sh + "shapesGraph" {
      c.error(
        t.subject,
        t.predicate,
        "Validation failure: unresolved graph reference; use an explicit resource resolver",
      )
    }
  }
  let shapes : Map[Term, Shape] = Map([])
  let parents : Map[Term, Array[Term]] = Map([])
  let mut i = 0
  while i < ids.length() {
    let id = ids[i]
    let shape = c.shape(id)
    // Sibling exclusion uses qualifiedValueShape even without a count component.
    match shape.qualified_value {
      Some(reference) => if !ids.contains(reference) { ids.push(reference) }
      None => ()
    }
    for rule in shape.rules {
      match rule {
        Property(child) => parents.get_or_init(child, () => []).push(id)
        _ => ()
      }
      for reference in rule_references(rule) {
        if !ids.contains(reference) {
          ids.push(reference)
        }
      }
    }
    shapes[id] = shape
    i = i + 1
  }
  for id in ids {
    let shape = shapes[id]
    for rule in shape.rules {
      match rule {
        Property(child) =>
          if shapes[child].path is None {
            c.error(
              child,
              sh + "path",
              "Referenced property shape requires a path",
            )
          }
        Node(child) =>
          if shapes[child].path is Some(_) {
            c.error(
              child,
              sh + "node",
              "sh:node requires a node shape, not a property shape",
            )
          }
        _ => ()
      }
    }
  }
  let done : Map[Term, Bool] = Map([])
  for id in ids {
    check_cycle(id, shapes, parents, done, c)
  }
  if c.problems.is_empty() {
    Ok({
      shapes,
      shape_order: ids,
      parents,
      diagnostics: c.diagnostics,
      implicit_timezone,
    })
  } else {
    Err(c.problems)
  }
}

///|
/// Core constraint parameters, including auxiliary component parameters.
pub fn supported_parameters() -> Array[String] {
  [
    "class", "datatype", "nodeKind", "minCount", "maxCount", "minLength", "maxLength",
    "languageIn", "uniqueLang", "hasValue", "in", "node", "property", "not", "and",
    "or", "xone", "equals", "disjoint", "closed", "qualifiedValueShape", "qualifiedMinCount",
    "qualifiedMaxCount", "qualifiedValueShapesDisjoint", "pattern", "flags", "minExclusive",
    "minInclusive", "maxExclusive", "maxInclusive", "lessThan", "lessThanOrEquals",
    "ignoredProperties",
  ]
}
