# MoonSHACL 交互演示

演示使用与 CLI 相同的 MoonBit 编译模块，在浏览器 Web Worker 中运行。前端只负责操作、图形呈现和导出；校验结论、受影响节点及提交状态由引擎计算。页面加载后校验不调用远程服务。

按本文从 11 月 10 日的补验源码构建，会使用包含两轮 Session 优化的引擎。构建版本可通过 `build-info.json` 中的引擎哈希核对。

## 构建与本地运行

```sh
npm ci --ignore-scripts
node scripts/moon.mjs update
npm run demo:build
npm run test:demo
npm run demo:serve
```

打开终端显示的地址，默认 `http://127.0.0.1:4173`。`dist/demo/` 是完整静态站点，可放到普通静态服务器；不要直接双击 HTML，浏览器模块、fetch 和 Worker 需要 HTTP(S)。端口可用 `DEMO_PORT` 环境变量配置。

构建同时收集真实数据应用与性能报告（如果存在）。要更新演示中附带的归档证据，先运行 `node scripts/real-data.mjs --record` 和 `npm run benchmark`，再运行 `npm run demo:build`。普通 `npm run test:real-data` 只将复验结果写入 `artifacts/`，不会覆盖归档证据。本地 `dist/` 属于构建产物，不作为手工维护源码。

## 两分钟演示顺序

1. 展示初始图：Alice/Bob 共享 Acme，Carol 属于另一家公司，全部符合规则。
2. 尝试删除共享公司名称。引擎报告 Alice/Bob 的多跳路径违反 `minCount`，更新被拒绝，当前图保留名称。
3. 输入新公司名称，执行原子替换。删除旧名称与添加新名称在同一提案内校验，通过后提交。
4. 导出提交后的图，再切换公开目录数据应用，查看真实元数据的来源与应用规则。
5. 展示公开目录错误注入、拒绝与修复过程；打开原始报告核查节点、路径、规则组件和运行状态。

`checked/reused` 是引擎的根校验任务数量，不是性能倍数。浏览器每次通过无状态 JSON bridge 基于当前图创建 Session，当前图在页面内保存；跨调用的持久缓存性能由独立 [性能基准](PERFORMANCE.zh-CN.md) 测量。

第二轮正式测量中，上一轮剩余的 1,000/5,000 人全部受影响场景，预检中位数由 11.974→9.765 ms、67.104→53.186 ms，下降 18.4%、20.7%。本轮哈希全量/预检比值为 0.97–3.00×，100 人全部受影响仍略慢；独立完整确认是 1.05–2.86×、0/12 较慢，单独列示而不替代正式结果。这两个目标场景两次均超过 1×，但全部受影响时 `reused=0`，改进属于构图等实现开销减少。前后分时运行，未随机交错配对；不能据此推断浏览器点击的同等提速，或声称所有负载更快。[首次优化前](PERFORMANCE-BEFORE.zh-CN.md)、[第一轮](PERFORMANCE-ROUND1.zh-CN.md)、[正式报告](PERFORMANCE.zh-CN.md)和[独立复测](PERFORMANCE-CONFIRMATION.zh-CN.md)共同保留比较条件。

## 证据与边界

- 共享对象图为明确标注的合成示例，便于解释依赖传播。
- 公开目录应用的来源、字段投影、许可和原始结果见 [真实数据说明](REAL-DATA.zh-CN.md)。公开数据接入不等于外部用户采用。
- 不支持扩展、解析失败或执行预算耗尽会作为错误展示，不能计作通过或普通数据违反。
- 当前交互状态只保存在内存，刷新页面重置；只有主动导出才下载文件。
- `dist/demo/build-info.json` 记录引擎与数据的 SHA-256，可与源码构建复核。
- `npm run test:demo` 验证分发的引擎和场景，包括成功提交后再次编辑、失败保留图和数据来源信息；浏览器交互另行验收。
- 本轮重建分发通过 12/12 类检查，2026-10-23 真实数据流程重新记录后 41/41 通过，三后端内核各 1,756 个测试块通过，`node scripts/verify.mjs` 单次完整执行通过；详见[本轮验收](evidence/optimization-verification.json)。这些本地检查不代表线上实际访问或浏览器交互已通过。
