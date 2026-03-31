# TeslaMate SaaS 改造开发工作流文档（Rebase 版）

> 适用于基于 TeslaMate 二次开发多租户 SaaS 版本的场景
> 基于 teslamate-org
> 分支策略：`main`（上游镜像）+ `release`（业务开发）
> 核心原则：**同步 upstream 一律使用 rebase，保持线性历史**

---

## 📁 一、分支策略

| 分支        | 用途                     | 保护规则                           | 推送方式      |
| ----------- | ------------------------ | ---------------------------------- | ------------- |
| `main`      | 上游代码镜像，只用于同步 | ❌ 关闭保护（允许 force push）     | `git push -f` |
| `release`   | SaaS 业务开发主分支      | ⚠️ 可开启保护（需允许 force push） | `git push -f` |
| `feature/*` | 功能开发分支             | -                                  | `git push`    |

---

## 🔄 二、上游同步流程

### 2.1 初始化上游仓库（仅首次）

```bash
git remote add upstream https://github.com/teslamate-org/teslamate.git
git remote -v  # 验证 origin 和 upstream 都存在
```

---

### 2.2 同步上游到 main 分支

```bash
# 切换到 main 分支
git checkout main

# 获取上游最新代码
git fetch upstream

# 强制本地 main 与上游完全一致
git reset --hard upstream/main

# 强制更新远程 main 镜像
git push -f origin main
```

---

### 2.3 更新 release 分支（⭐ 使用 rebase）

```bash
# 切换到开发分支
git checkout release

# 基于最新 main 进行 rebase（替代 merge）
git rebase main
```

如果有冲突：

```bash
# 解决冲突后
git add <conflicted_files>
git rebase --continue

# 如需放弃
git rebase --abort
```

完成后推送：

```bash
git push -f origin release
```

---

## 🛠️ 三、代码开发流程

### 3.1 创建功能分支

```bash
git checkout release
git checkout -b feature/your-feature-name
```

---

### 3.2 开发与提交

```bash
# 编写代码
# ...

# 提交变更
git add .
git commit -m "feat(module): description"

# 推送到远程
git push -u origin feature/your-feature-name
```

---

### 3.3 同步最新 upstream（开发过程中）

```bash
git fetch upstream
git rebase main
```

---

### 3.4 合并回 release

```bash
# 切换回 release
git checkout release

# 使用 fast-forward 合并（保持线性历史）
git merge --ff-only feature/your-feature-name
```

如果失败（说明有分叉）：

```bash
git rebase feature/your-feature-name
```

然后推送：

```bash
git push -f origin release
```

---

## 📦 四、依赖管理

### 4.1 同步后更新依赖

```bash
# 每次 merge/rebase 后执行
mix deps.get
mix deps.compile
```

---

### 4.2 编译项目

```bash
# 开发阶段（允许警告）
mix compile

# 上线前（严格模式）
mix compile --warnings-as-errors
```

---

### 4.3 清理依赖缓存（遇到问题时）

```bash
rm -rf deps _build
mix deps.get
mix deps.compile
```

---

## ⚔️ 五、冲突解决指南

### 5.1 Rebase 冲突处理

```bash
# 开始 rebase
git rebase main

# 出现冲突时
# 1. 打开冲突文件，解决 <<<<<<< ======= >>>>>>> 标记
# 2. 标记解决
git add <conflicted_files>

# 3. 继续 rebase
git rebase --continue

# 如需放弃
git rebase --abort
```

---

### 5.2 常见冲突修复模式

| 场景           | 修复方案                                               |
| -------------- | ------------------------------------------------------ |
| 函数签名变更   | 更新调用处参数，如 `signed_in?()` → `signed_in?(conn)` |
| 返回值类型变更 | 匹配元组，如 `%Tokens{}` → `{:ok, %Tokens{}}`          |
| 字符串插值类型 | 使用 `inspect()`，如 `#{name}` → `#{inspect(name)}`    |
| 结构体更新     | 先匹配类型，如 `%Car{} = car = ...`                    |

---

### 5.3 批量搜索未更新调用

```bash
grep -rn "Api.signed_in?()" lib/
grep -rn "Vehicles.list()" lib/
grep -rn "create_or_update!(vehicle)" lib/
```

---

## 🚀 六、编译与部署

### 6.1 本地开发

```bash
# 获取依赖
mix deps.get

# 编译
mix compile

# 启动服务
mix phx.server

# 运行测试
mix test
```

---

### 6.2 Docker 构建

```bash
# 构建镜像
docker build -t teslamate-saas:latest .

# 运行容器
docker run -d -p 4000:4000 teslamate-saas:latest
```

---

### 6.3 GitHub Actions 部署

```yaml
# .github/workflows/release.yml
on:
  push:
    branches: [release]

jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: docker build -t teslamate-saas:latest .
      - run: docker push ${{ secrets.REGISTRY }}/teslamate-saas:latest
```

---

## ⚠️ 七、常见问题排查

| 问题                | 解决方案                                                  |
| ------------------- | --------------------------------------------------------- |
| `mix.lock` 不匹配   | `mix deps.get`                                            |
| 分支分叉 (diverged) | `git push -f origin release`                              |
| rebase 后 push 失败 | 使用 `git push -f`                                        |
| 编译警告即错误      | 开发阶段用 `mix compile`，上线前用 `--warnings-as-errors` |
| 函数未定义          | 检查函数签名是否随多租户改造变更                          |
| 类型不匹配          | 使用 `inspect()` 或先匹配结构体类型                       |

---

## 📋 八、快速命令参考

```bash
# === 同步上游 ===
git checkout main && git fetch upstream && git reset --hard upstream/main && git push -f origin main

# === 更新 release（关键）===
git checkout release && git rebase main && git push -f origin release

# === feature 同步 ===
git fetch upstream && git rebase main

# === 依赖管理 ===
mix deps.get && mix deps.compile && mix compile

# === 冲突解决 ===
git add <file> && git rebase --continue

# === 强制推送 ===
git push -f origin <branch>

# === 备份分支 ===
git branch backup/$(date +%Y%m%d)
```

---

## 🎯 九、最佳实践建议

1. **同步 upstream 一律使用 rebase（禁止 merge main）**
2. **标记定制代码**：所有修改处添加 `# SaaS-MODIFIED:` 注释
3. **定期同步上游**：建议每周同步一次
4. **小步提交**：每个功能独立 commit
5. **CI/CD 严格检查**：上线前启用 `--warnings-as-errors`
6. **release 分支保持可发布状态**
7. **强制推送前建议创建备份分支**

---

## 📝 十、文档维护

- 本文档版本：v1.0
- 最后更新：2026-03-31
- 维护者：SaaS 开发团队
- 存放位置：`/docs/workflow.md`

---

> 💡 **提示**：将此文档保存到项目的 `docs/` 目录，并纳入版本控制，方便团队成员查阅和更新。
