///|
test "Every Core component has a positive and negative end to end witness" {
  let prefix = "@prefix ex: <urn:> . @prefix sh: <http://www.w3.org/ns/shacl#> . @prefix xsd: <http://www.w3.org/2001/XMLSchema#> . "
  // Component, constraint, conforming data, non-conforming data, result component.
  // PropertyConstraintComponent forwards the child result instead of wrapping it.
  let rows = [
    (
      "Class", "sh:class ex:C", "ex:item ex:p ex:v . ex:v a ex:C .", "ex:item ex:p ex:v . ex:v a ex:D .",
      "Class",
    ),
    (
      "Datatype", "sh:datatype xsd:string", "ex:item ex:p \"x\" .", "ex:item ex:p 1 .",
      "Datatype",
    ),
    (
      "NodeKind", "sh:nodeKind sh:IRI", "ex:item ex:p ex:v .", "ex:item ex:p \"x\" .",
      "NodeKind",
    ),
    ("MinCount", "sh:minCount 1", "ex:item ex:p 1 .", "", "MinCount"),
    (
      "MaxCount", "sh:maxCount 1", "ex:item ex:p 1 .", "ex:item ex:p 1, 2 .", "MaxCount",
    ),
    (
      "MinExclusive", "sh:minExclusive 0", "ex:item ex:p 1 .", "ex:item ex:p 0 .",
      "MinExclusive",
    ),
    (
      "MinInclusive", "sh:minInclusive 0", "ex:item ex:p 0 .", "ex:item ex:p -1 .",
      "MinInclusive",
    ),
    (
      "MaxExclusive", "sh:maxExclusive 1", "ex:item ex:p 0 .", "ex:item ex:p 1 .",
      "MaxExclusive",
    ),
    (
      "MaxInclusive", "sh:maxInclusive 1", "ex:item ex:p 1 .", "ex:item ex:p 2 .",
      "MaxInclusive",
    ),
    (
      "MinLength", "sh:minLength 2", "ex:item ex:p \"ab\" .", "ex:item ex:p \"a\" .",
      "MinLength",
    ),
    (
      "MaxLength", "sh:maxLength 2", "ex:item ex:p \"ab\" .", "ex:item ex:p \"abc\" .",
      "MaxLength",
    ),
    (
      "Pattern", "sh:pattern \"^AB$\"; sh:flags \"i\"", "ex:item ex:p \"ab\" .",
      "ex:item ex:p \"ab3\" .", "Pattern",
    ),
    (
      "LanguageIn", "sh:languageIn (\"en\")", "ex:item ex:p \"x\"@en-US .", "ex:item ex:p \"x\"@fr .",
      "LanguageIn",
    ),
    (
      "UniqueLang", "sh:uniqueLang true", "ex:item ex:p \"x\"@en, \"y\"@fr .", "ex:item ex:p \"x\"@en, \"y\"@EN .",
      "UniqueLang",
    ),
    (
      "Equals", "sh:equals ex:q", "ex:item ex:p 1; ex:q 1 .", "ex:item ex:p 1; ex:q 2 .",
      "Equals",
    ),
    (
      "Disjoint", "sh:disjoint ex:q", "ex:item ex:p 1; ex:q 2 .", "ex:item ex:p 1; ex:q 1 .",
      "Disjoint",
    ),
    (
      "LessThan", "sh:lessThan ex:q", "ex:item ex:p 1; ex:q 2 .", "ex:item ex:p 1; ex:q 1 .",
      "LessThan",
    ),
    (
      "LessThanOrEquals", "sh:lessThanOrEquals ex:q", "ex:item ex:p 1; ex:q 1 .",
      "ex:item ex:p 2; ex:q 1 .", "LessThanOrEquals",
    ),
    (
      "Not", "sh:not [sh:datatype xsd:integer]", "ex:item ex:p \"x\" .", "ex:item ex:p 1 .",
      "Not",
    ),
    (
      "And", "sh:and ([sh:nodeKind sh:Literal] [sh:minLength 2])", "ex:item ex:p \"ab\" .",
      "ex:item ex:p \"a\" .", "And",
    ),
    (
      "Or", "sh:or ([sh:datatype xsd:string] [sh:datatype xsd:integer])", "ex:item ex:p \"x\" .",
      "ex:item ex:p true .", "Or",
    ),
    (
      "Xone", "sh:xone ([sh:nodeKind sh:Literal] [sh:datatype xsd:string])", "ex:item ex:p 1 .",
      "ex:item ex:p \"x\" .", "Xone",
    ),
    (
      "Node", "sh:node [sh:nodeKind sh:IRI]", "ex:item ex:p ex:v .", "ex:item ex:p \"x\" .",
      "Node",
    ),
    (
      "Property", "sh:property [sh:path ex:q; sh:minCount 1]", "ex:item ex:p ex:v . ex:v ex:q 1 .",
      "ex:item ex:p ex:v .", "MinCount",
    ),
    (
      "QualifiedMinCount", "sh:qualifiedValueShape [sh:datatype xsd:integer]; sh:qualifiedMinCount 2",
      "ex:item ex:p 1, 2 .", "ex:item ex:p 1, \"x\" .", "QualifiedMinCount",
    ),
    (
      "QualifiedMaxCount", "sh:qualifiedValueShape [sh:datatype xsd:integer]; sh:qualifiedMaxCount 1",
      "ex:item ex:p 1, \"x\" .", "ex:item ex:p 1, 2 .", "QualifiedMaxCount",
    ),
    (
      "Closed", "sh:closed true; sh:property [sh:path ex:q]", "ex:item ex:p ex:v . ex:v ex:q 1 .",
      "ex:item ex:p ex:v . ex:v ex:r 1 .", "Closed",
    ),
    (
      "HasValue", "sh:hasValue 1", "ex:item ex:p 1 .", "ex:item ex:p 2 .", "HasValue",
    ),
    ("In", "sh:in (1 2)", "ex:item ex:p 1 .", "ex:item ex:p 3 .", "In"),
  ]
  assert_eq(rows.length(), 29)
  for (name, constraint, good, bad, component) in rows {
    let shapes = parse(
        prefix +
        "ex:S sh:targetNode ex:item; sh:path ex:p; " +
        constraint +
        " .",
        scope="shapes-",
      )
      |> Result::unwrap
    let plan = @moonshacl.compile(shapes) |> Result::unwrap
    let positive = plan.validate(
      parse(prefix + good, scope="data-") |> Result::unwrap,
    )
    assert_true(positive.conforms, msg=name + " positive witness")
    let negative = plan.validate(
      parse(prefix + bad, scope="data-") |> Result::unwrap,
    )
    assert_false(negative.conforms, msg=name + " negative witness")
    assert_eq(negative.results.length(), if name == "Equals" { 2 } else { 1 })
    assert_true(
      negative.results.all(r => {
        r.component == @moonshacl.sh + component + "ConstraintComponent"
      }),
      msg=name + " result component",
    )
  }
}
