# MoonSHACL 0.4.0 能力契约

实现基线为 [SHACL 2017 Recommendation Part A](https://www.w3.org/TR/2017/REC-shacl-20170720/)，覆盖全部 29 个 Core 约束组件及 targets、路径、验证报告和失败传播。v0.1.0 受限实现保留在历史 tag；本版不再排除 pattern、范围或排序组件。证据见 [VALIDATION.md](VALIDATION.md)，使用官方测试不代表 W3C 认证。

## Targets、路径和报告

支持四种显式 target，以及具有 SHACL shape 类型和 rdfs:Class 类型的 IRI shape 的隐式类 target。类型判断沿图中明确的 rdf:type / rdfs:subClassOf 展开，不提供完整 RDFS/OWL 推理。无 target 的 shape 可由 validate_node 指定焦点执行；空数据图仍检查显式 targets。

支持 predicate、inverse、sequence、alternative、zeroOrMore、oneOrMore、zeroOrOne 七种路径。序列和备选至少两个成员；sequence list 可附带注解，operator blank node 保留规范要求的单 triple 结构。重复路径对循环数据终止，路径值去重。

报告包括 focusNode、sourceShape、sourceConstraintComponent 和 resultSeverity；resultPath 按属性 shape、closed 等约束的要求提供，value、resultMessage 和嵌套 detail 按适用条件或可选规则提供。所有 severity 的违反均使 conforms=false。lessThan/lessThanOrEquals 逐一检查所有值对，保留每个失败配对产生的结果。work.checked/reused 表示根 shape/focus 的复验/缓存复用次数。

## 全部 Core 组件

| 类别 | 组件及相关参数 |
|---|---|
| 值类型（3） | class、datatype、nodeKind |
| 数量（2） | minCount、maxCount |
| 范围（4） | minExclusive、minInclusive、maxExclusive、maxInclusive |
| 字符串（5） | minLength、maxLength、pattern（flags）、languageIn、uniqueLang |
| 属性对（4） | equals、disjoint、lessThan、lessThanOrEquals |
| 逻辑（4） | not、and、or、xone |
| shape（4） | node、property、qualifiedMinCount、qualifiedMaxCount；含 qualifiedValueShape、qualifiedValueShapesDisjoint |
| 其他（3） | closed（ignoredProperties）、hasValue、in |

supported_parameters() 返回 33 个参数名称。数量、长度和 qualified 阈值接受任意精度 xsd:integer，按规范比较负数、零和大数，没有人为 32 位上限。sh:node 必须引用 node shape。参数基数、节点种类、列表、路径和 shape 类型在编译时检查。

deactivated 必须是 RDF terms true/false；uniqueLang、closed 等按各组件规定的 true term 启用，不把 "1"^^xsd:boolean 一律替换为 true。数据中的 boolean 接受合法词法 true/false/1/0。长度按 Unicode 码点计数；集合组件保持 RDF term 身份，"01"^^xsd:integer 不等于 "1"^^xsd:integer。

## 数值、datatype 和时间上下文

sh:datatype 接受任意 datatype IRI，并精确检查字面量的 datatype。已知词法检查覆盖 string、boolean、integer 及派生整数、decimal、float、double、dateTime；另实现 date、hexBinary、duration 和 rdf:langString 检查。未知 datatype 按 IRI 匹配，不臆造其词法验证器，不声称所有自定义字面量词法都已验证。

integer/decimal 使用 BigInt 精确值；float/double 按 IEEE binary32/64 直接舍入及 SPARQL 类型提升比较，处理 NaN、INF、溢出和下溢。字符串使用 Unicode 码点顺序，boolean 使用 false < true。坏词法、NaN、类型错误和不可比值产生约束违反，不转成宿主字符串比较。

日期比较有两种明确上下文：

- 默认 implicit_timezone=None：双方带时区时归一到 UTC，双方无时区时比较本地字段；混合时区按 [XSD 1.0 ±14 小时部分序](https://www.w3.org/TR/2004/REC-xmlschema-2-20041028/#dateTime-order) 判断，不确定则不可比。这与固定官方 node/minInclusive-003 预期一致。
- compile(..., implicit_timezone=Some(minutes))：按 [XPath 2.0 动态上下文](https://www.w3.org/TR/2007/REC-xpath-functions-20070123/#comp.datetime) 为无时区值补充指定偏移，范围 -840..840 分钟，已有时区不变。例如 Some(0) 为 UTC，Some(480) 为 UTC+08:00。

固定 SHACL 用例与 XPath 隐式时区上下文存在解释差异，因此同时提供、测试并披露两种行为；官方用例通过不等同于任意 SPARQL 宿主上下文相同。JSON 字段为 implicitTimezoneMinutes，CLI 选项为 --timezone-minutes。日历、时区和小数秒不依赖系统本地时区；xsd:date 词法和排序是附加兼容能力。

## 正则

纯 MoonBit 实现 [XPath 2.0 / SPARQL REGEX](https://www.w3.org/TR/2010/REC-xpath-functions-20101214/#regex-syntax)，支持 i/m/s/x、Unicode 类别与块、字符类差集、XML 名称字符、捕获及反向引用、贪婪/惰性量词、锚点和分支。Unicode 数据固定 15.0。默认 dot 排除 CR/LF，s 标志允许换行；不以 JavaScript RegExp 代替标准语义。

无反向引用表达式使用 NFA；带引用时保留捕获状态执行。正则工作量超限返回执行失败，不能当作“不匹配”。资源限制及错误见包实现和测试。W3C QT3 中只属于 XPath 3.x、XSD 1.1 或外围函数类型语义的案例有逐项排除记录，它们不是 SHACL Core 组件排除。

## 图装载与扩展

load_shapes(shapes, data, resources, root_iri=Some(root_url)) 解析 shapes 的 owl:imports / sh:shapesGraph 以及 data 的 sh:shapesGraph，按显式资源映射传递合并，循环只访问一次；缺失或非法引用明确失败。合并结果移除已解析链接，原 shapes/data 不变。低层 compile 遇到未解析链接会报错。

JSON resources 为图 IRI 到 Turtle 内容的映射；CLI --resources MAP.json 为图 IRI 到文件路径的映射，路径相对于映射文件。没有自动网络请求。各资源使用不同 blank-node scope；低层 Graph 调用者负责正确的文档身份。root_iri 用于将根文档标记为已加载，避免循环回到根时重建匿名节点；JSON 入口使用 shapesBase，资源映射中同名根文档须与显式输入内容一致，否则报冲突。

默认 Core 模式对 SPARQL/JS/AF/custom components 等未执行扩展返回 Plan::diagnostics()（JSON diagnostics），结果只表示 Core。strict=true / CLI --strict 将其作为编译失败。声明未支持的 entailment regime 始终失败。其他命名空间注解不会自动变成约束。

不提供 SHACL-SPARQL、JS/AF、SHACL 1.2、自定义查询执行器或完整推理。2017 未定义递归 shapes 的统一语义，本库明确拒绝递归。嵌套 shape 执行上限为 256 层；路径默认 max_depth=1024，可由调用方调整；超限属于资源失败，不是合法 Core 语法不受支持。

## API、失败与事务

Graph::new 是低层 RDF 构造接口，调用者负责合法绝对 IRI、主语种类、blank label、语言标签及 datatype；Turtle 入口执行语法/materialization 检查。不展平 named graphs，不接受 N3 formula 或 RDF 1.2 triple terms。

compile 返回 Result[Plan, Array[Problem]]。Plan::validate、Session::new/report/preview/apply 可抛出 ValidationFailure；validate_node 保持 Result 返回。本版调用方需要传播或捕获异常。输入/编译失败、执行失败与 conforms=false 是不同状态，不以执行失败出具符合结论。

Session 允许初始不合格图。preview 不改变状态；apply 先删除再添加，校验最终候选图，仅在 conforms=true 时替换图和缓存。规则违反或执行失败均保留原图与缓存。缓存追踪实际读取，包含零值读取；targets 每次重算。报告数组和路径为防御性副本。

CLI 文本 delta 仅使用 IRI 主语及 IRI/字面量宾语；空白节点更新需 Graph API 精确身份。Session 是单进程内存对象，没有持久化或并发隔离。更新仍重建候选图和索引，未宣称性能优于成熟引擎。
