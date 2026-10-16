# MoonSHACL

发行编号说明：固定 MoonBit 工具链要求包版本为 `0.x.y`，因此本次完整 Core 发行使用 v0.4.0；版本编号不缩减下述功能范围。

[![CI](https://github.com/wangjiale6036-dotcom/moonshacl/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiale6036-dotcom/moonshacl/actions/workflows/ci.yml)

**MoonBit 原生 SHACL 2017 Core 图契约与事务校验库。** 读取 RDF shapes graph，检查跨节点关系和属性路径；更新违反规则或执行失败时保留原图和缓存，报告定位节点、路径与来源 shape。

0.4.0 覆盖全部 29 个 Core 组件，包括 pattern/flags、四种范围约束及 lessThan/lessThanOrEquals；原 v0.1.0 是历史受限基线。数值精度、XPath 正则、datatype、合法路径和参数、图装载及失败传播一并实现。[能力契约](docs/PROFILE.md) 明确时间上下文、资源限额与扩展边界；没有 W3C 认证或外部用户采用的声明。

## 使用价值

MoonTTL 提供解析层，本库补充 MoonBit 同进程的图约束执行和更新预检。例如 Alice/Bob 共享公司，删除公司名称会同时破坏两人的 `(employer name)` 约束；同一提案替换名称可原子通过。这种共享节点关系超出普通逐条 JSON 字段校验。

真实标准样本使用未经修改的 [SEMIC DCAT-AP 3.0.0 base shapes](https://github.com/SEMICeu/DCAT-AP/blob/4470b8ea907b7eb9ec55ab22befd1ecd2210ff32/releases/3.0.0/shacl/dcat-ap-SHACL.ttl)。已有 [欧盟 SHACL 验证服务](https://www.itb.ec.europa.eu/shacl/dcat-ap/upload) 说明实际用途；本仓库案例采用合成数据，不表示该服务完整认证。

## 运行与安装

[GitHub v0.4.0 发行页](https://github.com/wangjiale6036-dotcom/moonshacl/releases/tag/v0.4.0) 提供源码 zip、CLI tar.gz 和校验和。CLI 解压后只需 Node 24，无须 MoonBit、Python 或 npm 安装。

源码构建使用 moonc 0.10.14+7d59c7ec9、Node 24；native 后端还需要 C 编译器。脚本优先使用工作区 .tools/moon，否则使用 PATH 中的 moon。

```sh
node scripts/moon.mjs update
npm ci --ignore-scripts
npm run build
node cli.mjs validate examples/people-shapes.ttl examples/people-data.ttl
node cli.mjs validate examples/core-roadmap/product-code-shapes.ttl examples/core-roadmap/product-code-valid.ttl
node cli.mjs validate fixtures/dcat-ap-3.0.0.ttl examples/dcat-data.ttl
```

```sh
# 删除共享名称会拒绝；删除旧值并加入新值则原子通过
node cli.mjs update examples/people-shapes.ttl examples/people-data.ttl examples/empty.ttl examples/remove-shared-name.ttl
node cli.mjs update examples/people-shapes.ttl examples/people-data.ttl examples/add-shared-name.ttl examples/remove-shared-name.ttl
# 严格审计未执行扩展；显式导入资源；标准 RDF 报告
node cli.mjs audit examples/unsupported-shapes.ttl --strict
node cli.mjs validate examples/imports/root.ttl examples/imports/data.ttl --resources examples/imports/resources.json
node cli.mjs validate examples/people-shapes.ttl examples/people-data.ttl --rdf
```

退出码 0 表示符合/已提交，1 表示违反/拒绝更新，2 表示输入、编译或执行失败。update 返回结果和最终图，不改写输入文件。文本 delta 仅支持 IRI 主语及 IRI/字面量宾语；空白节点更新使用库 API。

## MoonBit API

模块 [wangjiale6036-dotcom/moonshacl@0.4.0](https://mooncakes.io/docs/wangjiale6036-dotcom/moonshacl@0.4.0)，另有 turtle、xpath_regex 包。消费示例见 examples/consumer。

```sh
moon add wangjiale6036-dotcom/moonshacl@0.4.0
```

```moonbit
let shapes = @turtle.parse(shapes_text, scope="shapes-") |> Result::unwrap
let data = @turtle.parse(data_text, scope="data-") |> Result::unwrap
let plan = @moonshacl.compile(shapes) |> Result::unwrap
let report = plan.validate(data) // 在可 raise 的函数内调用，或捕获 ValidationFailure
let session = @moonshacl.Session::new(plan, data)
let preview = session.preview(additions, removals)
let update = session.apply(additions, removals)
```

生产调用须处理解析/编译的 Err 和执行的 ValidationFailure；unwrap 仅用于短示例。additions/removals 为 Array[Triple]。Plan 可复用，validate_node 显式指定 shape/focus 并返回 Result；Report.to_json()/to_graph() 输出 JSON/RDF。失败不是 conforms=false 的别名。

默认 Core 模式对未执行扩展给出 diagnostics；strict=true 拒绝扩展。load_shapes(..., root_iri=Some(root_url)) 通过调用方资源映射合并传递引用并保留根文档身份，不自动联网。JSON resources 映射 IRI 到 Turtle，CLI --resources 映射 IRI 到文件。

混合日期时区默认采用与固定 SHACL 官方用例一致的 XSD 部分序；需要 XPath 动态上下文时使用 compile(..., implicit_timezone=Some(0)) 或 CLI --timezone-minutes 0。两种模式均测试，不能省略其语义区别，详见能力契约。

## 验收

```sh
python -m pip install -r requirements-oracle.txt
npm test
npm run test:roadmap
node scripts/consumer-test.mjs --registry
```

产品核心为纯 MoonBit；N3、rdf-validate-shacl、pySHACL 等仅作独立测试。安装固定依赖后，测试离线使用已固定的标准材料。

固定 98 个 W3C Core 用例全部执行，要求 98 符合预期、零排除、零失败；另有 1,688 个适用 XPath 2.0 的 W3C 正则案例、原创边界和 NFA/捕获执行器对照。每后端 2,000 次确定性更新提案比较 preview/apply 与全量复验，并检查回滚。独立引擎比较保留结果多重性和匿名节点结构，不能只比较 BlankNode 类型。

[验收记录](docs/VALIDATION.md)、[逐组件矩阵](docs/CORE-MATRIX.md)、[公开证据](docs/evidence)、[三个端到端场景](docs/SCENARIOS.md) 和 [10 个 Core 业务案例](examples/core-roadmap) 给出具体方法与边界。CI 在 Linux/Windows 运行 JS、Wasm-GC、native。完整 Core 不表示接受无限资源输入、未定义递归语义或所有扩展。

## 独立贡献与边界

Mooncakes 公开索引及相邻模块调查尚未发现同等 MoonBit SHACL 引擎，调查不穷举未公开项目或全部历史源码。pySHACL、RDF/JS、RDF4J 已有成熟方案，事务、增量、CLI、离线运行不是全球首创。本项目贡献是 MoonBit 内嵌的标准约束、精确比较、正则、读取追踪和事务预检，并复用已有 MoonTTL。详细证据见 [选题依据](docs/RESEARCH.zh-CN.md)。

不含 SHACL-SPARQL/JS/AF、SHACL 1.2、完整推理、数据库持久化或并发隔离。Session 更新仍重建候选图及索引，无性能胜过成熟实现的实测声明。原始代码采用 Apache-2.0；第三方规范测试、Unicode 数据和 DCAT shapes 分别保留授权，见 [THIRD_PARTY.md](THIRD_PARTY.md)。

[项目申报书](PROPOSAL.zh-CN.md) · [阶段与验收安排](docs/CORE-ROADMAP.zh-CN.md) · [发行流程](docs/RELEASING.md)
