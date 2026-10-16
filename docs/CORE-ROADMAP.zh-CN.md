# SHACL 2017 Core 最终范围与阶段验收

更新：2026-10-16。本文是本次申报的开发承诺和验收计划。**最终交付目标是完整 SHACL 2017 Core 处理器；已发布的 v0.1.0 仅为阶段性受限实现，不是最终终点。** v0.2、v0.3、v1.0 均为拟定里程碑，尚未发布。

## 最终交付范围

基线固定为 [W3C 2017-07-20 Recommendation](https://www.w3.org/TR/2017/REC-shacl-20170720/)，实现其 Part A 的 Core 语义：shape/target、属性路径、约束执行、验证过程及标准报告。RDF 图和字面量处理分别依据 [RDF 1.1](https://www.w3.org/TR/rdf11-concepts/) 与所引用的 [SPARQL 1.1 运算语义](https://www.w3.org/TR/sparql11-query/#expressions)。不把“支持若干约束参数”当成完整性证明。

### 29 个 Core 约束组件全部纳入终点

| 类别 | 组件对应参数 | v0.1.0 状态 | 最终验收 |
|---|---|---|---|
| 值类型（3） | class、datatype、nodeKind | 已有实现；datatype 白名单仍有限制 | 补齐 datatype 匹配与所需词法语义 |
| 数量（2） | minCount、maxCount | 已实现，参数限 Int | 消除 32 位参数限制及不合法输入误判 |
| 范围（4） | minExclusive、minInclusive、maxExclusive、maxInclusive | 未实现 | 全部实现，含等于边界、类型错误 |
| 字符串（5） | minLength、maxLength、pattern、languageIn、uniqueLang | pattern 未实现 | pattern 与 flags 纳入必做；其余复核 |
| 属性对（4） | equals、disjoint、lessThan、lessThanOrEquals | 后两项未实现 | 全部实现，逐值对比较及不可比值 |
| 逻辑（4） | not、and、or、xone | 已有实现 | 正反例、嵌套、失败传播 |
| shape（4） | node、property、qualifiedMinCount、qualifiedMaxCount | 已有实现 | 包含 qualifiedValueShape、qualifiedValueShapesDisjoint 语义 |
| 其他（3） | closed、hasValue、in | 已有实现 | 包含 ignoredProperties 及 RDF term 身份 |

`flags`、`ignoredProperties`、`qualifiedValueShape` 等是组件参数，不能另算组件。已有实现也须经过最终语义审查；“22 类已有代码 + 7 类待补”不等于已经完成 22/29 的标准认证。

### 除七个缺失组件外，必须闭环的兼容问题

- **正则：** 按 SPARQL REGEX 引用的 [XPath 2.0 正则语义](https://www.w3.org/TR/2010/REC-xpath-functions-20101214/#regex-syntax)及 flags 实现和对照；覆盖 Unicode 类别、字符类差集、换行/多行等边界。不能只用 JavaScript RegExp 处理简单 ASCII 案例后宣称完成。
- **数值与时间：** 维护 RDF term 身份与比较值的区别；整数/decimal 保留精度，按运算映射处理类型提升、float/double 特殊值、日期时间及时区、不可比值和类型错误。不把所有字面量转成宿主 double 或按字典顺序排序。
- **datatype：** 不再因为参数 IRI 未在当前白名单就拒绝整个 shape。按 datatype IRI 匹配，并落实规范所需的 ill-typed 检查；自定义 datatype 不假装存在其未知词法验证器。日期、HTML 等官方用例要按各自规范语义判定，不能混成“所有 datatype 都有同一词法规则”。
- **路径与列表：** 接受标准允许的 sequence list 额外注解，修复两个 `path-strange` 用例；保留 operator 节点的合法结构检查、列表终止与循环检查。不将所有路径节点一律放宽。
- **合法参数与资源：** 审核参数基数、适用 shape 类型、整数范围、shape 发现和报告字段；数量、长度和 qualified 阈值按各自的 `xsd:integer` 规则处理，加入负数、`2147483648` 及超 64 位值测试，不把当前“非负且 32 位”当成标准限制。较深非递归输入也不直接认定为 profile 外语法；真实资源耗尽单独报告 validation failure，不算通过或数据违反。
- **Core 与扩展：** 提供明确的 Core 验证范围，混有扩展时给出未执行扩展的诊断；严格规则审计可以拒绝扩展，但不能将其冒充已执行的 Core 验证。两类入口的状态和文档必须区分。
- **图装载：** 为 imports/shapesGraph 提供调用方可控的资源映射与传递合并流程，处理循环和缺失资源；缺失时不得以不完整规则返回成功。默认不擅自发起远程请求。合并后的 shapes/data 在验证中保持不变。

`sh:node` 引用 node shape 的现有限制保留，这是规范语法要求。全量与增量路径须执行同一套新增语义；规则补齐不能只进入 CLI。

## 最终不承诺的扩展及实现策略

最终范围不含 SHACL-SPARQL、自定义 SPARQL 约束组件、SHACL-JS/AF、SHACL 1.2、完整 RDFS/OWL 推理服务、图数据库持久化或并发隔离。**pattern/flags、四种范围及两种排序比较不在排除清单中。**

SHACL 2017 未规定递归 shapes 的统一验证结果；本项目继续明确拒绝递归，并报告不能完成验证，不伪造 conforms。对声明但未支持的 entailment regime 报告失败。完整 Core 不等于接受所有扩展、任意资源消耗或提供通用 SPARQL 查询引擎。规范依据见 [递归及失败](https://www.w3.org/TR/2017/REC-shacl-20170720/#validation)、[Core/扩展划分](https://www.w3.org/TR/2017/REC-shacl-20170720/#conformance)。

## 阶段安排和退出条件

下列日期为本项目工程目标（北京时间），不代表组委会公布的截止日期。每阶段以行为验收为退出条件；不通过则继续修复，不把范围退回受限 profile 后宣称最终完成。

| 阶段 | 计划日期 | 交付与退出条件 |
|---|---|---|
| S0：v0.1.0 基线 | 已完成，10 月 10 日 | 保留 76 通过/22 明确拒绝的真实记录，冻结当前包；不得将拒绝改计通过 |
| S1：v0.2 缺失组件 | 10 月 17—21 日 | 实现 pattern/flags、四种范围、两种属性比较及其数值/时间基础；本文三组案例从编译拒绝转为预期通过/违反，新增语义同时用于全量与更新 |
| S2：v0.3 Core 兼容闭环 | 10 月 22—26 日 | datatype、合法路径/参数、列表、报告、图装载及扩展处理完成逐项审计；固定 98 个官方用例全部进入语义验收并符合预期 |
| S3：v1.0 完整 Core 验收 | 10 月 27—30 日 | 29 组件矩阵与通用语义门槛全部通过；Linux/Windows × 三后端、独立引擎、更新等价、公开包安装、文档与案例一致后发布 |
| 修复窗口 | 10 月 31 日起，如需 | 公布剩余差距并继续修复；未达到门槛时不发布“完整 Core 已完成”的结论，也不以时间到期替代验收 |

## 最终验收门槛

1. 对每个 Core 组件给出规范条款、正例、反例、边界/错误用例和对应测试位置；四类显式 target、隐式类 target、七种路径与标准报告单独列矩阵。
2. 当前固定的 98 个 W3C validation 用例达到 **98 符合预期、0 profile-rejected、0 语义失败**；上游新增且适用的 Core 用例纳入版本化清单。不能删除现有 22 个或改写官方预期。
3. 98 个通过仍不足以单独证明完整性。补充 regex、datatype、精度/NaN/时区、空集合、参数边界、列表、合法注解及非递归深嵌套；按规范逐项审计。
4. 至少两个独立实现交叉对照，例如 rdf-validate-shacl 与 pySHACL；核对 conforms 和要求的结果字段/多重性。匿名节点使用结构映射或图同构处理，不能只比较 BlankNode 类型；可选 detail/message 的差异单独说明。引擎与规范有分歧时记录并依据规范判断，不改产品迎合工具。
5. 现有每后端 1,000 次增量/全量等价检查保留，并新增每个补齐组件的添加、删除、回滚、target 变化用例；Core 新功能覆盖 JS、Wasm-GC、Native。
6. 发布前再次安装公开包复验，交付矩阵、案例、原始报告及源提交。缺少任何强制 Core 项均不能以 v1.0 完整 Core 名义验收。

## 附带案例及当前状态

案例文件位于 [examples/core-roadmap](../examples/core-roadmap/)，预期列于 `expectations.json`，使用命名 shape/focus/path 便于复核。

| 案例 | 规则与输入 | 最终预期 | v0.1.0 |
|---|---|---|---|
| 产品编码 | `pattern "^SKU-[0-9]{4}$"`、`flags "i"`；合法编码 `sku-0042` 及缺位 `sku-42` | 合法值通过；缺位产生 PatternConstraintComponent | 编译拒绝 |
| 金额界限 | decimal 下界 0、上界 1000，分别检查 inclusive/exclusive | 等于边界时按开/闭区间准确区分；越界返回对应范围组件 | 编译拒绝 |
| 起止时间及附加词法检查 | dateTime 的 start/end，分别执行 lessThan 与 lessThanOrEquals；另附独立 xsd:date 词法案例 | 先于通过；相等仅非严格比较通过；逆序失败；独立 date 坏词法返回 datatype 违反 | 编译拒绝 |

`xsd:date` 词法检查是为官方用例兼容增加的实现承诺；Core 的 datatype IRI 匹配和 SPARQL 1.1 所需词法检查分别验收，不把自定义 datatype 的未知词法验证当成 Core 要求。

上述是待实现功能的可执行验收材料。运行 `node examples/core-roadmap/verify.mjs --check-current-profile` 核实独立引擎预期与当前版本的拒绝行为；`--require-core` 则要求 MoonSHACL 真正执行并匹配全部预期，当前版本运行应失败。**不能把“预期正确/拒绝正确”当成 MoonSHACL 已实现该功能**。当前已实现的 DCAT 导入、共享节点回滚/替换场景继续见 [SCENARIOS.md](SCENARIOS.md)。
