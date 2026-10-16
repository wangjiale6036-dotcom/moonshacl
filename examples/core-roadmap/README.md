# SHACL 2017 Core 补齐验收案例

这里保存三个场景、十组输入及机器可读预期，用于后续完整 Core 阶段的验收。**这些不是 MoonSHACL 0.1.0 已实现功能的演示。** 当前版本会在形状编译时返回 `unsupported-or-invalid-shapes`，不会生成符合／不符合的数据校验结论；这十例均已确认如此。

语义基线为 [SHACL 2017 Recommendation](https://www.w3.org/TR/2017/REC-shacl-20170720/)。`expectations.json` 列出每例的形状文件、数据文件、`conforms` 和所有预期违规的组件、焦点、路径、命名形状。结果顺序不参与比较。

| 场景 | 输入 | 完整实现应给出的结果 |
| --- | --- | --- |
| 产品编码，`^SKU-[0-9]{4}$`，`flags "i"` | `product-code-valid.ttl`：`sku-0042` | 通过，证明该例的大小写标志生效 |
| 同上 | `product-code-invalid.ttl`：`sku-42` | 1 个 `PatternConstraintComponent` 违规 |
| decimal 金额，业务区间 `0 <= amount < 1000`，另设独立的 `> 0`、`<= 1000` 属性 | `amount-valid-boundaries.ttl`：`0`、`0.01`、`1000` | 通过，覆盖两个包含式边界 |
| 同上 | `amount-invalid-lower.ttl`：金额 `-0.01`，严格下界属性 `0` | `MinInclusiveConstraintComponent`、`MinExclusiveConstraintComponent` 各 1 个 |
| 同上 | `amount-invalid-upper.ttl`：金额 `1000`，包含上界属性 `1000.01` | `MaxExclusiveConstraintComponent`、`MaxInclusiveConstraintComponent` 各 1 个 |
| 开始／结束时间，分别要求 `<` 和 `<=` | `interval-valid-before.ttl`：08:00 早于 09:00 | 通过 |
| 同上 | `interval-invalid-after.ttl`：10:00 晚于 09:00 | `LessThanConstraintComponent`、`LessThanOrEqualsConstraintComponent` 各 1 个 |
| 同上 | `interval-equal-boundary.ttl`：两端均为 09:00 | 仅严格 `<` 违规，`<=` 通过 |
| 独立的 `sh:datatype xsd:date`，与排序检查分开 | `date-datatype-valid.ttl`：`2026-10-16` | 通过 |
| 同上 | `date-datatype-invalid-lexical.ttl`：`not-a-date` | 1 个 `DatatypeConstraintComponent` 违规；输入仍是合法 Turtle |

排序案例采用带显式 `Z` 时区的合法 `xsd:dateTime`，避免把 `xsd:date` 的实现扩展排序当作 Core 互操作证明。`xsd:date` 仅用于独立的词法验证案例。

`xsd:date` 词法验证作为兼容官方用例的实现扩展承诺；Core 的 datatype IRI 匹配与 SPARQL 1.1 所需词法检查另行验收，不因此声称任意自定义 datatype 都有可知的词法验证器。

## 重现检查

从仓库根目录运行：

```sh
npm ci
node examples/core-roadmap/verify.mjs
```

这会使用锁定的独立引擎 `rdf-validate-shacl@0.6.5` 检查预期。2026-10-16 的结果为 **10/10 匹配**，比较字段为 `conforms`、`sourceConstraintComponent`、`focusNode`、`resultPath`、`sourceShape`。

如需复核当前 0.1.0 的明确拒绝行为：

```sh
npm run build
node examples/core-roadmap/verify.mjs --check-current-profile
```

`--check-current-profile` 专门断言现有版本拒绝这些案例；未来实现相应能力后应调整该选项对应的断言，不能继续把编译拒绝算作验收通过。独立引擎预期检查和产品实现验收是两项不同的检查。

未来产品验收运行 `node examples/core-roadmap/verify.mjs --require-core`，要求 MoonSHACL 真正返回 validated 并匹配预期。**该命令在当前 v0.1.0 应返回非零退出码**，不能改成跳过或把编译拒绝计为合格。它仍只验收这十例，不代替 29 组件和官方完整矩阵。

## 覆盖边界

这十例是申报阶段可复现的验收样例，不等同于完整 Core 一致性测试。简单 ASCII 正则和 `i` 标志不能证明完整正则语义；这里的 decimal 数值不能证明任意精度实现正确，也不能用于声称二进制浮点比较足够；日期案例没有覆盖闰年、所有非法日历值、时区混合、非可比值和跨类型比较。后续仍需按规范补齐这些边界及官方测试，并记录不同引擎的分歧。
