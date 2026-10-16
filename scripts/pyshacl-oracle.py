"""Independent SHACL comparison, including input-linked blank-node identity.

The projected graph contains both unchanged input graphs and one fresh node for
each top-level result. Thus isomorphism preserves result multiplicity and checks
which anonymous source shape/focus/value a report refers to. Result paths are
copied structurally because SHACL permits an equivalent newly allocated path.
Optional engine-generated messages/details are excluded, never required fields.
"""

from __future__ import annotations

import importlib.metadata
import json
import logging
import sys

import rdflib

# RDF term identity includes the original lexical spelling, even for valid
# numerics and ill-typed literals. Disable RDFLib's default normalization.
rdflib.NORMALIZE_LITERALS = False
logging.getLogger("rdflib.term").setLevel(logging.ERROR)

from pyshacl import validate
from rdflib import BNode, Graph, Literal, Namespace, RDF, URIRef
from rdflib.compare import graph_diff, isomorphic

SH = Namespace("http://www.w3.org/ns/shacl#")
XSD = Namespace("http://www.w3.org/2001/XMLSchema#")
TEST = Namespace("urn:moonshacl:independent-oracle:")


class PreserveLabels(dict):
    """N-Triples has already scoped labels; keep links to JSON report terms."""

    def get(self, key, default=None):
        return BNode(key)


def rdf11_graph(graph):
    """RDF 1.1 simple strings and case-insensitive language tags have one term."""
    result = Graph()
    def normalize(term):
        if not isinstance(term, Literal):
            return term
        if term.language:
            return Literal(str(term), lang=term.language.lower(), normalize=False)
        return Literal(str(term), datatype=term.datatype or XSD.string, normalize=False)
    for subject, predicate, obj in graph:
        result.add((subject, predicate, normalize(obj)))
    return result


def nt_graph(text):
    rdflib.NORMALIZE_LITERALS = False
    return rdf11_graph(Graph().parse(data=text, format="nt", bnode_context=PreserveLabels()))


def turtle_graph(text, base):
    rdflib.NORMALIZE_LITERALS = False
    return rdf11_graph(Graph().parse(data=text, format="turtle", publicID=base))


def from_json(term):
    if term is None:
        return None
    if term["termType"] == "NamedNode":
        return URIRef(term["value"])
    if term["termType"] == "BlankNode":
        return BNode(term["value"])
    if term["termType"] == "Literal":
        language = term.get("language")
        datatype = term.get("datatype")
        if isinstance(datatype, dict):
            datatype = datatype["value"]
        return Literal(term["value"], lang=language.lower() if language else None,
                       datatype=None if language else URIRef(datatype), normalize=False)
    raise AssertionError(f"Unknown term kind: {term}")


def one(graph, node, predicate, required=False):
    values = list(graph.objects(node, predicate))
    if len(values) > 1 or (required and len(values) != 1):
        raise AssertionError(f"Expected {'one' if required else 'at most one'} {predicate} at {node}")
    return values[0] if values else None


def read_path(graph, node, active=frozenset()):
    if node is None:
        return None
    if isinstance(node, URIRef):
        return {"predicate": str(node)}
    if not isinstance(node, BNode) or node in active:
        raise AssertionError("Invalid or cyclic result path")
    active = active | {node}
    # A sequence list may carry additional annotations. In contrast an operator
    # path must be the subject of exactly one triple (SHACL 2017 section 2.3.1).
    # In particular path-strange-001/002 remain sequences despite inversePath.
    sequence = one(graph, node, RDF.first) is not None
    alternative = None
    if not sequence:
        if len(list(graph.predicate_objects(node))) != 1:
            raise AssertionError("An operator result path must have exactly one triple")
        for predicate, key in ((SH.inversePath, "inverse"), (SH.zeroOrMorePath, "zeroOrMore"),
                               (SH.oneOrMorePath, "oneOrMore"), (SH.zeroOrOnePath, "zeroOrOne")):
            value = one(graph, node, predicate)
            if value is not None:
                return {key: read_path(graph, value, active)}
        alternative = one(graph, node, SH.alternativePath)
    current = alternative if alternative is not None else node
    seen, children = set(), []
    while current != RDF.nil:
        if current in seen:
            raise AssertionError("Cyclic result path list")
        seen.add(current)
        children.append(read_path(graph, one(graph, current, RDF.first, True), active))
        current = one(graph, current, RDF.rest, True)
    return {"alternative" if alternative is not None else "sequence": children}


def write_path(graph, path):
    if path is None:
        return None
    if "predicate" in path:
        return URIRef(path["predicate"])
    node = BNode()
    for key, predicate in (("inverse", SH.inversePath), ("zeroOrMore", SH.zeroOrMorePath),
                           ("oneOrMore", SH.oneOrMorePath), ("zeroOrOne", SH.zeroOrOnePath)):
        if key in path:
            graph.add((node, predicate, write_path(graph, path[key])))
            return node
    children = path.get("sequence", path.get("alternative"))
    if children is None or len(children) < 2:
        raise AssertionError("Malformed structural path")
    head = BNode() if "alternative" in path else node
    current = head
    for index, child in enumerate(children):
        tail = RDF.nil if index + 1 == len(children) else BNode()
        graph.add((current, RDF.first, write_path(graph, child)))
        graph.add((current, RDF.rest, tail))
        current = tail
    if "alternative" in path:
        graph.add((node, SH.alternativePath, head))
    return node


def json_results(report):
    return [{
        "focusNode": from_json(r["focusNode"]),
        "sourceShape": from_json(r["sourceShape"]),
        "sourceConstraintComponent": URIRef(r["sourceConstraintComponent"]),
        "resultSeverity": from_json(r["resultSeverity"]),
        "value": from_json(r.get("value")),
        "resultPath": r.get("resultPath"),
    } for r in report["results"]]


def report_root(graph, explicit=None):
    if explicit is not None:
        return from_json(explicit)
    roots = list(graph.subjects(RDF.type, SH.ValidationReport))
    if len(roots) != 1:
        raise AssertionError(f"Expected one validation report, got {len(roots)}")
    return roots[0]


def rdf_results(graph, root, term_remap=None):
    def remap(term):
        return term_remap.get(term, term) if term_remap else term

    results = []
    for node in graph.objects(root, SH.result):
        if (node, RDF.type, SH.ValidationResult) not in graph:
            raise AssertionError("Missing sh:ValidationResult type")
        result = {key: remap(one(graph, node, SH[key], True)) for key in (
            "focusNode", "sourceShape", "sourceConstraintComponent", "resultSeverity")}
        result["value"] = remap(one(graph, node, SH.value))
        result["resultPath"] = read_path(graph, one(graph, node, SH.resultPath))
        results.append(result)
    return results


def conforms_from_rdf(graph, root):
    value = one(graph, root, SH.conforms, True)
    if value.datatype != XSD.boolean or str(value) not in ("true", "false", "1", "0"):
        raise AssertionError("Malformed sh:conforms")
    return str(value) in ("true", "1")


def projection(shapes, data, conforms, results):
    graph = Graph()
    # Include full input structure, not just the outgoing triples of sourceShape.
    # A blank node's role also prevents accidental shape/data scope merging.
    for source, role in ((shapes, TEST.ShapesBlank), (data, TEST.DataBlank)):
        for triple in source:
            graph.add(triple)
            for term in (triple[0], triple[2]):
                if isinstance(term, BNode):
                    graph.add((term, TEST.inputRole, role))
    root = URIRef(TEST.Report)
    graph.add((root, SH.conforms, Literal("true" if conforms else "false", datatype=XSD.boolean)))
    for result in results:
        node = BNode()
        graph.add((root, SH.result, node))
        graph.add((node, RDF.type, SH.ValidationResult))
        for key in ("focusNode", "sourceShape", "sourceConstraintComponent", "resultSeverity", "value"):
            value = result.get(key)
            if value is not None:
                graph.add((node, SH[key], value))
        path = write_path(graph, result.get("resultPath"))
        if path is not None:
            graph.add((node, SH.resultPath, path))
    return graph


def report_rename_map(report):
    mapping = {}

    def walk(result):
        for key in ("focusNode", "sourceShape", "sourceConstraintComponent", "resultSeverity", "value"):
            term = result.get(key)
            if isinstance(term, dict) and term["termType"] == "BlankNode":
                raw = BNode(term["value"])
                if raw not in mapping:
                    mapping[raw] = BNode(f"input{len(mapping)}")
        for message in result.get("resultMessage", []):
            if message["termType"] == "BlankNode":
                raise AssertionError("A result message cannot be a blank node")
        for detail in result.get("detail", []):
            walk(detail)

    for result in report["results"]:
        walk(result)
    return {renamed: raw for raw, renamed in mapping.items()}


def summary(conforms, results):
    return {
        "conforms": conforms,
        "results": len(results),
        "components": sorted(str(r["sourceConstraintComponent"]).removeprefix(str(SH)) for r in results),
    }


def compare_engine(case, name, shapes, data, conforms, results, actual_projection):
    candidate = projection(shapes, data, conforms, results)
    matched = isomorphic(actual_projection, candidate)
    row = {"engine": name, **summary(conforms, results), "status": "matched" if matched else "mismatch"}
    if not matched:
        expected_divergence = case.get("knownDivergences", {}).get(name)
        if expected_divergence:
            expected = projection(shapes, data, expected_divergence["report"]["conforms"],
                                  json_results(expected_divergence["report"]))
            if not isomorphic(candidate, expected):
                raise AssertionError(f"{name}: changed/unexpected divergence: {row}")
            row.update(status="documented-engine-divergence", reason=expected_divergence["reason"],
                       specification=expected_divergence["specification"])
        else:
            # Count differences without dumping input data or enormous RDF graphs.
            _, only_actual, only_oracle = graph_diff(actual_projection, candidate)
            raise AssertionError(f"{name}: unexpected report mismatch {row}; "
                                 f"projection-only triples product={len(only_actual)}, oracle={len(only_oracle)}")
    return row


def run_case(case):
    moon_shapes = nt_graph(case["moonShapesRdf"])
    moon_data = nt_graph(case["moonDataRdf"])
    moon_report = case["actual"]["report"]
    actual_results = json_results(moon_report)
    actual_projection = projection(moon_shapes, moon_data, moon_report["conforms"], actual_results)
    if "expected" in case:
        expected = case["expected"]
        assert summary(moon_report["conforms"], actual_results) == expected, f"Normative expected result: {expected}"

    serialized = nt_graph(case["actual"]["reportRdf"])
    serialized_root = report_root(serialized)
    serialized_results = rdf_results(serialized, serialized_root, report_rename_map(moon_report))
    assert isomorphic(actual_projection, projection(
        moon_shapes, moon_data, conforms_from_rdf(serialized, serialized_root), serialized_results
    )), "MoonSHACL JSON and RDF reports differ"

    js_shapes, js_data = nt_graph(case["rdfjsShapesRdf"]), nt_graph(case["rdfjsDataRdf"])
    assert isomorphic(moon_shapes, js_shapes), "MoonTTL and N3 shapes parsing differ"
    assert isomorphic(moon_data, js_data), "MoonTTL and N3 data parsing differ"
    js_report = nt_graph(case["rdfjsReportRdf"])
    js_root = report_root(js_report, case["rdfjsReportRoot"])
    js_results = rdf_results(js_report, js_root)
    js_row = compare_engine(case, "rdf-validate-shacl", js_shapes, js_data,
                            conforms_from_rdf(js_report, js_root), js_results, actual_projection)

    py_shapes = turtle_graph(case["shapes"], case["shapesBase"])
    py_data = turtle_graph(case["data"], case["dataBase"])
    assert isomorphic(moon_shapes, py_shapes), "MoonTTL and RDFLib shapes parsing differ"
    assert isomorphic(moon_data, py_data), "MoonTTL and RDFLib data parsing differ"
    # pySHACL adds two internal axioms to its shapes graph even with inference
    # disabled. Compare reports against immutable pre-validation input snapshots.
    input_shapes, input_data = rdf11_graph(py_shapes), rdf11_graph(py_data)
    try:
        py_conforms, py_report, _ = validate(
            py_data, shacl_graph=py_shapes, inference="none", advanced=False,
            meta_shacl=False, abort_on_first=False, allow_infos=False, allow_warnings=False,
            do_owl_imports=False, inplace=False,
        )
    except Exception as error:
        observation = case.get("knownErrors", {}).get("pySHACL")
        if not observation or type(error).__name__ != observation["type"] or observation["includes"] not in str(error):
            raise
        py_row = {"engine": "pySHACL", "status": "documented-engine-error",
                  "errorType": type(error).__name__, "error": str(error),
                  "reason": observation["reason"], "specification": observation["specification"]}
        return {"name": case["name"], "group": case["group"],
                "product": summary(moon_report["conforms"], actual_results),
                "inputGraphsIsomorphic": True, "jsonRdfConsistent": True,
                "semanticExpectationPassed": "expected" in case,
                "expectedSummary": case.get("expected"),
                "comparisons": [js_row, py_row]}
    if not isinstance(py_report, Graph):
        raise AssertionError(f"pySHACL failed: {py_report}")
    py_results = rdf_results(py_report, report_root(py_report))
    py_row = compare_engine(case, "pySHACL", input_shapes, input_data,
                            py_conforms, py_results, actual_projection)
    return {"name": case["name"], "group": case["group"],
            "product": summary(moon_report["conforms"], actual_results),
            "inputGraphsIsomorphic": True, "jsonRdfConsistent": True,
            "semanticExpectationPassed": "expected" in case,
            "expectedSummary": case.get("expected"),
            "comparisons": [js_row, py_row]}


def self_test_projection():
    """Prove that the harness rejects source-blank swaps and lost duplicates."""
    a, b = BNode("a"), BNode("b")
    shapes = Graph()
    shapes.add((a, SH.path, URIRef("urn:a")))
    shapes.add((b, SH.path, URIRef("urn:b")))
    result = {"focusNode": URIRef("urn:focus"), "sourceShape": a,
              "sourceConstraintComponent": SH.MinCountConstraintComponent,
              "resultSeverity": SH.Violation, "value": None, "resultPath": None}
    correct = projection(shapes, Graph(), False, [result])
    wrong_source = projection(shapes, Graph(), False, [{**result, "sourceShape": b}])
    lost_duplicate = projection(shapes, Graph(), False, [result, result])
    assert not isomorphic(correct, wrong_source), "Source shape identity is not checked"
    assert not isomorphic(correct, lost_duplicate), "Result multiplicity is not checked"
    renamed = Graph()
    renamed_a, renamed_b = BNode("different-a"), BNode("different-b")
    renamed.add((renamed_a, SH.path, URIRef("urn:a")))
    renamed.add((renamed_b, SH.path, URIRef("urn:b")))
    assert isomorphic(correct, projection(renamed, Graph(), False, [{**result, "sourceShape": renamed_a}])), \
        "Equivalent blank-node renaming should be accepted"


def main():
    versions = {name: importlib.metadata.version(name) for name in ("pyshacl", "rdflib")}
    assert versions == {"pyshacl": "0.30.1", "rdflib": "7.6.0"}, versions
    if "--check" in sys.argv[1:]:
        json.dump({"versions": versions}, sys.stdout)
        return 0
    self_test_projection()
    payload = json.load(sys.stdin)
    rows, failures = [], []
    for case in payload["cases"]:
        try:
            rows.append(run_case(case))
        except Exception as error:
            failures.append({"name": case["name"], "error": f"{type(error).__name__}: {error}"})
    json.dump({"versions": versions, "projectionSelfTests": 3, "cases": rows, "failures": failures}, sys.stdout)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
