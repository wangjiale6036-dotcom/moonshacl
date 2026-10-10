# MoonSHACL

[![CI](https://github.com/wangjiale6036-dotcom/moonshacl/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiale6036-dotcom/moonshacl/actions/workflows/ci.yml)

**MoonBit 原生 RDF 图契约编译与事务校验库。** 读取标准 SHACL shapes graph，检查跨节点关系和属性路径，并在图更新前进行校验。失败的更新保留原图，报告指出违反规则的节点、路径和来源 shape。

这是基于 2017 SHACL Recommendation 的**受限 profile**，不是完整 SHACL Core/SPARQL 处理器。不支持的规则会在编译阶段返回错误；不会忽略约束后报告“通过”。

## 适合什么需求

MoonTTL 已提供 MoonBit 的 RDF 解析层，MoonSHACL 补充解析之后的图约束执行层。适用于需要 MoonBit 同进程嵌入的 RDF 导入、共享对象引用检查和数据更新预检。

例如 Alice 和 Bob 都引用同一家公司的名称。删除公司的名称会同时使两个人违反 `(employer name)` 路径约束；直接替换名称则可以作为一个原子更新通过。普通 JSON 字段校验无法直接表达这种共享节点关系。

真实标准样本采用 [SEMIC 官方 DCAT-AP 3.0.0 base shapes](https://github.com/SEMICeu/DCAT-AP/blob/4470b8ea907b7eb9ec55ab22befd1ecd2210ff32/releases/3.0.0/shacl/dcat-ap-SHACL.ttl)。欧盟已有 [SHACL 验证服务](https://www.itb.ec.europa.eu/shacl/dcat-ap/upload)，证明图约束有实际用途。本项目尚无外部用户采用证据。

## 运行

需要 MoonBit 工具链、Node.js 和 native 测试所需的 C 编译器。已验证 Moon `0.1.20260920`、moonc `0.10.14+7d59c7ec9`、Node 24；Linux/Windows CI 均通过。`scripts/moon.mjs` 优先使用工作区 `.tools/moon`，否则使用 PATH 中的 `moon`。工具链安装见 [MoonBit 官方文档](https://docs.moonbitlang.com/en/latest/toolchain/moon/index.html)。

只运行 CLI 可下载 [v0.1.0 发行包](https://github.com/wangjiale6036-dotcom/moonshacl/releases/tag/v0.1.0) 中的 `moonshacl-0.1.0-cli.tar.gz`，解压后用 Node 24 运行 `node cli.mjs --help`，无需 MoonBit 编译器或 npm 安装。源码构建步骤如下：

```sh
node scripts/moon.mjs update
npm ci --ignore-scripts
npm run build
node cli.mjs validate examples/people-shapes.ttl examples/people-data.ttl
```

CLI 运行只需要 Node 内置模块和编译后的 `dist/moonshacl.mjs`。N3、rdf-validate-shacl、shacl-engine 是测试依赖，产品不会调用这些验证器。

```sh
# 只检查规则是否属于支持范围
node cli.mjs audit examples/people-shapes.ttl

# 删除共享公司名称：拒绝更新，退出码 1
node cli.mjs update examples/people-shapes.ttl examples/people-data.ttl examples/empty.ttl examples/remove-shared-name.ttl

# 删除旧名称并加入新名称：原子提交，退出码 0
node cli.mjs update examples/people-shapes.ttl examples/people-data.ttl examples/add-shared-name.ttl examples/remove-shared-name.ttl

# 使用未经修改的官方规则
node cli.mjs validate fixtures/dcat-ap-3.0.0.ttl examples/dcat-data.ttl

# 标准 RDF 报告，N-Triples 输出
node cli.mjs validate examples/people-shapes.ttl examples/people-data.ttl --rdf
```

退出码：`0` 表示通过/已提交；`1` 表示不符合约束/更新被拒绝；`2` 表示请求、解析或规则范围错误。`update` 返回内存中候选校验的结果和最终图，不会改写输入文件。文本增删只接受 IRI 主语与 IRI/字面量宾语；空白节点更新使用库 API 的精确节点身份。

## MoonBit API

模块名：`wangjiale6036-dotcom/moonshacl`；Turtle 适配包：`wangjiale6036-dotcom/moonshacl/turtle`。[Mooncakes 0.1.0](https://mooncakes.io/docs/wangjiale6036-dotcom/moonshacl@0.1.0) 已发布并重新安装验证；在消费项目中运行 `moon add wangjiale6036-dotcom/moonshacl@0.1.0`。公开包消费示例见 `examples/consumer`。

```moonbit
let shapes = @turtle.parse(shapes_text, scope="shapes-") |> Result::unwrap
let data = @turtle.parse(data_text, scope="data-") |> Result::unwrap
let plan = @moonshacl.compile(shapes) |> Result::unwrap
let report = plan.validate(data)
let session = @moonshacl.Session::new(plan, data)
let preview = session.preview(additions, removals)
let update = session.apply(additions, removals)
```

实际应用应处理解析和编译的 `Err`；`unwrap` 仅用于短示例。`additions/removals` 类型为 `Array[Triple]`。`compile` 返回 `Result[Plan, Array[Problem]]`，与不符合约束的 `Report` 分开。

同一原生调用示例可在三个后端运行：

```sh
node scripts/moon.mjs run src/demo --target js
node scripts/moon.mjs run src/demo --target wasm-gc
node scripts/moon.mjs run src/demo --target native
```

`Plan` 可以复用；`validate_node` 可指定 shape/focus node；`Report.to_json()` 与 `to_graph()` 分别输出 JSON 和标准 RDF 报告。图采用集合语义并保留 RDF 字面量的词法形式、datatype 和 language。对外返回的数组与路径不允许间接改写内部计划/缓存。

## 支持范围

四类标准 target；谓词、逆向、序列、备选及三种重复路径；类、datatype、nodeKind、数量、字符串长度、语言、集合、逻辑组合、嵌套 shape、equals/disjoint、closed 和 qualified 数量约束。具体参数、datatype 和拒绝项见 [PROFILE.md](docs/PROFILE.md)。

不支持 SPARQL、JS/AF、自定义约束组件、递归 shapes、自动 imports、推理服务、pattern/flags、数值范围与 lessThan 比较。日期等未实现词法校验的 datatype 会被拒绝。类检查只沿数据图明确给出的 `rdf:type` 和 `rdfs:subClassOf` 边，不做完整 RDFS/OWL 推理。

更新缓存记录实际图读取，包含查不到值的读取，并对变化涉及的 focus nodes 复验。每次更新仍会重建候选图并重算 targets；这不是数据库增量引擎，也没有性能胜过现有方案的实测结论。Session 无并发/持久化事务语义。

Turtle 适配复用 `thy1016/moonttl@0.3.0` 的语法解析和 materializer，并修正该版本相邻标点与 bare `a` 的兼容问题，详见 [THIRD_PARTY.md](THIRD_PARTY.md)。不验证部分解析结果。

## 验证

```sh
npm test
```

该命令执行格式检查、编译检查、三个后端测试与原生调用示例、CLI/JSON 边界检查及独立验证器对照。测试完成后即可离线运行，官方 fixtures 已固定在仓库中，测试不需要抓取在线数据。

当前结果：三个后端各 21 个测试通过；98 个 W3C validation fixtures 中 76 个通过、22 个明确拒绝、0 个已执行语义失败；每个后端 1,000 次确定性更新提案与全量复验一致；13 个 CLI 检查、17 个 JSON 边界检查、14 个独立引擎场景通过。这些数字不表示完整 SHACL 认证。

用例来源、逐项拒绝原因和对照字段见 [VALIDATION.md](docs/VALIDATION.md)。源码包保留 tests 和第三方许可，调查快照 `audit/` 不进入 Mooncakes 包。

三个端到端场景与验收产物见 [SCENARIOS.md](docs/SCENARIOS.md)。独立消费模块在三个后端验证公开 API；`node scripts/release-smoke.mjs` 检查发布包脱离开发目录运行。源码统计脚本排除测试、生成 fixtures 和宿主层：2,020 行去空白/注释，1,539 行再去纯分隔符。可审查记录见 [docs/evidence](docs/evidence)，统计口径不代替赛事认定。

精简八项 [项目申报书](PROPOSAL.zh-CN.md) 与 [维护发行流程](docs/RELEASING.md) 一并提供。

## 选题与已有方案

当前 Mooncakes 公开索引与相邻模块调查尚未发现同功能 MoonBit SHACL 引擎；未发布仓库及全部历史源码不在穷举范围。已有 pySHACL、RDF/JS 与 RDF4J 方案具备更全面的能力，事务/增量、CLI、浏览器和离线运行都不是本项目的全球创新点。

独立贡献在于 MoonBit 原生的 RDF targets/paths/约束执行、支持范围编译检查、可追踪标准报告和图更新预检，并与已有 MoonTTL 解析层直接集成。需要完整 SHACL 或允许外部服务的系统可选成熟方案。完整选题证据与查重范围见 [选题依据](docs/RESEARCH.zh-CN.md)。

原始实现采用 Apache-2.0；第三方 tests、官方 shapes、依赖库分别保留其许可证与署名，见 [THIRD_PARTY.md](THIRD_PARTY.md)。
