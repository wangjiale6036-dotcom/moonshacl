# MoonSHACL 项目申报书

公开发行基线为 v0.4.0。本材料对应 10 月 23 日完成本地复验、于 2026 年 11 月 10 日提交到主仓库的补验源码。两轮 Session 优化、浏览器交互和真实目录流程均以本次源码提交为准。

## 一、项目名称与申报人

项目名称：MoonSHACL——MoonBit 原生 SHACL 2017 Core 图契约与事务校验库。

申报人 GitHub ID：wangjiale6036-dotcom。个人姓名及联系方式见参赛者提交给组委会的申报附件。

参赛类型：2026 年 10 月黑客松，新项目申报，个人参赛；申报工作版：基于 v0.4.0 的 2026-10-23 第二轮性能优化版，尚未正式发行；原始代码许可证：Apache-2.0。

本项目以完整 SHACL 2017 Core 为交付范围。v0.1.0 的受限 profile 是已冻结的早期基线，不是本次最终范围；pattern/flags、四种范围和两种排序约束均已进入实际实现和验收。

## 二、项目简介

MoonSHACL 为 MoonBit 应用提供 RDF 数据图的规则编译、跨节点关系检查、标准报告和更新预检。读取 SHACL shapes，沿属性路径检查数据；更新违反规则或执行失败时保留原图和缓存，报告指出问题节点、路径和来源规则。

图模型、Core 约束、精确比较、XPath 正则、依赖追踪和事务预检由 MoonBit 实现，同一核心支持 JavaScript、Wasm-GC、Native。Turtle 解析复用 MoonTTL；Node.js 仅处理 CLI 文件及参数。独立的 RDF/JS、pySHACL 引擎只用于测试，不参与产品验证。

## 三、方向、通用性与独立价值

方向为语义数据处理和 MoonBit 基础工具库。标准 RDF 规则可以复用于数据目录、知识图谱和关联元数据，不绑定某种业务实体。数据能够解析不代表节点关系满足要求：两个人共享一家公司，删除公司名称会同时破坏两条多跳关系，逐条 JSON 字段校验不能直接覆盖这种共享图结构。

欧盟 SEMIC 使用 SHACL 验证 DCAT-AP 数据目录，本项目以其未经修改的 3.0.0 base shapes 和合成数据验证导入及更新流程，未宣称外部用户采用或完整官方服务认证。

独立贡献是 MoonBit 同进程的 targets/paths/标准约束执行、精确数值和纯 MoonBit 正则、读取依赖缓存、可追踪报告与原子更新预检。MoonTTL/jsonld 提供解析或转换，专用图规则、JSON/CSV 契约不等同于通用 RDF Core 接口。2026-10-10 对 Mooncakes 2,909 条元数据、12 组子包检索及 23 个相邻模块的审查尚未发现同等 MoonBit SHACL 引擎；不穷举未公开项目。

pySHACL、RDF/JS、RDF4J 已有成熟能力，SHACL、事务、增量或离线运行不是本项目全球首创。项目面向 MoonBit 原生嵌入和多后端复用需求。查重范围、需求与已有方案对照见[选题依据][research]。

## 四、完整使用场景

1. **目录导入。** 输入 RDF 元数据和 DCAT-AP base shapes，解析、编译、验证后输出 JSON/RDF 报告；删除 distribution 的 accessURL 产生 MinCount 违反，拒绝更新且原图不变。
2. **共享对象编辑。** 输入原图和增删三元组；删除共享公司名称定位 Alice/Bob，复用 Carol 的结果，示例 checked=2、reused=1。原子替换名称成功，导出图重读仍通过；失败时图和缓存均不变。
3. **发布前规则门禁。** 编译并执行所有 Core 约束；混有未执行扩展时返回 diagnostics，严格模式拒绝扩展。缺失导入资源、错误规则和执行资源耗尽均明确失败，不把“未完成验证”当成通过。

以上流程都有可运行案例和机器断言，见[场景验收][scenarios]。原始案例输入为公开规则与合成数据；新增真实公开目录应用见下文，仍无外部采用证明。

**10 月 21 日评优增强：** 提供由真实 MoonBit 引擎驱动的浏览器交互实验室，可观察提案图、失败回滚、原子替换和原始报告；接入 data.europa.eu 的 Kaunas 空气质量元数据，冻结 341 条源语句并投影出 31 条导入语句，公开来源、CC0 许可与 SHA。官方 base 对查询切片及投影分别返回 26/20 项问题，应用 profile 单独通过；人为删除访问入口被拒绝，使用同源下载链接进行本地原子替换后导出读回通过。不是官方认证、上游修改或外部用户采用。

**10 月 21 日第一轮优化：** 删除/添加提案与三类读取依赖采用哈希集合，避免批量删除和失效检查的重复线性扫描；真实变化由提案与原图索引推导；预检不构建会被丢弃的候选缓存，新求值且已经隔离的结果直接返回。目标仍重新计算，复用缓存结果仍深拷贝，失败/异常仍保留原图与缓存。

**10 月 23 日第二轮优化：** 利用保留三元组已有的唯一性，避免候选图重复建立全图去重集合。新增三元组按输入顺序取首个相等代表，再以原图 SPO 索引及删除集合判断是否追加；内部 `Graph::from_unique` 重新建立全部索引，公开 `Graph::new` 的任意输入去重行为不变。保留删除后添加顺序、RDF 相等语义、依赖读取、目标重算、结果隔离与回滚，没有停用 Reader 或改走全量 fallback。正确性与端到端耗时分别验收，不以少复验节点数替代性能证据。

## 五、最终范围、阶段结果与案例

**最终范围固定为 W3C 2017-07-20 Recommendation Part A：全部 29 个 Core 约束组件、四类显式及隐式类 targets、七种路径、验证过程、标准报告与失败传播。** 已实现 pattern/flags、min/max inclusive/exclusive、lessThan/lessThanOrEquals，消除旧版 datatype 白名单与 32 位阈值限制，补齐合法 sequence 注解、资源合并及扩展诊断。

| 阶段 | 原工程安排 | 本次交付 |
|---|---|---|
| S0 基线 | 10 月 10 日 | 保留 v0.1.0 的 76 通过/22 明确拒绝/0 语义失败记录和旧发行包 |
| S1 补齐组件 | 原定 10 月 17—21 日 | 七个缺失组件、精确比较和 XPath 正则已实现；10 个业务案例实际执行通过 |
| S2 通用兼容 | 原定 10 月 22—26 日 | datatype、路径/参数、图装载、扩展及报告已审查；固定 98 个 Core 用例全部符合预期，零排除 |
| S3 完整验收 | 原定 10 月 27—30 日 | v0.4.0 原发行已验收三后端、两个独立引擎、增量回归、源码/CLI 和公开包安装；本轮优化另有本地复验，尚未发行 |

原计划日期是工程目标，不是组委会截止日期；S1/S2 的 v0.2/v0.3 只是计划里程碑，没有虚构中间发行。最终状态和可复算证据见[验收记录][validation]及[29 组件矩阵][matrix]。

附带案例已经执行：① 商品编码 ^SKU-[0-9]{4}$ 配合 i 标志，sku-0042 通过、sku-42 产生 Pattern 违反；② decimal 金额 0/1000 的四种开闭边界分别产生正确范围结果；③ start/end 比较覆盖先于、相等、逆序，相等仅违反严格 lessThan；④ 独立 date 词法案例验证合法日期与 not-a-date。共 10 组输入，文件和机器预期见[Core 案例][cases]。

精确范围包括任意精度 integer/decimal、IEEE float/double 提升、NaN/INF、Unicode 码点及 XPath2 正则。日期默认采用与固定 SHACL 官方用例一致的 XSD 混合时区部分序；另提供显式 XPath 隐式时区上下文参数，两种模式均验证并披露差异。未知自定义 datatype 按 IRI 匹配，不宣称知道其词法规则。

不包括 SHACL-SPARQL/JS/AF、SHACL 1.2、完整推理、数据库持久化或并发隔离。递归 shapes 按标准未规定统一语义采取明确失败；深层 shape、路径和正则有资源预算，耗尽在编译或执行阶段明确失败。具体值和调用契约见[能力说明][profile]。这些不是排除某个 Core 组件。

## 六、项目性质与原创说明

这是依据公开规范新实现的 MoonBit 项目，非整库移植、非外部验证器包装。原创贡献在实现与工程集成，不将标准、测试资料、Unicode 表或已有算法申报为全球首创。开发、测试和文档使用 AI 辅助；申报人应按赛事要求核对最终申报材料。

## 七、参考来源及许可证

移植来源：不适用。实现依据 W3C SHACL / SPARQL / XPath 规范；复用 MoonBit Core、MoonTTL（Apache-2.0）。W3C data-shapes、QT3 测试、Unicode 15.0 数据及 SEMIC DCAT-AP shapes 分别保留原许可和署名。RDF/JS 与 pySHACL 仅用于独立测试。固定版本、原字节哈希、生成复现和许可见[第三方来源][sources]。

## 八、仓库、测试与交付

公开基线：GitHub [wangjiale6036-dotcom/moonshacl][repo]、[提交历史][commits]、[v0.4.0 发行页][release]与[Mooncakes 0.4.0][package]。本仓库 11 月 10 日的补验提交包含新增源码与复验材料，发行页和 Mooncakes 0.4.0 对应 10 月 16 日的原发行。

原发行包括库、CLI、公开包、完整源码/第三方许可、案例、独立消费项目、自动化测试、CI 和申报材料。本轮 `node scripts/verify.mjs` 单次完整执行通过：JS、Wasm-GC、native 各通过 1,756 个测试块，保留第一轮 4 块回归并新增 3 块，包含 400 轮混合更新与索引检查；每后端固定 98 个官方 Core 用例及既有 2,000 次更新提案比较均通过。另有 1,688 个适用 XPath2 官方正则案例。bridge 38 项、CLI 18 项、3 项比较器自检、3 个端到端场景和三后端独立消费通过。142 个场景 × 2 独立引擎共 284 次比较，276 次匹配、7 个已知差异、1 个已知错误，零意外失败，不能算作全部一致。另完成公开数据 41 项与分发演示 12 类检查；命令及证据见[本轮验收归档][optimization]，第一轮分段验收作为历史单独保留。

源码统计排除测试、生成表、第三方数据、演示与基准、宿主层和依赖；本轮核心 4,043 物理行、3,629 去空白/注释行、2,785 再去纯分隔符行，见[本轮源码统计][sourceaudit]。各后端测试、原发行 CI 与安装证据见[验收记录][validation]，原发行记录不能替代新源码的复验。测试通过不代表 W3C 认证、外部采用或性能领先；提交时间及代码量的赛事认定由组委会决定。

新增交付见[交互演示][demo]、[真实数据与 41 项复验][realdata]和[性能报告][performance]。第二轮于 2026-10-23 在本机 JS release 重跑 100/1,000/5,000 人的 12 种负载，每项 5 次预热、25 次采样。上一轮剩余的 1,000/5,000 人全部受影响场景，预检中位数分别由 11.974→9.765 ms、67.104→53.186 ms，下降 18.4%、20.7%；本轮对应哈希全量中位数为 10.663、56.545 ms，全量/预检比值为 1.09×、1.06×。这两个场景的 `reused=0`，改进来自候选图构造等实现开销减少，不是复用了未受影响结果。前后分时测量，未作随机交错配对，数字仍受调度、GC、JIT 和系统负载影响。

第一轮加入的哈希删除全量重建校验继续作为主要比较基线，本轮操作与计时边界保持不变。正式运行的全量/预检中位数比值为 **0.97–3.00×**；仍有 **1/12** 场景（100 人全部受影响）预检约慢 2.8%。相对首次优化前，原 4 个慢场景的累计延迟下降为 33.0%、42.5%、65.0%、72.0%，包含两轮改动，不等同于第二轮单独收益。旧线性基线、[首次优化前报告][before]、[第一轮报告][round1]、各轮完整样本、环境与源码指纹均保留；不以复验数量代替加速比，不声称全部场景更快或性能胜过成熟引擎。

正式测量后，以相同源码、编译模块、环境和每项 5 次预热/25 次采样，再独立执行完整 12 场景。该[确认测量][confirmation]为 **1.05–2.86×、0/12 较慢**；1,000/5,000 人全部受影响的全量/预检比值分别为 1.05×、1.18×。首次完整运行始终保留为正式报告，确认结果另存，不选择更好的一轮替代正式数据。100 人全部受影响由正式 0.97× 变为确认 1.13×，体现运行波动；两次分时运行不是统计置信区间，也不支持普遍更快的结论。

[repo]: https://github.com/wangjiale6036-dotcom/moonshacl
[commits]: https://github.com/wangjiale6036-dotcom/moonshacl/commits/main/
[release]: https://github.com/wangjiale6036-dotcom/moonshacl/releases/tag/v0.4.0
[package]: https://mooncakes.io/docs/wangjiale6036-dotcom/moonshacl@0.4.0
[research]: docs/RESEARCH.zh-CN.md
[scenarios]: docs/SCENARIOS.md
[profile]: docs/PROFILE.md
[validation]: docs/VALIDATION.md
[matrix]: docs/CORE-MATRIX.md
[cases]: https://github.com/wangjiale6036-dotcom/moonshacl/tree/main/examples/core-roadmap
[sources]: https://github.com/wangjiale6036-dotcom/moonshacl/blob/main/THIRD_PARTY.md
[evidence]: https://github.com/wangjiale6036-dotcom/moonshacl/tree/main/docs/evidence
[demo]: docs/DEMO.zh-CN.md
[realdata]: docs/REAL-DATA.zh-CN.md
[performance]: docs/PERFORMANCE.zh-CN.md
[before]: docs/PERFORMANCE-BEFORE.zh-CN.md
[round1]: docs/PERFORMANCE-ROUND1.zh-CN.md
[confirmation]: docs/PERFORMANCE-CONFIRMATION.zh-CN.md
[optimization]: docs/evidence/optimization-verification.json
[sourceaudit]: docs/evidence/source-audit-optimization.json
