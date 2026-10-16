# 第三方来源与许可

MoonSHACL 原始实现采用 [Apache License 2.0](LICENSE)。以下内容保留各自授权；不会把第三方测试或官方规则计算为本项目的原创功能。

## MoonTTL

生产依赖 `thy1016/moonttl@0.3.0`，Apache-2.0，作者及源仓库：[thy7/mbt.ttl](https://www.gitlink.org.cn/thy7/mbt.ttl)，包文档：[Mooncakes](https://mooncakes.io/docs/thy1016/moonttl@0.3.0)。不复制/修改安装包源码；依赖由 Moon 工具获取，许可证随依赖发行。

Turtle 适配调用其 `gen_trig`、`gen_nquads` public API。本项目自身代码修正该发布版本的兼容问题：literal 后相邻 comma/semicolon 先作保持词项内容的空白分隔；未展开 slice 的 prefix 检查改到 materializer Deep 验证；已由语法判定的 bare `a` predicate 补回 KwA 标签。另依据原始 term span 区分显式 blank label 与匿名/集合生成节点，避免 MoonTTL 的 genid 标签与用户同名标签合并。所有语法和 materialization 错误仍返回 Err，回归测试检查坏语法、未声明 prefix、named graph 和 blank identity。

## W3C 官方测试

来源：[w3c/data-shapes](https://github.com/w3c/data-shapes/tree/07458ebb1ece6addc664636d70b08444a7b66609/data-shapes-test-suite)，固定 commit `07458ebb1ece6addc664636d70b08444a7b66609`。授权声明见 [仓库原始 LICENSE](licenses/W3C-repository-LICENSE.md) 和 [W3C Software and Document License 完整文本](licenses/W3C-Software-and-Document.html)。

本软件包含从 W3C data-shapes test suite 复制的测试材料。Copyright © W3C® and the respective contributors. 原始文件字节保持不变，仅编码为 MoonBit 字符串分块以供离线测试；本项目另写测试执行/结果比较代码。[fixtures/SOURCES.json](fixtures/SOURCES.json) 记录每个资源的 SHA-256。使用测试不代表 W3C 认证、认可或赞助。

## DCAT-AP

来源：European Commission / SEMIC，DCAT-AP 3.0.0 base SHACL shapes，[固定文件链接](https://github.com/SEMICeu/DCAT-AP/blob/4470b8ea907b7eb9ec55ab22befd1ecd2210ff32/releases/3.0.0/shacl/dcat-ap-SHACL.ttl)，[CC BY 4.0 完整许可](licenses/DCAT-AP-CC-BY-4.0.txt)。固定版本与哈希见 [DCAT-SOURCE.json](fixtures/DCAT-SOURCE.json)。

`fixtures/dcat-ap-3.0.0.ttl` 未作修改；测试中的 MoonBit 字符串为同文件内容。示例 RDF 数据由本项目编写。本项目没有欧盟官方验证服务的全部资源、推理或认证覆盖。

## 仅用于测试的 JavaScript 依赖

`n3@1.26.0`（MIT）、`rdf-validate-shacl@0.6.5`（MIT）、`shacl-engine@1.1.0`（MIT）、`@rdfjs/data-model@2.1.1`（MIT）。具体安装版本及传递依赖固定在 `package-lock.json`，许可证位于各安装包。它们用于独立解析/语义对照，不进入产品的原生规则逻辑。Node CLI 本身只使用内置文件和进程功能。

## Unicode 数据和 XPath 正则测试

纯 MoonBit 正则实现使用固定 Unicode 15.0 的类别、块和大小写映射数据。原始数据来源和 SHA-256 在 `fixtures/regex-unicode/SOURCES.json`，生成代码为 `src/xpath_regex/unicode_generated.mbt`；许可见 [Unicode 数据许可](licenses/Unicode-DATA-LICENSE.txt)。数据和生成表不计入原创代码量。

W3C QT3 的 `fn:matches` 和正则回归用例用于独立标准测试，源版本、哈希、适用 XPath 版本与排除原因记录在 `fixtures/regex-*.json`。QT3 原始许可链接对应 [W3C Software License 2023](licenses/W3C-Software-2023.html)，已附完整文本；仅转换表达方式，不将这些数据宣称为原创实现。正则解析器、捕获执行器及 NFA 由 MoonBit 实现。

## 仅用于测试的 Python 依赖

`pySHACL@0.30.1`（Apache-2.0）及 RDFLib 用于第二套独立验证及 RDF 图同构比较；固定版本见 `requirements-oracle.txt`。Python 不属于库和 CLI 的运行依赖，第三方引擎没有被编译或调用到产品验证路径。
