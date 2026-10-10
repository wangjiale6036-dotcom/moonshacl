# MoonSHACL 选题依据（2026-10-10，开发前冻结）

## 结论

选择 **MoonSHACL：MoonBit 原生 RDF 图契约编译与事务校验库**。独立贡献定位于 MoonBit RDF 管线的图约束层：读取标准 shapes graph、编译并检查规则、在同一进程内验证 data graph、对更新执行原子预检。不是 JSON 字段校验器、RDF 解析器、图数据库或现有验证器的调用包装。

这是有可验证用途的生态补缺项目，不是已获得用户采用证明的产品。不得把没有检索命中写成“无人做过”，不得承诺赛事审核通过。

## 需求证据

- 欧盟 [SEMIC 官方验证服务](https://www.itb.ec.europa.eu/shacl/dcat-ap/upload) 用 SHACL 校验 RDF 的结构、关系和属性，提供 REST/SOAP 接口。这证明图约束有实际用途，不证明该服务需要 MoonBit。
- [DCAT-AP 3.0.0 官方 shapes](https://github.com/SEMICeu/DCAT-AP/blob/master/releases/3.0.0/shacl/dcat-ap-SHACL.ttl) 包含 cardinality、class、nodeKind、datatype、property、targetClass。选取该未经修改的文件验证兼容性；其他 shapes、词表、推理和服务配置不因此自动得到支持。
- [MoonTTL 0.3.0](https://mooncakes.io/docs/thy1016/moonttl@0.3.0) 已有 RDF 解析与序列化，[jsonld 0.1.1](https://mooncakes.io/docs/thy1016/jsonld@0.1.1) 已有 JSON-LD 算法。项目复用解析层，新增数据图约束执行层。现有库存在不等于其作者已提出 SHACL 需求。
- 库级验收场景：导入 RDF 后检查对象引用、类约束和多跳路径；更新导致共享对象失效时定位所有受影响 focus nodes；失败时保持原图和校验缓存不变。

## 现成方案与采用边界

| 方案 | 已有能力 | MoonSHACL 的边界 |
|---|---|---|
| [pySHACL](https://github.com/RDFLib/pySHACL) | Python、Core/SPARQL、推理、CLI | Python 项目优先用现成方案；本项目不声称替代它 |
| [shacl-engine](https://github.com/rdf-ext/shacl-engine) | RDF/JS、浏览器、CLI、SPARQL 插件、trace/coverage | 浏览器、离线、解释报告均不能算首创 |
| [rdf-validate-shacl](https://github.com/zazuko/rdf-validate-shacl) | JavaScript RDF/JS 验证器 | 作为独立语义对照，不复制引擎 |
| [RDF4J ShaclSail](https://rdf4j.org/documentation/programming/shacl/) | 事务校验、根据更新减少验证工作、JVM 存储集成 | 增量和事务也不是全球创新；本项目提供 MoonBit 内嵌 API |
| [sparq](https://github.com/sparq-org/sparq) | Rust RDF/SPARQL 引擎，文档列出 SHACL/Wasm | Wasm 或免 Python 不是充分差异 |
| Mooncakes 的 MoonTTL/jsonld | 解析、序列化、JSON-LD 转换 | 复用而非重做 |
| Mooncakes 的数据契约及专用图验证库 | JSON/CSV 字段规则、专用图结构规则 | 不等同于执行 RDF terms、SHACL targets/paths、标准 shapes 的通用图约束层 |

仅在下游要求 MoonBit 同进程嵌入、保留 RDF term 身份并跨后端复用时，原生实现的部署边界有价值。允许外部进程、REST 或 JavaScript 集成的现有系统可以继续使用成熟方案。本项目不能把“换语言”单独包装成应用价值。

## 公开查重范围

当前 Mooncakes 2,909 条模块元数据、12 组子包检索、23 个相邻模块共 3,244 个文本文件静态扫描，尚未找到 SHACL 引擎。检索不是所有未发布仓库的证明。9 月的 2,639 个 Git 索引文件（Windows 大小写折叠后 2,637 项）、16,081 条历史版本元数据也没有 SHACL 相关命中；原来的 9 月报告并没有专项检查 SHACL。

CLI、网页、多个格式或“能跑”本身不足以证明项目独立贡献。本项目先确定图约束执行层的范围和可执行验收条件，再开发；调查结论不覆盖赛事内部尚未公开的申报材料。

## 必须通过的验收

1. 使用 MoonTTL 解析真实 Turtle，不另写残缺 Turtle 解析器。
2. 完整执行声明支持的规则；不支持的约束、递归 shape、错误参数及路径必须在编译阶段报错，不能忽略后返回通过。
3. 标准结果字段可追踪至 sourceShape、constraint component、focus node、path/value；严格区分数据不符合和验证无法完成。
4. 对官方测试比较 conformance 与规范要求的结果字段，并明确列出因能力边界未执行的测试。
5. 更新预检覆盖添加、删除、零结果读取、多跳/逆向路径、共享节点、类型继承和 target 集合变化；与全量复验结果一致。
6. 使用未经修改的官方 DCAT-AP base shapes 做端到端演示和独立引擎对照，不把它等同于完整 DCAT-AP 服务认证。
7. JS、Wasm-GC、native 验证同一核心。不得凭无对照的计时声称更快。

基线采用 [2017 SHACL Recommendation](https://www.w3.org/TR/shacl/)。[2026-10-08 SHACL 1.2 Core](https://www.w3.org/TR/2026/WD-shacl12-core-20261008/) 是工作草案，不据此宣称支持新标准。本项目明确声明支持的受限 profile；全部 Core 组件通过前不得称完整 SHACL Core 处理器。
