# MoonSHACL

**2026-11-10 补验源码**基于 v0.4.0，包含两轮 Session 优化、浏览器交互和真实目录流程。10 月 23 日的本地测试和性能记录保存在仓库中。此次提交晚于十月验收截止日，v0.4.0 标签仍对应 10 月 16 日的公开发行。

补验入口见[评优证据索引](docs/AWARD-DEMO.zh-CN.md)，含源码位置和复验命令。

[![CI](https://github.com/wangjiale6036-dotcom/moonshacl/actions/workflows/ci.yml/badge.svg)](https://github.com/wangjiale6036-dotcom/moonshacl/actions/workflows/ci.yml)

**MoonBit 原生 SHACL 2017 Core 图契约与事务校验库。** 读取 RDF shapes graph，检查跨节点关系和属性路径；更新违反规则或执行失败时保留原图和缓存，报告定位节点、路径与来源 shape。

0.4.0 覆盖全部 29 个 Core 组件，包括 pattern/flags、四种范围约束及 lessThan/lessThanOrEquals；原 v0.1.0 是历史受限基线。数值精度、XPath 正则、datatype、合法路径和参数、图装载及失败传播一并实现。[能力契约](docs/PROFILE.md) 明确时间上下文、资源限额与扩展边界；没有 W3C 认证或外部用户采用的声明。

## 使用价值

MoonTTL 提供解析层，本库补充 MoonBit 同进程的图约束执行和更新预检。例如 Alice/Bob 共享公司，删除公司名称会同时破坏两人的 `(employer name)` 约束；同一提案替换名称可原子通过。这种共享节点关系超出普通逐条 JSON 字段校验。

标准案例使用未经修改的 [SEMIC DCAT-AP 3.0.0 base shapes](https://github.com/SEMICeu/DCAT-AP/blob/4470b8ea907b7eb9ec55ab22befd1ecd2210ff32/releases/3.0.0/shacl/dcat-ap-SHACL.ttl)。共享对象与原始 DCAT 示例使用合成数据；新增[公开真实目录应用](docs/REAL-DATA.zh-CN.md)保留 data.europa.eu 来源、查询、快照哈希及许可，并区分应用规则与官方规则的结果。这些均不表示外部采用或完整官方认证。

## 交互实验室与评优演示

**在错误更新落地之前，看到受影响的关系，并把它拦住。** 浏览器演示直接调用 MoonBit 引擎：删除共享名称会同时影响 Alice/Bob，更新被拒绝；原子替换名称则可提交。第二个场景使用公开空气质量目录元数据，展示来源、错误注入、拒绝与本地修复。

```sh
npm run demo:build
npm run test:demo
npm run demo:serve
```

终端给出本地地址。静态产物在 `dist/demo/`，校验在浏览器 Worker 内完成，无远程验证服务。详见[演示说明](docs/DEMO.zh-CN.md)与[两分钟讲解及证据索引](docs/AWARD-DEMO.zh-CN.md)。

真实数据复验运行 `npm run test:real-data`；性能复算运行 `npm run benchmark`。性能基准直接复用 MoonBit Session，记录全量/缓存路径、图重建成本和内存采样；`checked/reused` 只表示校验任务数，不能当作速度倍数。[性能方法与实测](docs/PERFORMANCE.zh-CN.md)明确负载、适用条件和限制。

10 月 23 日第二轮优化利用保留三元组已有的唯一性，避免候选图构造时重复建立全图去重集合；新增三元组仍按输入顺序去重，全部索引仍重新建立。正式测量中，上一轮剩余的 1,000/5,000 人全部受影响场景，预检中位数从 **11.974→9.765 ms、67.104→53.186 ms**，分别下降 **18.4%、20.7%**。本轮同次运行的哈希全量/预检比值为 **0.97–3.00×**；仍有 1/12 场景（100 人全部受影响）预检略慢，不能声称全部负载更快。全部受影响场景的 `reused=0`，该收益来自构图等实现开销减少。前后分时测量，未作随机交错配对；[首次优化前](docs/PERFORMANCE-BEFORE.zh-CN.md)、[第一轮报告](docs/PERFORMANCE-ROUND1.zh-CN.md)与完整样本均保留。

相同源码和编译模块的[独立完整复测](docs/PERFORMANCE-CONFIRMATION.zh-CN.md)为 **1.05–2.86×、0/12 较慢**，两个人数较多的全部受影响场景再次超过 1×。复测单独归档，不覆盖正式结果；100 人全部受影响的比值从正式 0.97× 变为复测 1.13×，体现接近成本相当时的运行波动。

## 运行与安装

[GitHub v0.4.0 发行页](https://github.com/wangjiale6036-dotcom/moonshacl/releases/tag/v0.4.0) 提供原发行的源码 zip、CLI tar.gz 和校验和，不包含本轮优化。原发行 CLI 解压后只需 Node 24，无须 MoonBit、Python 或 npm 安装；体验本轮优化须从当前工作区构建。

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

第二轮优化工作版的 `node scripts/verify.mjs` 单次完整执行通过：JS、Wasm-GC、native **各 1,756 个测试块通过**，保留第一轮 4 块回归并新增 3 块，包含 400 轮混合更新与索引检查；每后端既有 2,000 次更新提案对照继续保留。bridge 38 项、CLI 18 项、比较器 3 项自检、3 个端到端场景和三后端独立消费通过。142 个场景 × 2 独立引擎共 284 次比较，其中 276 次匹配、7 个已知差异、1 个已知错误，零意外失败，不能算作全部一致。另完成公开数据 41 项及分发演示 12 类检查。详见[本轮验收归档](docs/evidence/optimization-verification.json)；第一轮分段执行记录另行保留。

[验收记录](docs/VALIDATION.md)、[逐组件矩阵](docs/CORE-MATRIX.md)、[公开证据](docs/evidence)、[三个端到端场景](docs/SCENARIOS.md) 和 [10 个 Core 业务案例](examples/core-roadmap) 给出具体方法与边界。已发布基线的 CI 在 Linux/Windows 运行 JS、Wasm-GC、native；本轮工作区的结果属于本地复验。完整 Core 不表示接受无限资源输入、未定义递归语义或所有扩展。

## 独立贡献与边界

Mooncakes 公开索引及相邻模块调查尚未发现同等 MoonBit SHACL 引擎，调查不穷举未公开项目或全部历史源码。pySHACL、RDF/JS、RDF4J 已有成熟方案，事务、增量、CLI、离线运行不是全球首创。本项目贡献是 MoonBit 内嵌的标准约束、精确比较、正则、读取追踪和事务预检，并复用已有 MoonTTL。详细证据见 [选题依据](docs/RESEARCH.zh-CN.md)。

不含 SHACL-SPARQL/JS/AF、SHACL 1.2、完整推理、数据库持久化或并发隔离。Session 更新仍重建候选图及索引，无性能胜过成熟实现的实测声明。原始代码采用 Apache-2.0；第三方规范测试、Unicode 数据和 DCAT shapes 分别保留授权，见 [THIRD_PARTY.md](THIRD_PARTY.md)。

[项目申报书](PROPOSAL.zh-CN.md) · [阶段与验收安排](docs/CORE-ROADMAP.zh-CN.md) · [发行流程](docs/RELEASING.md)
