# 真实数据应用：Kaunas 空气质量目录导入

这个案例读取 **data.europa.eu 中的真实公开 RDF 元数据**，验证导入、错误更新拒绝、原子替换和导出文件读回。数据集为立陶宛开放数据目录的 [Air quality in Kaunas](https://data.europa.eu/data/datasets/https-data-gov-lt-datasets-1948-?locale=en)，源目录地址为 [data.gov.lt/datasets/1948](https://data.gov.lt/datasets/1948/)。它描述空气质量传感器监测数据，包含 CSV、JSON、JSONL、RDF 四个分发条目。本案例只处理目录元数据，不下载空气质量观测值。

这是开发者自行完成的真实输入集成案例，不是外部用户采用、官方认证或对完整上游目录的质量结论。

## 运行

在仓库根目录完成现有构建后执行：

```sh
npm ci --ignore-scripts
npm run build
node scripts/real-data.mjs
```

验证默认完全离线，只读固定快照；自动校验 SHA-256、提取规则和浏览器 fixture 一致性。默认命令（与 `npm run test:real-data` 相同）将本次机器证据写入 Git 忽略的 `artifacts/real-data.json`，不会覆盖已存档的 [real-data.json](evidence/real-data.json)。它还将本地变更后的图保存为已忽略的 `artifacts/real-catalogue/committed.nt`，随后真正从该文件读回验证。因此 CI 和日常测试不会因 Node 版本或编译产物摘要差异改写受跟踪的证据文件，也不会将运行时导出图混入演示的源数据目录。

需要明确更新供评审的证据存档时，运行：

```sh
node scripts/real-data.mjs --record
```

此命令执行同样的 41 项检查，并将本次结果写入 `docs/evidence/real-data.json`，供审查差异后归档。它仍不刷新官方快照。

如果只需从现有快照重新生成导入文件和浏览器 fixture：

```sh
node scripts/real-data.mjs --write-fixture
```

这条命令也不联网，不重新抓取或替换快照；它只重写源快照的导入派生文件，证据默认仍写入 `artifacts/real-data.json`，仅同时传入 `--record` 才更新证据存档。刷新官方数据应作为独立变更重新核验来源、SHA、条目关系和期望结果，不能把可变线上响应当作固定回归测试。

## 来源与可复现性

| 文件 | 用途 |
| --- | --- |
| [source-response.ttl](../examples/real-catalogue/source-response.ttl) | 官方 SPARQL 的原始 UTF-8 响应，15,608 字节、341 条三元组；原样保存 |
| [source-query.rq](../examples/real-catalogue/source-query.rq) | 可重放的 `CONSTRUCT` 查询，读取指定数据集及四个分发条目的直接属性 |
| [SOURCES.json](../examples/real-catalogue/SOURCES.json) | 来源 URL、抓取时间、响应头、许可、SHA-256、提取规则和预期结果 |
| [data.ttl](../examples/real-catalogue/data.ttl) | 31 条语句的导入投影，所有 RDF 语句都可在原始响应找到 |
| [application-shapes.ttl](../examples/real-catalogue/application-shapes.ttl) | 本案例明确声明的本地目录导入规则 |
| [scenario.json](../examples/real-catalogue/scenario.json) | 浏览器用的小型自包含场景；数据、规则和更新提案由同一验证脚本生成 |

抓取时间和响应摘要固定在清单中。门户[官方文档](https://data.europa.eu/data/sparql?locale=en)提供 SPARQL 入口；查询只访问公开图，不需要账户。原始响应是**查询切片**：没有递归获取所链接的受控词表、联系人、发布机构和质量测量节点的描述，不能称为完整目录备份。

导入投影保留数据集的 `rdf:type`、标题、描述及四个 `dcat:distribution` 关系，保留分发的类型、访问 URL、下载 URL、格式、许可和媒体类型。文本只保留英文或无语言标签的值。其余语句仅被排除；未补类型、改字面量、改 IRI 或添加合成条目。脚本对投影的每条语句做原图包含性检查，并验证未导入联系方式。

### 许可

[data.europa.eu 法律声明](https://data.europa.eu/en/legal-notice)说明门户元数据采用 **CC0 1.0**。本仓库冻结的是这类元数据，清单保留来源和许可链接。

四个分发在原始 RDF 中另行声明观测数据采用 [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.lt)。这与元数据的 CC0 是不同层次；本案例没有再分发观测数据，也没有将观测数据称为 CC0。

## 两套规则分别报告

| 输入与规则 | 结果 | 含义 |
| --- | --- | --- |
| 原始 341 条查询响应 × 未修改的 DCAT-AP 3.0.0 base | `conforms=false`，26 个结果 | 保留原始验证结果，没有为通过测试而补造类型 |
| 31 条投影 × 同一官方 base | `conforms=false`，20 个结果 | 投影只包含导入所需字段，链接资源类型仍未随附 |
| 原始响应 × 本地目录导入 profile | 通过 | 本地规则允许外部 URL / 词表 IRI 不携带类型描述 |
| 31 条投影 × 同一本地 profile | 通过 | 交互演示从这份真实输入开始 |

26 / 20 个结果全部是 `ClassConstraintComponent`，与该切片缺失链接资源的类型声明有关。例如 URL 没有伴随 `rdf:type rdfs:Resource`，格式、许可和媒体类型 IRI 也没有伴随其分类声明。MoonSHACL 直接检查所提供的图，不联网填充词表，不暗中推理补全。本结果**不能据此推出完整上游目录不合规**，也没有掩盖官方规则结果而只展示通过的本地规则。

本地 profile 的要求是：数据集有非空标题和描述；至少关联一个有 `dcat:Distribution` 类型的分发条目；每个关联分发至少有一个 HTTP(S) 访问 IRI、格式 IRI 和许可 IRI；若提供下载 URL，也必须是 HTTP(S) IRI。嵌套 `sh:node` 检查让一个分发条目的问题同时反映到所属数据集。

## 演示流程

1. **读取和验证。** 校验固定源 SHA，从原始语句提取 31 条投影，同时输出官方 base 与本地 profile 的结果。
2. **明确的人为错误注入。** 构造删除 CSV 分发 `accessURL` 的提案。原始数据本来有该字段；没有暗示官方数据缺失访问入口。
3. **拒绝与回滚。** 实际执行 MoonSHACL `operation: "update"`。结果分别定位 CSV 分发的 `MinCount` 和所属数据集的 `Node` 约束；返回图与导入图逐三元组相等。
4. **修正提案并原子提交。** 在同一次更新中删除旧 `accessURL`、加入同一 CSV 分发原本就声明的 `downloadURL` 作为新访问入口。新值是 `https://get.data.gov.lt/datasets/gov/kaunas/oras/Oras/:format/csv`，取自冻结快照。这是**本地访问策略调整**，没有虚构下载地址，也没有声称源门户已做此修改。
5. **导出和读回。** 验证确实只删除一条、增加一条，而不是重复添加原值的空操作；把最终 RDF 写入文件，再从磁盘读回并验证。原始快照的 SHA 再次检查保持不变。

程序没有访问或写回源门户，也不验证下载地址此时是否在线。该案例证明的是元数据约束与事务结果，不证明观测值正确、链接长期可用、数据库持久化、并发隔离或全量 DCAT-AP 合规。

## 浏览器接入

`scenario.json` 提供 `data`、`shapes`、`removals`、`repairAdditions` 四个 Turtle 字符串。首次验证使用 `data + shapes`；拒绝操作使用空 additions 和 `removals`；修复操作使用拒绝后原图、相同 `removals` 和 `repairAdditions`。每一步须调用实际 `dist/moonshacl.mjs` 的 `request`，不能用存档 evidence 代替现场结果。

`officialSummary` 是冻结快照的官方 base 验收摘要；`source` 和许可字段用于展示来源与范围。`currentUrl` / `replacementUrl` 供界面展示，后者来自冻结源，宜保持只读。机器证据另外保留完整原始官方报告以及拒绝报告，便于检查 UI 文案与验证结果一致。
