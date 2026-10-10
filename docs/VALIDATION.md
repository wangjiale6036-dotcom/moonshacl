# MoonSHACL 0.1.0 验收记录

验证日期：2026-10-10。环境为 Windows/MSVC、Moon `0.1.20260920`、moonc `0.10.14+7d59c7ec9`、Node `24.21.0`。重跑命令：安装已固定的依赖后，在仓库根目录运行 `npm test`。

## 结果

| 检查 | 结果 |
|---|---|
| `moon fmt --check` / `moon check` | 通过，编译检查无警告 |
| JS / Wasm-GC / native | 每个后端 21/21 MoonBit 测试通过 |
| W3C official validation fixtures | 每个后端 76 通过 / 22 明确拒绝 / 0 已执行语义失败 |
| 更新缓存与全量复验 | 每个后端 1,000 次确定性提案一致 |
| 原生消费示例 | 三个后端运行通过 |
| Node CLI | 8/8 检查通过 |
| JSON 输入边界 | 17/17 检查通过 |
| rdf-validate-shacl 0.6.5 独立对照 | 14/14 场景匹配 |
| 原始文件校验 | 113 个 W3C 资源和 DCAT-AP 文件的 SHA-256 核对通过 |

这里的 21 是 MoonBit 测试块数，W3C 的 98 个用例由其中一个测试块运行；不能把两者简单相加为独立测试数。原始 JSON 结果写入仓库工作区 `audit/2026-10-10/verification.json`、`conformance-*.json`、`oracle.json`。调查与验收快照不进入 Mooncakes 发行包。

## 官方用例比较

固定 [W3C 仓库 commit](https://github.com/w3c/data-shapes/tree/07458ebb1ece6addc664636d70b08444a7b66609/data-shapes-test-suite/tests/core) 的 98 个 `sht:Validate` fixtures；另包含其引用的辅助 data/shapes graphs，共 113 个资源。全部输入解析成功，规则不支持时返回编译错误。测试直接使用官方预期结果，未删改失败节点或约束。

比较 `conforms`、focusNode、sourceShape、sourceConstraintComponent、resultSeverity、value、结构化 resultPath；官方要求的 resultMessage 必须出现在报告中。结果按多重集合比较，保留两个不同根约束产生的相同错误。标准可选的额外消息/detail 不要求与其他处理器完全一致。

逐项能力边界固定在测试中：必须保持 76/22/0，不能把新增语义失败改归为“不支持”后静默让测试通过。这是项目声明的受限 profile 验收，不是完整 SHACL Core 认证。

### 22 个明确拒绝的用例

| 用例 | 原因 |
|---|---|
| `complex/personexample.ttl` | pattern |
| `node/maxExclusive-001.ttl` | 数值范围 |
| `node/maxInclusive-001.ttl` | 数值范围 |
| `node/minExclusive-001.ttl` | 数值范围 |
| `node/minInclusive-001.ttl` | 数值范围 |
| `node/minInclusive-002.ttl` | 数值范围 |
| `node/minInclusive-003.ttl` | 数值范围 |
| `node/pattern-001.ttl` | pattern |
| `node/pattern-002.ttl` | pattern/flags |
| `path/path-strange-001.ttl` | sequence head 的额外属性超出严格路径范围 |
| `path/path-strange-002.ttl` | sequence head 的额外属性超出严格路径范围 |
| `property/datatype-001.ttl` | 未实现 xsd:date 词法校验 |
| `property/lessThan-001.ttl` | lessThan |
| `property/lessThan-002.ttl` | lessThan |
| `property/lessThanOrEquals-001.ttl` | lessThanOrEquals |
| `property/maxExclusive-001.ttl` | 数值范围 |
| `property/maxInclusive-001.ttl` | 数值范围 |
| `property/minExclusive-001.ttl` | 数值范围 |
| `property/minExclusive-002.ttl` | 数值范围 |
| `property/or-datatypes-001.ttl` | 未实现 rdf:HTML 词法校验 |
| `property/pattern-001.ttl` | pattern |
| `property/pattern-002.ttl` | pattern/flags |

两个 path-strange 用例说明本 profile 比标准路径允许范围严格，并不意味着官方输入错误。其余未支持组件也不能算校验通过。

## 独立引擎对照

固定 `rdf-validate-shacl@0.6.5`，由 `n3@1.26.0` 独立解析同样的输入。场景包括共享名称删除、inverse、datatype、uniqueLang、closed、qualified、xone、alternative 去重、数据图 subclass，以及官方 DCAT-AP 正例/缺失 accessURL。

比较 conformance、focusNode、sourceConstraintComponent、severity、value、路径结构；IRI sourceShape 精确比较。由于两套解析器的空白节点标签不同，匿名 sourceShape 只比较 BlankNode 类型，未作完整图同构比较。不得称所有报告字段完全相同。另用 N3 重新解析产品 RDF 报告，检查顶层结果数量。

次级 `shacl-engine@1.1.0` 对空数据图中的显式 literal target 会返回通过，其 `ShapeValidator.js` 在 `dataset.size===0` 时跳过验证；这个差异已记录。MoonSHACL 继续验证显式 target 并返回 datatype 违反结果，主对照引擎同意。未修改产品以迎合该行为，也未把该场景记录为“所有引擎一致”。

## 官方 DCAT-AP 演示边界

使用 [DCAT-AP 3.0.0 base SHACL 文件](https://github.com/SEMICeu/DCAT-AP/blob/4470b8ea907b7eb9ec55ab22befd1ecd2210ff32/releases/3.0.0/shacl/dcat-ap-SHACL.ttl)，commit 与 SHA-256 在 `fixtures/DCAT-SOURCE.json`。生成脚本直接读取 Git blob，避免 Windows checkout 换行转换改变原始文件。

`examples/dcat-data.ttl` 包含 Dataset、Distribution、title/description、accessURL，以及 URL 的显式 `rdfs:Resource` 类型。本引擎没有把所有 IRI 自动推理为 Resource；示例给出满足 base shapes class 检查所需的类型。

正例通过；删除 accessURL 的更新不通过并保持原图。没有验证完整 DCAT-AP 官方服务的其他 shapes、词表、远程 imports 或推理配置，不能把演示等同于官方完整认证。

## 更新正确性与独立性

400 次提案覆盖基本新增/删除/type/name；600 次提案覆盖共享两跳路径、inverse 入边、重复路径循环、target 集合与 subclass 变化。每次分别比较 preview、apply、最终图和当前 report 与全量复验；拒绝时检查原图不变。另有 qualified sibling、closed 零读取和防御性路径副本的回归测试。

全量与缓存模式共用本项目约束语义，因此这些 1,000 次提案只能证明更新模式与全量模式一致；语义本身由官方预期结果和独立引擎对照补充检查。没有随机压力测试、并发隔离验证或百万级图性能基准。

共享公司名称删除示例有三个 Person focus nodes。提案报告 `checked=2, reused=1`，定位 Alice/Bob，Carol 结果复用；拒绝后原始 CLI 示例图保持 11 triples。原生消费示例更精简，保留 8 triples，三个后端结果一致。

## 原创代码与依赖

RDF term/索引、规则编译、路径求值、约束执行、读取依赖追踪、更新预检、标准报告由 MoonBit 实现。Turtle 语法和 materialization 复用已有 MoonTTL；CLI 只负责文件/参数传输，测试验证器只用于对照。生成的 W3C/DCAT fixtures 是第三方测试资料，不属于原创代码量。

完整支持范围、低层 Graph API 的合法 RDF 输入前提、Session 内存/并发边界见 [PROFILE.md](PROFILE.md)。
