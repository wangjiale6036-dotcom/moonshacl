# MoonSHACL 0.4.0 验收记录

基线为 SHACL 2017 Part A；实现范围与配置见 [PROFILE](PROFILE.md)，逐组件正反例见 [CORE-MATRIX](CORE-MATRIX.md)。本轮记录于 2026-10-16；源提交、实际执行时间和平台由 [evidence](evidence) 及 CI 产物记录。历史 v0.1.0 的 76/22/0 保留在旧 tag，不再作为当前门槛。

## 固定验收

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

## 官方用例与完整性

固定 [W3C data-shapes commit 07458e…](https://github.com/w3c/data-shapes/tree/07458ebb1ece6addc664636d70b08444a7b66609/data-shapes-test-suite/tests/core)，98 个 sht:Validate，加引用资源共 113 个。原始字节和官方预期不变，既不删除旧版拒绝项，也不把拒绝计作通过。

比较 conforms、focusNode、sourceShape、sourceConstraintComponent、resultSeverity、value 和结构化 resultPath，要求官方消息出现。结果按多重集合比较，保留逐失败值对及不同约束产生的重复结果。可选的额外消息/detail 不要求所有引擎一致。

29 组件均有端到端正反例；另检查大整数、decimal 精度、直接 binary32 舍入、NaN/INF、日期词法/时区、Unicode、列表、sequence 注解、深层无环输入、shape 发现、扩展诊断、资源闭包、执行失败和匿名节点身份。这些审查补充官方 98 个用例，未声称官方测试穷尽标准或获得 W3C 认证。

## 两个独立引擎

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

## 正则与数据完整性

纯 MoonBit 的解析器、NFA 和捕获执行器不调用宿主正则。固定 Unicode 15.0 类别/块/大小写表；QT3 的 XPath2 适用案例共 1,688 个。其余 XPath3/XSD1.1 或外围函数类型/表达式用例逐项列于 fixtures/regex-w3c-source.json。不是排除 SHACL Core 组件，也没有删掉导致实现失败的适用案例。

verify-fixtures.mjs 校验原文件 SHA-256，并在只读内存文件系统重跑生成器、格式化比对生成表、测试及 manifest。来源、许可与非原创数据边界见 THIRD_PARTY.md。

## 更新与装载

原 400 次基本编辑、600 次共享/逆向/重复路径及 target/subclass 变化保留；新增 1,000 次混合编码、金额、时间和属性对编辑。每次核对 preview、apply、候选与提交图、当前报告，并检查拒绝回滚。全量和缓存共用语义，因此这部分证明更新等价，语义由官方预期与独立引擎另行检查。

imports/shapesGraph 覆盖循环、缺失、根文档回边及冲突；各文档 blank scope 隔离。Turtle adapter 区分显式标签与匿名/集合生成节点，回归覆盖用户标签 genid32 与生成编号碰撞，避免误合并改变验证结论。

Regex 超预算或嵌套 shape 超 256 层会返回 ValidationFailure；即使另一 or 分支通过，也不会吞掉失败；Session 图和缓存不变。路径有独立预算，不把资源失败当作符合或普通数据违反。

## 集成、安装和来源

三个端到端场景见 [SCENARIOS](SCENARIOS.md)，独立 MoonBit consumer 在三个后端测试 API。公开 registry 使用 `node scripts/consumer-test.mjs --registry` 独立安装验收；发布后证据记录在 registry-consumer.json。

源码 zip 与 CLI tar.gz 由干净 Git HEAD 构建，SOURCE_REVISION / manifest.json / SHA256SUMS 记录源版本和哈希。release-smoke.mjs 执行六项下载包布局/隔离运行检查。CLI 不需要 MoonBit、Python 或 npm；源码包保留测试、资料和许可。CI 默认测试源码，release/manual 另检查公开 registry，避免发布前检查尚不存在的新版本。

公开源码统计排除 tests、生成 fixtures/Unicode 表、第三方数据、demo、bridge、JavaScript 宿主和依赖。本轮核心 3,998 物理行、3,597 去空白/注释行、2,758 再去纯分隔符行；复算以 source-audit.json 为准，不代替赛事认定。没有并发隔离、百万级图性能或外部用户采用的测试结论。
