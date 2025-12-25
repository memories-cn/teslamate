# 确保 fork 的 main 分支与原始仓库（upstream）完全同步，你需要执行以下步骤：

- 首先，确保你的本地 main 分支与 upstream/main 同步：

```bash
git checkout main
git fetch upstream
git merge upstream/main
git push origin main
```

- 然后，由于你设置了保护规则，不能直接推送到 main 分支，你需要创建一个新的分支：

```bash
git checkout -b update-from-upstream
```

- 推送这个新分支到你的 fork：

```bash
git push origin update-from-upstream
```

- 然后在 GitHub 界面中创建一个 Pull Request，将这个新分支合并到你的 main 分支。

- 在 PR 中审查更改后，合并 PR 以更新你的 main 分支
