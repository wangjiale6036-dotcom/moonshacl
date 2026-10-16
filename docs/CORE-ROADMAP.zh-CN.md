# SHACL 2017 Core 最终范围与阶段验收

发行编号说明：固定 MoonBit 工具链要求包版本为 `0.x.y`，因此本次完整 Core 发行使用 v0.4.0；版本编号不缩减下述功能范围。

更新：2026-10-16。最终范围是 [SHACL 2017 Recommendation Part A](https://www.w3.org/TR/2017/REC-shacl-20170720/) 的全部 Core 能力。v0.1.0 是历史受限基线，本轮将阶段计划合并实施为 v0.4.0；没有把受限 profile 当作最终终点，也没有虚构 v0.2/v0.3 的独立发行。

## 最终范围

覆盖 29 个 Core 组件、四类显式及隐式类 targets、七种属性路径、验证过程、标准报告及失败传播。值类型3、数量2、范围4、字符串5、属性对4、逻辑4、shape4、其他3，逐条规范与正反例见 [CORE-MATRIX.md](CORE-MATRIX.md)。flags、ignoredProperties 等是附属参数，不另计组件。

七个旧缺项 pattern、minExclusive、minInclusive、maxExclusive、maxInclusive、lessThan、lessThanOrEquals 已进入同一 MoonBit 全量/增量执行路径。并完成以下通用行为：

- XPath2/SPARQL 正则与 i/m/s/x、Unicode 类别/块、类差集、捕获及反向引用；无引用时使用 NFA。
- BigInt integer/decimal 精度、binary32/64 直接舍入与类型提升、NaN/INF、日期及显式时间上下文。
- 任意 datatype IRI 匹配和已知词法检查，取消 datatype 白名单；自定义 datatype 不假造词法验证器。
- 任意精度有符号 xsd:integer 阈值，合法 sequence 注解、列表与 shape 参数语法，保留 operator 单 triple 要求。
- Core 扩展 diagnostics 与 strict 拒绝模式，未支持 entailment、递归或资源耗尽明确失败。
- 调用方控制的 imports/shapesGraph 资源闭包、缺失及循环处理、根文档身份、不可变输入和失败回滚。

准确契约见 [PROFILE.md](PROFILE.md)。日期默认 XSD 混合时区部分序符合固定 SHACL 官方用例；显式 implicit_timezone 支持 XPath 动态上下文。两种行为都已实现和测试，官方用例通过不代表所有 SPARQL 宿主时间上下文相同。

## 阶段安排与结果

原日期为工程目标，不是组委会截止日期。后续阶段已按用户要求提前连续实施；中间版本号只是规划标识。

| 阶段 | 原计划 | 退出条件与交付 |
|---|---|---|
| S0 基线 | 10 月 10 日 | 冻结 v0.1.0，保留 76/22/0 真实记录和发行包 |
| S1 缺失组件 | 10 月 17—21 日 | 七个组件、精确比较与 XPath 正则实现；十组业务输入由编译拒绝转为正确通过/违反 |
| S2 通用兼容 | 10 月 22—26 日 | datatype、合法路径/参数、图装载、扩展、报告完成审查；官方 98/98，零排除 |
| S3 完整验收 | 10 月 27—30 日 | 29 组件矩阵、三后端、双独立引擎、更新等价、公开包和干净安装验收；以 v0.4.0 交付 |
| 后续维护 | 发布后 | 保持固定回归与语义契约，新问题修复提升版本，不改写旧 tag 或旧测试预期 |

本轮执行记录、CI 和安装结果见 [VALIDATION.md](VALIDATION.md) 与 [evidence](evidence)。版本完成状态以实际测试和发行证据为准，不能只凭安排表认定完成。

## 验收门槛

1. 每个 Core 组件都有规范位置、可执行正反例和边界证据；targets、路径、报告和失败独立审查。
2. 固定 98 个官方用例要求 98 符合预期、0 profile-rejected、0 语义失败；保留所有旧 22 项，不改写预期。
3. 额外覆盖 XPath 正则、精度/NaN/时区、datatype、空集合、大整数/负数参数、列表及合法注解、深层无环输入和资源失败。
4. rdf-validate-shacl 与 pySHACL 对相同输入交叉对照，报告字段、匿名节点结构及结果多重性保留；已知引擎错误单列，不能算一致，任何未解释差异让测试失败。
5. 每后端 2,000 次确定性编辑提案比较 preview、apply、最终图和全量复验；执行失败与规则违反均检查回滚。
6. 本地 workspace、公开 registry、源码 zip 和无需开发依赖的 CLI 分别验收；记录源提交及 SHA-256。

98 个用例全过不是单独的完整性证明，更不等于 W3C 认证。实现仍有明示的资源预算；没有任何 Core 组件因预算而被整体排除。

## 已执行案例

文件与预期在 [examples/core-roadmap](../examples/core-roadmap/)。

| 场景 | 规则和输入 | 结果 |
|---|---|---|
| 商品编码 | ^SKU-[0-9]{4}$、flags i；sku-0042 / sku-42 | 前者通过，后者 1 个 Pattern 违反 |
| 金额边界 | decimal 0/1000 的四种开闭区间 | 含端点与排除端点准确区分；上下界反例各 2 个对应组件结果 |
| 起止时间 | 显式时区 dateTime，start/end 的 < 与 <= | 先于通过，逆序两个违反，相等只违反严格 < |
| 附加日期词法 | date 的 2026-10-16 / not-a-date | 前者通过，后者 Datatype 违反 |

```sh
npm run build
npm run test:roadmap
```

该命令使用 --require-core，要求产品实际返回 validated 并匹配全部十例。旧 --check-current-profile 仅用于检出 v0.1.0 的历史行为，不属于本版验收。

## 范围外

SHACL-SPARQL、自定义 SPARQL 约束组件、JS/AF、SHACL 1.2、完整 RDFS/OWL 推理、持久化和并发隔离不属于本次范围。递归 shapes 在 2017 中未有统一验证语义，采用明确失败策略。pattern/flags、所有范围和排序比较始终在最终范围内。
