# MoonSHACL 项目申报书

## 一、项目名称与申报人

项目名称：MoonSHACL——MoonBit 原生 RDF 图契约编译与事务校验库。

申报人 GitHub ID：wangjiale6036-dotcom。个人姓名及联系方式见参赛者提交给组委会的申报附件。

参赛类型：2026 年 10 月黑客松，新项目申报，个人参赛；版本：v0.1.0；许可证：Apache-2.0。

2026-10-16 范围补正：当前 v0.1.0 为阶段性成果；最终申报交付为完整 SHACL 2017 Core，计划 v1.0，不以受限 profile 作为终点。

## 二、项目简介

MoonSHACL 为 MoonBit 应用提供 RDF 数据图的规则编译、跨节点关系检查和更新预检。它读取 SHACL shapes，沿属性路径检查数据；更新违反规则时保留原图，并报告出错节点、路径及来源规则。

图模型、规则执行、读取依赖缓存及报告均由 MoonBit 实现，同一核心支持 JavaScript、Wasm-GC、Native。Turtle 解析复用 MoonTTL，Node.js 仅承担 CLI 文件和参数适配，外部验证器只用于测试。已完成可运行库、CLI、三个集成场景及独立消费示例。

## 三、项目方向、通用性与独立价值

方向为语义数据处理和 MoonBit 基础工具库。规则以标准 RDF 图表达，可复用于数据目录、知识图谱和关联元数据，不绑定某一种业务实体。

实际问题是：数据能够解析，不代表节点间关系满足要求。例如两个人共享一家公司，删除公司名称会同时破坏两人的多跳约束，逐条 JSON 字段校验不能直接覆盖这种图关系。欧盟 SEMIC 已使用 SHACL 校验 DCAT-AP 数据目录，说明需求有现实用途；本项目采用其公开 base shapes 验证实现。

独立贡献是 MoonBit 内嵌的 targets/paths/约束执行层、支持范围编译检查、标准报告和原子更新预检。MoonTTL/jsonld 提供解析或转换，专用图规则及 JSON/CSV 契约不等同于该通用 RDF 约束接口。2026-10-10 对 Mooncakes 2,909 条元数据、12 组子包检索及 23 个相邻模块的代码检查尚未发现同等 SHACL 引擎；此结论不覆盖未公开项目。

pySHACL、RDF/JS 验证器和 RDF4J 已有成熟能力，事务或增量校验不是本项目首创。项目面向需要 MoonBit 同进程嵌入及跨后端复用的开发者；允许外部服务或需要完整 SHACL 的系统可继续使用成熟方案。[需求、查重范围和对照][research]见仓库。

## 四、三个完整的预期使用场景

1. **数据目录导入。** MoonBit 目录工具输入 RDF 元数据和 DCAT-AP base shapes，解析、编译并检查后输出 JSON/RDF 报告。固定正例须通过；删除 distribution 的 accessURL 须报告 MinCount 违反并拒绝更新，原图保持不变。
2. **共享对象编辑。** 元数据编辑器输入原图及增删三元组，预检受影响节点。删除共享公司名称须定位 Alice/Bob 两人、复用 Carol 的结果；同一提案替换名称须成功，导出图重新读入后仍通过校验。失败时图与缓存均保留。
3. **发布管线的规则检查。** 维护者输入待使用的 shapes，先编译检查，再验证数据。v0.1.0 对尚未实现的 pattern 等返回明确错误；最终版本必须执行全部 Core 规则，并区分数据违反、输入/执行失败和未执行扩展，不能忽略 Core 约束后给出“通过”。

上述三个场景的 v0.1.0 行为均已有自建集成演示；场景 3 的完整 Core 执行属于后续阶段。输入为公开规则与合成数据，暂无外部用户采用证明。[运行方法与验收产物][scenarios]见仓库。

## 五、核心功能及验收边界

v0.1.0 已实现四类标准 targets、七种路径形式、类与 datatype、基数、字符串/语言、集合、逻辑组合、嵌套、closed、equals/disjoint 和 qualified 数量约束；支持 JSON/N-Triples 报告及 preview/apply API。

直接验收：共享名称删除报告两个失败节点，`checked=2, reused=1`，CLI 示例图仍为 11 triples；原子替换后旧值消失、新值存在，读回校验通过。不支持的 shapes 必须在执行前拒绝。独立调用模块在三个后端验证修复提交、预览无副作用和失败回滚。

**最终范围：完整 SHACL 2017 Core（2017 Recommendation Part A），覆盖全部 29 个约束组件、targets、路径及报告语义。** 当前缺失的 pattern/flags、min/max inclusive/exclusive、lessThan/lessThanOrEquals 均为必做；同时补齐 datatype、合法路径/参数、图装载和报告兼容问题，不仅增加组件名称。

| 阶段 | 工程计划 | 交付及验收 |
|---|---|---|
| v0.1.0 | 已完成 | 保留受限实现与 76/22/0 的真实基线 |
| v0.2 | 10 月 17—21 日 | 补齐七个缺失组件及比较基础；编码、金额、起止时间案例达到预期 |
| v0.3 | 10 月 22—26 日 | 完成 Core 兼容审计；现有 98 个官方用例全部符合语义预期，零 profile 拒绝 |
| v1.0 | 10 月 27—30 日 | 29 组件与通用语义矩阵全部通过，完成跨后端/独立对照、更新回归和公开包验收 |

以上是开发目标，非组委会截止日期；不达验收条件则继续修复，不降级为受限终点。98 个用例全过也不单独等同完整性，仍须逐条规范审计及边界测试。最终不包含 SHACL-SPARQL/JS/AF、自定义 SPARQL 组件、SHACL 1.2、完整推理服务或数据库并发/持久化；递归按规范未定义语义采取明确失败策略。

附带案例：① `^SKU-[0-9]{4}$` 与忽略大小写 flags，合法编码通过、缺位编码产生 pattern 违反；② decimal 金额 0/1000 的四种开闭边界逐项验收；③ start/end 的严格与非严格 dateTime 比较，覆盖先于、相等、逆序，另附独立 xsd:date 词法案例作为附加兼容承诺。案例预期已作为验收材料，当前版本仍拒绝这些规则，不能写成已实现。完整文件、阶段退出条件及实现边界分别见 [Core 最终范围与案例][core-roadmap]、[v0.1.0 能力契约][profile]。

## 六、项目性质与原创说明

依据公开规范新实现的 MoonBit 项目，非整库移植、非外部验证引擎包装。原创贡献为 MoonBit 实现和工程集成，不将 RDF/SHACL 标准、事务校验或已有算法申报为全球首创。开发、测试和文档使用 AI 辅助。

## 七、参考项目、来源与许可证

移植来源：不适用。实现依据 W3C SHACL Recommendation；复用 MoonBit Core、MoonTTL（Apache-2.0）。W3C 测试保留其软件与文档许可，SEMIC DCAT-AP shapes 保留 CC BY 4.0；MIT 授权的 RDF/JS 工具用于独立测试。固定版本、原文件哈希和完整许可证见[第三方来源][sources]。

## 八、GitHub 仓库与完成情况

仓库：[wangjiale6036-dotcom/moonshacl][repo]；[源码提交历史][commits]；[发行页][release]。

[Mooncakes 0.1.0](https://mooncakes.io/docs/wangjiale6036-dotcom/moonshacl@0.1.0) 已发布并通过独立重新安装验证；Linux/Windows CI 已通过。

仓库已具备 MVP、测试、CI、示例和维护文档。提交覆盖完整核心基线、源码统计、CI、CLI 修复、场景验收、独立消费、公开证据、发行构建、安装验证及申报材料；没有回填日期、空提交或重复提交，赛期有效提交口径由组委会认定。

核心库排除测试、生成 fixtures、demo、bridge、宿主代码、空白和注释后为 2,020 行，进一步排除纯分隔符行为 1,539 行；附复算脚本。三后端各 21 个测试块通过，W3C 98 个用例为 76 通过、22 因 profile 明确拒绝、0 已执行语义失败；另有 14 个独立引擎场景、每后端 1,000 次更新与全量复验比较。统计不代替实际价值，亦不代表完整标准认证。[验收方法及证据][validation]见仓库。

[repo]: https://github.com/wangjiale6036-dotcom/moonshacl
[commits]: https://github.com/wangjiale6036-dotcom/moonshacl/commits/main/
[release]: https://github.com/wangjiale6036-dotcom/moonshacl/releases/tag/v0.1.0
[research]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/docs/RESEARCH.zh-CN.md
[scenarios]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/docs/SCENARIOS.md
[profile]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/docs/PROFILE.md
[core-roadmap]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/docs/CORE-ROADMAP.zh-CN.md
[sources]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/THIRD_PARTY.md
[validation]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/docs/VALIDATION.md
