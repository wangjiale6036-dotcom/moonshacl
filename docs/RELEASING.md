# 维护与发行

工具链固定为 moonc `0.10.14+7d59c7ec9`，使用 Node 24。Linux/Windows CI 执行同一套验证，不把本机通过直接等同于 CI 通过。

```sh
node scripts/moon.mjs update
npm ci --ignore-scripts
python -m pip install -r requirements-oracle.txt
npm test
node scripts/export-evidence.mjs --snapshot
```

审查并提交全部发行输入，确认 `package.json` 与 `moon.mod` 版本相同，再构建：

```sh
node scripts/package-release.mjs
node scripts/release-smoke.mjs
node scripts/moon.mjs package
```

`package-release` 要求干净工作区，源码 zip 来自 HEAD，CLI tar.gz 包含编译结果、示例、支持边界和完整第三方许可；不需要安装 npm 依赖或 MoonBit 编译器即可运行 CLI。`manifest.json` 记录源提交、大小和 SHA-256，`SHA256SUMS` 供下载核对。

发布前检查 CI、源包清单、许可和支持范围。使用维护者自己的 Mooncakes/GitHub 登录发布，凭据不进入版本库。发布成功后执行 `node scripts/consumer-test.mjs --registry`，验证 registry 中的公开包；本地 workspace 消费成功不能代替这一步。

GitHub tag 对应已验证提交，附件使用本次构建的 manifest/checksums；发行后不重写标签或替换为不同代码。后续修复提升版本并保留旧版本与回归用例。

问题反馈通过 [GitHub Issues](https://github.com/wangjiale6036-dotcom/moonshacl/issues)。请提供最小 shapes/data、预期行为、实际报告和版本，避免上传私人数据。项目不承诺响应时限或尚未验证的兼容能力。
