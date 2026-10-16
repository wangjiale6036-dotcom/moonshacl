# 三个可验收的集成场景

运行 `npm run build` 后执行 `node scripts/scenarios.mjs`，产物写入 `artifacts/scenarios/`。
脚本逐项断言下列行为，任何不符合均以非零退出码结束。输入是公开规则和自建合成数据，不代表已有外部用户采用。

## 数据目录导入

MoonBit 数据目录工具导入 `examples/dcat-data.ttl`，执行未经修改的官方 DCAT-AP 3.0.0 base shapes。
正例必须通过；尝试删除 distribution 的 `dcat:accessURL` 必须被拒绝，报告包含 MinCount 违反，返回图与原图逐三元组一致。
产物 `01-catalogue-*.json`。这里只验证固定 base shapes，不宣称完整 DCAT-AP 认证。

## 共享对象编辑与导出

元数据编辑器中 Alice/Bob 共享 Acme，Carol 引用另一公司。
删除 Acme 名称必须定位 Alice/Bob 两个 focus nodes，`checked=2, reused=1`，原图保留 11 triples。
同一提案中删除旧名称并加入新名称必须提交，旧值消失、新值存在，导出 N-Triples 重新读入后再次校验通过。
产物 `02-editor-*.json`、`02-editor-export.nt`。CLI 返回图供调用方保存，不自动覆盖输入文件；Session 不提供磁盘持久化或并发事务。

## 发布管线中的规则能力检查

维护者收到 shapes 文件，先运行 `audit` 确认规则可执行，再处理数据。
people shapes 返回 supported；pattern 等全部 Core 规则实际执行。示例 unsupported-shapes 含 SPARQL 扩展，使用 --strict 时返回退出码 2 和 problems，不产生伪造的 conforms 报告；默认 Core 模式提供未执行扩展的 diagnostics。
产物 `03-profile-*.json`。这是编译支持范围检查，不是“数据不符合”的退出码 1。

以上行为与统计数量分开定义。完整能力契约 见 [PROFILE](PROFILE.md)，独立语义对照见 [VALIDATION](VALIDATION.md)。
