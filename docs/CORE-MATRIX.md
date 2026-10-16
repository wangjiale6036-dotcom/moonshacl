# SHACL 2017 Core 实现与验收矩阵

基线：[2017 Recommendation](https://www.w3.org/TR/2017/REC-shacl-20170720/)，Part A §2—4。全部 29 组件的可执行正/反例集中于 [core_matrix_wbtest.mbt](../src/turtle/core_matrix_wbtest.mbt)，每例从 Turtle 输入经过真实编译和验证，断言结果组件与数量。以下表中的边界用例与固定官方用例共同验收，不以组件名称出现代替行为验证。

| 组件 | 规范条款 | 正例 / 反例 | 额外边界证据 |
|---|---|---|---|
| Class | 4.1.1 | 类型 C / 类型 D | node/class-*；subclass 更新依赖 |
| Datatype | 4.1.2 | string / integer | 坏词法、自定义 IRI、派生整数上下限 |
| NodeKind | 4.1.3 | IRI / literal | node/property nodeKind 官方用例；六种参数种类 |
| MinCount | 4.2.1 | 1 值 / 0 值 | 负阈值、超 64 位阈值、空读取失效 |
| MaxCount | 4.2.2 | 1 值 / 2 值 | RDF 集合去重；任意精度参数 |
| MinExclusive | 4.3.1 | 1 > 0 / 0 > 0 | 精确 decimal、NaN、坏词法 |
| MinInclusive | 4.3.2 | 0 >= 0 / -1 >= 0 | 日期、混合时区、显式 XPath 上下文 |
| MaxExclusive | 4.3.3 | 0 < 1 / 1 < 1 | float/double 提升、INF/溢出 |
| MaxInclusive | 4.3.4 | 1 <= 1 / 2 <= 1 | binary32 舍入、binary64 下溢 |
| MinLength | 4.4.1 | ab / a | Unicode 码点、blank node、大阈值 |
| MaxLength | 4.4.2 | ab / abc | IRI 的 str、负阈值 |
| Pattern | 4.4.3 | ab 匹配 ^AB$ + i / ab3 | 1,688 个 W3C XPath2 正则案例、i/m/s/x、反向引用、差集 |
| LanguageIn | 4.4.4 | en-US / fr | 大小写、基本语言范围、无语言标记 |
| UniqueLang | 4.4.5 | en+fr / en+EN | 每种重复语言 1 结果；布尔 term 的 true/1 区别 |
| Equals | 4.5.1 | {1}={1} / {1}!={2} | 对称差产生 2 结果；term 身份保留 |
| Disjoint | 4.5.2 | {1} 与 {2} / 两侧 {1} | 相同词法与不同 datatype |
| LessThan | 4.5.3 | 1<2 / 1<1 | 每个失败值对独立结果；空参考集合 |
| LessThanOrEquals | 4.5.4 | 1<=1 / 2<=1 | 精确小数、不可比类型、日期相等边界 |
| Not | 4.6.1 | 字符串不符合 integer / integer | 多个 not 参数；嵌套失败传播 |
| And | 4.6.2 | literal 且长度2 / 长度1 | 空列表、子 shape 失败 |
| Or | 4.6.3 | string 或 integer / boolean | 所有分支执行失败传播，不能被另一通过分支吞掉 |
| Xone | 4.6.4 | 仅 Literal / 同时 Literal+string | 重复 shape 成员及 0 个匹配 |
| Node | 4.7.1 | 子 shape 接受 IRI / literal | node/property 类型限制、detail、递归失败 |
| Property | 4.7.2 | 子节点 q 存在 / 缺少 q | 直接转发子 MinCount 结果，不伪造 Property 组件结果 |
| QualifiedMinCount | 4.7.3 | 2 个 integer / 1 个 | sibling exclusion、无 count 的 sibling、增量依赖 |
| QualifiedMaxCount | 4.7.3 | 1 个 integer / 2 个 | qualified disjoint、超大阈值 |
| Closed | 4.8.1 | 允许 q / 出现 r | ignoredProperties、每个出边、覆盖 resultPath |
| HasValue | 4.8.2 | 含 1 / 仅 2 | 01 与 1 不合并；空集合 |
| In | 4.8.3 | 1 属于(1 2) / 3 | 空列表、坏列表、RDF term 身份 |

## 通用语义

| 要求 | 验收位置 |
|---|---|
| 四显式 targets、隐式类 targets、target 联集去重 | 官方 targets/*；compiler_core_wbtest；core_test |
| 七类路径、反向序列、循环数据终止、去重 | 官方 path/*；core_test；integration_wbtest |
| sequence 注解合法，operator 附加 triple 不合法 | 官方 path-strange 两例；compiler_core_wbtest |
| RDF list 终止、成员资源类型、rdf:nil 不得有 first/rest | compiler_core_wbtest |
| severity、message、deactivation、共享报告 | 官方 misc/*、validation-reports/shared；core_test |
| 输出所有必需结果字段与多重性 | official_wbtest；双引擎图同构比较；property-pair 集成测试 |
| datatype 精确词法和比较值/term 身份分离 | scalar_values_wbtest；core_test |
| 数值与时区上下文 | scalar_values_wbtest；bridge-test；PROFILE 中披露默认与显式模式 |
| 深层无环 shape / 路径及资源失败 | compiler_core_wbtest；bridge-test；failure_wbtest |
| Core 扩展诊断、strict、未支持 entailment | compiler_core_wbtest；bridge-test |
| imports/shapesGraph 传递闭包、循环、缺失、根身份 | core_integration_wbtest；bridge-test；examples/imports |
| 失败不提交、不污染缓存、preview 无副作用 | failure_wbtest；core_test；consumer_test |
| 新功能增量/全量一致 | 每后端新增 1,000 次混合编辑，加原 1,000 次；core_integration_wbtest |
| 第三方输入原字节、生成内容可复现、许可 | verify-fixtures.mjs；fixtures 元数据；THIRD_PARTY |

限制不隐藏：递归 shapes 按规范未定义语义明确失败；嵌套 shape 执行 256 层、路径和正则有显式资源预算；SPARQL/JS/AF 等扩展不执行。它们与删除某个必需 Core 组件不同。数字和最终各平台执行结果见 [验收记录](VALIDATION.md)。
