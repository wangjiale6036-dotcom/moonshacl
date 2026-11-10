# MoonSHACL 验收记录：优化工作版与发行基线

## 2026-10-23 第二轮性能优化工作版复验

本节对应基于 v0.4.0 的未发布第二轮工作版。Session 候选图构造利用保留三元组已有的唯一性，省去重复建立全图去重集合；新增三元组仍按输入顺序处理首个相等代表，并用原图 SPO 索引与删除集合决定是否追加。内部 `Graph::from_unique` 重新建立所有索引，公开 `Graph::new` 仍去重任意输入。依赖读取、目标重算、第一轮缓存隔离与失败回滚均保留，没有关闭 Reader 或改用全量 fallback。本轮源码于 2026 年 11 月 10 日补交至主仓库，以下保留 10 月本地复验的原始范围。完整执行与归档见 [optimization-verification.json](evidence/optimization-verification.json)。

| 本轮本地检查 | 结果 |
|---|---|
| 总体验收命令 | `node scripts/verify.mjs` 单次完整执行通过，无沙箱读取中断 |
| JS / Wasm-GC / native | 各 1,756 个测试块通过；各含固定 W3C Core 98/98、零排除、零失败 |
| 第二轮新增边界回归 | 每后端 3 块：400 轮混合更新的图与各索引等价，目标增减后的预检/提交依赖保持，闭包前沿与类型读取在非提交预检后保持 |
| 已有更新回归 | 第一轮 4 个边界测试块及每后端 2,000 次 preview/apply 与全量复验提案全部保留并通过 |
| JSON bridge / CLI | 38 / 18 项通过 |
| 双独立引擎 | 142 场景 × 2 引擎，共 284 次比较：276 匹配、7 已知差异、1 已知错误，零意外失败；比较器 3 项自检通过 |
| 集成消费 | 3 个端到端场景、JS / Wasm-GC / native 独立消费均通过，属于 source-workspace 方式，不表示已发布新包 |
| 公开数据流程 | [2026-10-23 复验 41 项通过](evidence/real-data.json)，原始 341 条与投影 31 条分开检查 |
| 分发演示 | 重建引擎与静态材料后 12/12 类检查通过；浏览器及线上交互状态另见交付记录 |
| 正式性能基准 | [12 场景、5 次预热、每项 25 次采样、11 项操作](evidence/benchmark.json)，全部前后语义检查通过；哈希全量/预检比值 0.97–3.00×，1/12 场景仍略慢 |
| 独立确认测量 | [相同源码、模块和采样配置重跑完整 12 场景](evidence/benchmark-round2-confirmation.json)，全部前后语义检查通过；1.05–2.86×、0/12 较慢，单独归档，不替代首次正式结果 |
| 核心源码统计 | [4,043 / 3,629 / 2,785 行](evidence/source-audit-optimization.json)：物理行 / 去空白注释 / 再去纯分隔符；排除测试、生成数据、演示、基准与宿主层 |

总体验收之后仅澄清新增测试名称及注释，并重新执行格式检查与三个新增测试块；实现源码没有再变化。1,756 是测试块数量，块内的官方用例、更新提案、400 轮图检查及正则组合不与块数相加。`audit/2026-10-10/` 是既有输出目录名，实际执行日期以证据的 `verifiedAt` 为准。

第二轮正式测量中，上一轮剩余的 1,000/5,000 人全部受影响场景，预检中位数为 9.765/53.186 ms，较上一轮下降 18.4%/20.7%；同次哈希全量/预检为 1.09×/1.06×。独立确认分别为 1.05×/1.18×。正式运行的 100 人全部受影响场景仍为 0.97×，确认运行变为 1.13×，说明接近 1× 的小差异存在运行波动；不择优替换正式结果，也不据此声称统计置信或普遍更快。all-people 的 `reused=0`，改进归于候选图构造等实现开销减少。方法、原始样本及边界见[正式报告](PERFORMANCE.zh-CN.md)和[独立复测](PERFORMANCE-CONFIRMATION.zh-CN.md)。

## 2026-10-21 第一轮性能优化复验（历史记录）

本节保留第一轮未发布工作版的结果：新增哈希删除/差集推导、依赖失效索引，以及不保留候选缓存的 preview 路径，不包含第二轮候选图去重优化。完整执行与归档见 [optimization-round1-verification.json](evidence/optimization-round1-verification.json)。

| 本轮本地检查 | 结果 |
|---|---|
| JS / Wasm-GC / native | 各 1,753 个测试块通过；各含固定 W3C Core 98/98、零排除、零失败 |
| 新增优化边界回归 | 每后端 4 个测试块通过：重复及等价三元组/删除再添加顺序，共享/逆向/closed 空读失效，缓存及新求值结果的可变数组隔离，部分求值后异常与拒绝原子性 |
| 既有增量回归 | 每后端 2,000 次提案比较 preview/apply 与全量复验，图及缓存回滚通过 |
| JSON bridge / CLI | 38 / 18 项通过 |
| 双独立引擎 | 142 个场景 × 2 引擎；保留 8 个已知差异/异常，零未解释失败；比较器 3 项自检通过 |
| 集成消费 | 3 个端到端场景、JS / Wasm-GC / native 独立消费均通过；公开 registry 的历史验收不冒充工作区新包发布 |
| 公开数据流程 | 当时 41 项通过，原始 341 条与投影 31 条分开检查；[当前数据归档](evidence/real-data.json)已由第二轮复验更新 |
| 分发演示 | 重建后的引擎与静态材料通过 12/12 类检查；浏览器及线上交互状态另见交付记录，不由脚本通过推断 |
| 正式性能基准 | [第一轮 12 场景、5 次预热、每项 25 次采样](evidence/benchmark-before-round2.json)，每场景前后语义检查通过；新增哈希全量基线 / 缓存比值 0.94–2.23×，2 场景仍较慢 |
| 核心源码统计 | [第一轮 4,023 / 3,613 / 2,773 行](evidence/source-audit-round1.json)：物理行 / 去空白注释 / 再去纯分隔符；排除测试、生成数据、演示、基准与宿主层 |

整套验收先在 Python 沙箱读取权限处受阻，随后单独提升权限重跑独立对照通过，其余检查分别执行通过。这是分段完成的验收，不记为一次 `npm test` 全流程通过。1,753 是测试块数量；官方用例、更新提案及正则组合在块内执行，不与测试块数相加。

第一轮中，原先较慢的 4 个场景的缓存预检中位数下降 34.4%、29.5%、43.2%、64.7%；具体场景、毫秒值和前后运行限制见 [第一轮性能报告](PERFORMANCE-ROUND1.zh-CN.md)。当时 1,000/5,000 人全部受影响仍略慢于新增哈希全量基线。保留 [首次优化前报告](PERFORMANCE-BEFORE.zh-CN.md)及[首次优化前原始样本](evidence/benchmark-before-optimization.json)，不混用新旧基线比值。

## 2026-10-21 首轮展示增强复验（优化前历史记录）

本节保留首轮、尚未修改内核时的展示验收记录，当时使用 v0.4.0 内核新增浏览器交互演示、公开目录数据应用和性能基准。它与下面 2026-10-16 原发行记录都不能替代上文优化后源码的复验，也不表示新增展示已在远端 CI 运行或随旧发行包发布。

| 本次本地检查 | 结果 |
|---|---|
| JS 内核回归 / W3C Core | 1,749 个测试块通过；其中官方 98/98 |
| 格式 / JSON bridge | `moon fmt --check` 通过；38/38 |
| 分发演示验收 | 12/12 类验收检查，包括真实引擎、失败保留原图、原子修复及后续编辑 |
| 浏览器交互 | 实际操作确认共享节点删除拒绝、含引号名称替换、再次编辑；公开目录删除拒绝及修复提交；窄屏布局检查 |
| 公开数据流程 | 当时 41 项检查通过，原始 341 条与投影 31 条分开记录；[当前归档](evidence/real-data.json)已由优化后复验更新 |
| 性能基准 | [优化前 12 场景、每项 25 次采样](evidence/benchmark-before-optimization.json)，每场景前后语义检查通过；当时相对线性删除全量基线为 0.55–1.82×，4 场景更慢 |
| 新增 benchmark 包 | JS / Wasm-GC / native 的 `moon check` 均通过；耗时报告仅测 JS |

完整执行命令、数据边界和演示顺序分别见 [交互演示](DEMO.zh-CN.md)、[真实数据应用](REAL-DATA.zh-CN.md)、[性能报告](PERFORMANCE.zh-CN.md) 与 [评优证据索引](AWARD-DEMO.zh-CN.md)。本次检查不将不同层级的测试计数相加，也不以包编译检查替代全后端运行测试。

## 2026-10-16 原发行基线

基线为 SHACL 2017 Part A；实现范围与配置见 [PROFILE](PROFILE.md)，逐组件正反例见 [CORE-MATRIX](CORE-MATRIX.md)。本轮记录于 2026-10-16；源提交、实际执行时间和平台由 [evidence](evidence) 及 CI 产物记录。历史 v0.1.0 的 76/22/0 保留在旧 tag，不再作为当前门槛。

### 原发行固定验收

| 检查 | 结果 / 门槛 |
|---|---|
| fmt / check | 通过，编译无警告 |
| JS / Wasm-GC / native | 每后端 1,749 个测试块通过 |
| W3C Core | 每后端 98/98，零排除、零失败 |
| 官方 XPath2 正则 | 146 个 matches + 1,542 个兼容回归，三后端通过 |
| 原创正则测试 | 7 组，含 NFA/捕获执行器 13,068 个确定性组合对照 |
| 增量与全量 | 每后端 2,000 次编辑提案一致，检查 preview、apply、最终图及缓存回滚 |
| JSON / CLI | 38 / 18 项通过 |
| 独立实现 | 142 个场景 × 2 引擎，284 次比较 |
| 独立比较结果 | 276 次一致、7 个精确记录差异、1 个精确记录异常；0 未解释失败 |
| 匿名节点比较器自检 | 3 项：拒绝错配来源节点和丢失重复结果，接受一致重命名 |
| Core 业务案例 | 10/10，产品实际执行并匹配预期 |
| 第三方字节与生成复现 | 113 个 Core 资源、DCAT、Unicode 输入/表、QT3 输入/生成测试全部核对 |

1,749 是 MoonBit 测试块数，包含单独的正则测试；98 个 Core fixtures 在一个块内运行，29 个组件正反例在一个矩阵块内运行，不能把这些数字简单相加为独立测试总数。每后端 2,000 次提案也属于若干测试块中的循环检查。

```sh
node scripts/moon.mjs update
npm ci --ignore-scripts
python -m pip install -r requirements-oracle.txt
npm test
npm run test:roadmap
```

固定 Moon 0.1.20260920 / moonc 0.10.14+7d59c7ec9、Node 24；Python 仅用于独立测试。首次安装依赖后，标准测试无需联网。Linux/Windows CI 均运行 JS、Wasm-GC、native，相同规则用于本地与 CI。

### 官方用例与完整性

固定 [W3C data-shapes commit 07458e…](https://github.com/w3c/data-shapes/tree/07458ebb1ece6addc664636d70b08444a7b66609/data-shapes-test-suite/tests/core)，98 个 sht:Validate，加引用资源共 113 个。原始字节和官方预期不变，既不删除旧版拒绝项，也不把拒绝计作通过。

比较 conforms、focusNode、sourceShape、sourceConstraintComponent、resultSeverity、value 和结构化 resultPath，要求官方消息出现。结果按多重集合比较，保留逐失败值对及不同约束产生的重复结果。可选的额外消息/detail 不要求所有引擎一致。

29 组件均有端到端正反例；另检查大整数、decimal 精度、直接 binary32 舍入、NaN/INF、日期词法/时区、Unicode、列表、sequence 注解、深层无环输入、shape 发现、扩展诊断、资源闭包、执行失败和匿名节点身份。这些审查补充官方 98 个用例，未声称官方测试穷尽标准或获得 W3C 认证。

### 两个独立引擎

固定 rdf-validate-shacl 0.6.5、pySHACL 0.30.1 / RDFLib 7.6.0。默认 oracle 脚本运行 98 个官方用例和 44 个补充场景。分别独立解析输入，对输入图和必需结果投影作 RDF 图同构，保持匿名 sourceShape/focus/value 的关联和每条结果身份；路径按结构比较。JSON 与本产品 RDF 报告也互相核对。

所有 142 个产品结果须符合固定预期。下列参考引擎分歧采用精确断言，既不改产品迎合它，也不计为“一致”；任何新差异均让脚本失败：

| 参考引擎 | 已记录行为 |
|---|---|
| RDF/JS | 超 binary64 整数及精确 decimal 比较丢精度（2 例） |
| RDF/JS | xsd:float 的 INF 处理差异（1 例） |
| RDF/JS | languageIn 大写范围未按不区分大小写匹配（1 例） |
| RDF/JS | 未要求 SHACL shape 类型就创建隐式类 target（1 例） |
| pySHACL | 正则 s 标志未应用（1 例） |
| pySHACL | uniqueLang 的 "1" boolean 被当作 RDF term true（1 例，固定官方用例） |
| pySHACL | count-free qualified sibling 抛异常（1 例） |

原始输入、预期摘要、实际结果及依据在 oracle.json。另保留 shacl-engine 1.1.0 对空数据图跳过显式 literal target 的观察，它不计入两主引擎的一致次数。

日期混合时区有公开的上下文区别：默认 XSD 部分序匹配锁定 SHACL 用例；显式 implicitTimezoneMinutes 支持 XPath 动态上下文。这两种模式各有边界测试，不把它们混成单一“任意宿主完全一致”承诺。

### 正则与数据完整性

纯 MoonBit 的解析器、NFA 和捕获执行器不调用宿主正则。固定 Unicode 15.0 类别/块/大小写表；QT3 的 XPath2 适用案例共 1,688 个。其余 XPath3/XSD1.1 或外围函数类型/表达式用例逐项列于 fixtures/regex-w3c-source.json。不是排除 SHACL Core 组件，也没有删掉导致实现失败的适用案例。

verify-fixtures.mjs 校验原文件 SHA-256，并在只读内存文件系统重跑生成器、格式化比对生成表、测试及 manifest。来源、许可与非原创数据边界见 THIRD_PARTY.md。

### 更新与装载

原 400 次基本编辑、600 次共享/逆向/重复路径及 target/subclass 变化保留；新增 1,000 次混合编码、金额、时间和属性对编辑。每次核对 preview、apply、候选与提交图、当前报告，并检查拒绝回滚。全量和缓存共用语义，因此这部分证明更新等价，语义由官方预期与独立引擎另行检查。

imports/shapesGraph 覆盖循环、缺失、根文档回边及冲突；各文档 blank scope 隔离。Turtle adapter 区分显式标签与匿名/集合生成节点，回归覆盖用户标签 genid32 与生成编号碰撞，避免误合并改变验证结论。

Regex 超预算或嵌套 shape 超 256 层会返回 ValidationFailure；即使另一 or 分支通过，也不会吞掉失败；Session 图和缓存不变。路径有独立预算，不把资源失败当作符合或普通数据违反。

### 原发行集成、安装和来源

三个端到端场景见 [SCENARIOS](SCENARIOS.md)，独立 MoonBit consumer 在三个后端测试 API。原发行的公开 Mooncakes v0.4.0 已发布，并通过 `node scripts/consumer-test.mjs --registry` 从包库独立安装，三后端均通过；包来源提交和 SHA-256 记录在 [registry-consumer.json](evidence/registry-consumer.json)。当时发布后的证据补充仅改变文档，源码与发布来源一致；这一历史结论不适用于本页上方已修改 Session 内核的优化工作版。

原发行的 [GitHub CI](https://github.com/wangjiale6036-dotcom/moonshacl/actions/runs/38893450042) 已在 Windows/Linux 完成全部测试和打包检查，[机器记录](evidence/ci.json) 保留源提交及两个任务结果。11 月补验提交的检查结果以该提交对应的 GitHub Actions 为准。

源码 zip 与 CLI tar.gz 由干净 Git HEAD 构建，SOURCE_REVISION / manifest.json / SHA256SUMS 记录源版本和哈希。release-smoke.mjs 执行六项下载包布局/隔离运行检查。CLI 不需要 MoonBit、Python 或 npm；源码包保留测试、资料和许可。CI 默认测试源码，release/manual 另检查公开 registry，避免发布前检查尚不存在的新版本。

原发行源码统计排除 tests、生成 fixtures/Unicode 表、第三方数据、demo、bridge、JavaScript 宿主和依赖。当时核心 3,998 物理行、3,597 去空白/注释行、2,758 再去纯分隔符行；历史统计见 source-audit.json，新工作版以本页上方 source-audit-optimization.json 为准，均不代替赛事认定。没有并发隔离、百万级图性能或外部用户采用的测试结论。
