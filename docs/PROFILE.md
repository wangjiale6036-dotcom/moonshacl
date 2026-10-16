# MoonSHACL 0.1.0 能力契约

本文只描述已发布 v0.1.0 的实际能力。申报最终目标已明确为完整 SHACL 2017 Core；现有限制中属于 Core 的缺项列入必做，阶段、验收和案例见 [最终范围与阶段安排](CORE-ROADMAP.zh-CN.md)。该计划不表示当前版本已实现。

基线为 [SHACL 2017 Recommendation](https://www.w3.org/TR/shacl/)，RDF 1.1 单个 data graph/shapes graph。编译成功表示规则属于以下范围，不表示数据通过；无 target 的 shape 不会自行产生 focus nodes，可用 `validate_node` 显式执行。空 shapes graph 在显式提供时有效，请避免把它当作已有规则的校验。

## Targets、路径与结果

支持 `targetNode`、`targetClass`、`targetSubjectsOf`、`targetObjectsOf`，以及 shapes graph 中 `rdfs:Class` shape 的隐式类 target。SHACL 类型检查沿 shapes graph 的明确 subclass 边展开。

支持 IRI predicate、`inversePath`、至少两个成员的 RDF list sequence、至少两个成员的 `alternativePath`，以及 `zeroOrMorePath`、`oneOrMorePath`、`zeroOrOnePath`。路径结果去重，循环图上的重复路径终止。

报告字段包括 `focusNode`、`sourceShape`、`sourceConstraintComponent`、`resultSeverity`、`resultPath`、可选 `value`、`resultMessage` 与嵌套 `detail`。任意 severity 的错误结果都会使 `conforms=false`。额外 `work.checked/reused` 统计的是根 shape/focus 校验次数，不是图读取数或耗时。

## 支持的 24 个约束参数

| 组 | 参数 |
|---|---|
| 值类型 | `class`, `datatype`, `nodeKind` |
| 数量 | `minCount`, `maxCount` |
| 字符串 | `minLength`, `maxLength`, `languageIn`, `uniqueLang` |
| 集合 | `hasValue`, `in` |
| 组合 | `node`, `property`, `not`, `and`, `or`, `xone` |
| 属性集合关系 | `equals`, `disjoint` |
| 闭合图 | `closed`，附属 `ignoredProperties` |
| 条件数量 | `qualifiedValueShape`, `qualifiedMinCount`, `qualifiedMaxCount`, `qualifiedValueShapesDisjoint` |

支持六种标准 nodeKind、severity/message/deactivated 及 name/description/order/group/defaultValue 等展示注解。数量和长度参数只接受非负 `xsd:integer`，上限为 32 位有符号整数。RDF list、参数基数、property/node shape 适用范围在编译时检查。

布尔开关按规范组件的字面量条件启用，`"1"^^xsd:boolean` 不统一改写为 RDF term `true`；官方 uniqueLang-002 用例覆盖这一点。datatype 为 boolean 的数据值仍接受合法词法 `1/0/true/false`。长度按 Unicode 码点计数，集合比较保留 RDF term 身份；`"01"^^xsd:integer` 与 `"1"^^xsd:integer` 不合并。

qualified 组件仅在必需参数齐全时实例化；单独的 qualified 数量参数依规范不构成约束。disjoint 会检查同一父 shape 下其他 property shape 的 qualified shapes。该隐式依赖也纳入递归检测和更新读取追踪。

## Datatype 词法检查

支持 `rdf:langString` 和以下 18 个 `xsd:` datatype：

`string`, `boolean`, `integer`, `int`, `long`, `short`, `byte`, `unsignedLong`, `unsignedInt`, `unsignedShort`, `unsignedByte`, `positiveInteger`, `negativeInteger`, `nonNegativeInteger`, `nonPositiveInteger`, `decimal`, `hexBinary`, `duration`。

整数使用 BigInt 检查，无任意整数精度丢失；派生整数有对应边界检查。非字符串的空白处理限定为 XML whitespace。decimal/duration 的词法检查来自规范语法，不采用浮点近似值或通用日期解析器。

未列出的 datatype（包括 float/double、date/dateTime、anyURI、HTML、自定义 datatype）作为 `sh:datatype` 参数时会拒绝编译。数据图可以含这些字面量；如果 shape 未约束 datatype，不会自动检查全部数据字面量。

## 明确拒绝

SPARQL 约束/targets、JS/AF/rules、自定义 ConstraintComponent（含 subclass typing）、自动 `owl:imports`、`sh:entailment`；pattern/flags、min/max inclusive/exclusive、lessThan/lessThanOrEquals；递归 shapes 或超过 64 层的 shape/path 嵌套；错误参数、坏 RDF lists/路径。

未知 `sh:` 约束出现在被识别的 shape 上时会拒绝。普通其他命名空间注解不执行约束；本实现不会把任意 RDF 谓词推断为自定义规则。

路径 operator blank node 必须只有定义 triple；sequence head 不允许额外属性。这比某些标准路径实例的允许范围严格。官方两个 `path-strange` 用例明确拒绝，不能把它们算通过。

Turtle 输入不接受 named graph 展平、N3 formula/变量、RDF 1.2 triple terms/方向语言字面量；不会获取远端词表。MoonTTL 适配只做词项转换和兼容修正，错误位置对应相邻标点分隔后的等价文本。

## API 的输入与事务边界

`Graph::new` 是低层构造 API，调用者提供合法 RDF terms/triples：IRI 应为合法绝对 IRI，主语不能为 literal，blank labels 与语言标签应合法，带 language 的 literal 使用 `rdf:langString`。它去重并索引，不是 RDF term 语法验证器。Turtle 入口由解析/materializer 执行输入检查。

分别解析的文档应使用不同 blank-node scope；同一个源图更新则使用该图已有的节点身份。CLI 为 shapes/data 分别添加 scope，并拒绝带空白节点的文本 delta，避免错误合并。

`Session::new` 允许初始不合格图，以便后续一次更新修复。`preview` 无状态变更；`apply` 先删除再添加，对最终集合校验，成功才替换图及缓存，拒绝时保留二者。新增/消失 targets 每次重新计算。缓存包含失败结果和零值读取；报告数组及复合路径为防御性副本。

更新仍重建候选图和索引。Session 是单进程内存对象，无持久化、并发事务隔离、自动补全或远程提交功能。
