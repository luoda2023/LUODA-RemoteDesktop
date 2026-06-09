# LUODA CI 构建监控总结

## ✅ 已完成的配置

### 1. 自动触发配置

CI 流水线已配置为以下情况自动触发：

| 触发条件 | 配置 | 状态 |
|---------|------|------|
| Master 分支推送 | `.workflow/luoda-full-build.yml` | ✅ |
| 创建版本标签 | `tags: v*` | ✅ |
| 手动触发 | Gitee 界面 / API / 脚本 | ✅ |

### 2. 监控工具

#### 方法 1: Web 监控面板（推荐）
```
文件：monitor.html
使用：在浏览器打开 monitor.html
功能：实时状态、进度条、日志输出
刷新：每 10 秒自动刷新
```

**访问方式**：
- 本地打开：直接双击 `monitor.html`
- 在线预览：https://gitee.com/soulemo_1/dicad/blob/master/monitor.html

#### 方法 2: Python 监控脚本
```bash
# 设置 Token
export GITEE_TOKEN=your_token_here

# 监控最新构建
python3 ci-logger.py

# 触发并监控新构建
python3 ci-logger.py trigger

# 监控指定 ID 的构建
python3 ci-logger.py <pipeline_id>
```

#### 方法 3: Shell 监控脚本
```bash
# 设置 Token
export GITEE_TOKEN=your_token_here

# 运行监控
./monitor-ci.sh
```

### 3. 构建配置

#### 完整构建流程（luoda-full-build）

| 阶段 | 产物 | 路径 |
|------|------|------|
| Windows | EXE + MSI | `target/release/` |
| Android | APK | `flutter/build/app/outputs/` |
| Linux | DEB + Bin | `./` 和 `target/release/` |

#### 环境变量要求

```yaml
Flutter: 3.16
Rust: 1.75
Java: 11 (Android)
Node.js: 16
```

---

## 📊 监控方式对比

| 方式 | 优点 | 缺点 | 推荐场景 |
|------|------|------|---------|
| Web 面板 | 可视化好、实时更新 | 需要浏览器 | 日常监控 |
| Python 脚本 | 功能完整、可定制 | 需要 Python | 自动化集成 |
| Shell 脚本 | 简单快捷 | 功能有限 | 快速检查 |
| Gitee 界面 | 官方支持、日志完整 | 需要手动刷新 | 查看详细日志 |

---

## 🚀 使用指南

### 快速开始

1. **获取 Gitee Token**
   ```
   访问：https://gitee.com/profile/personal_access_tokens
   权限：勾选 'projects'
   ```

2. **设置环境变量**
   ```bash
   export GITEE_TOKEN=your_token_here
   ```

3. **触发构建**
   - 方式 A: 访问 https://gitee.com/soulemo_1/dicad/pipelines
   - 方式 B: 运行 `python3 ci-logger.py trigger`
   - 方式 C: 打开 `monitor.html` 点击"触发新构建"

4. **监控进度**
   - Web: 打开 `monitor.html`
   - CLI: `python3 ci-logger.py`
   - Shell: `./monitor-ci.sh`

### 构建产物下载

构建成功后，产物位置：

1. **Gitee 界面下载**
   ```
   https://gitee.com/soulemo_1/dicad/pipelines/[ID]/artifacts
   ```

2. **Releases 下载**（如果配置自动发布）
   ```
   https://gitee.com/soulemo_1/dicad/releases
   ```

---

## 🔧 故障排查

### 常见问题

#### 1. 构建不触发
- 检查 `.workflow/luoda-full-build.yml` 语法
- 确认触发条件匹配（master 分支或 v* 标签）
- 查看 Gitee 流水线设置是否启用

#### 2. Token 无效
```bash
# 检查 Token 是否设置
echo $GITEE_TOKEN

# 重新生成 Token
# 访问：https://gitee.com/profile/personal_access_tokens
```

#### 3. 构建失败
- 查看日志：https://gitee.com/soulemo_1/dicad/pipelines/[ID]/jobs
- 检查依赖版本（Flutter 3.16, Rust 1.75）
- 查看内存是否充足（至少 4GB）

#### 4. 产物找不到
- 确认构建阶段名称正确
- 检查 artifacts 路径配置
- 查看构建日志确认生成位置

---

## 📈 监控面板功能

### monitor.html 功能

1. **实时状态显示**
   - 当前构建状态
   - 流水线 ID
   - 触发类型
   - 开始时间
   - 持续时间

2. **可视化进度**
   - 动态进度条
   - 颜色编码状态
   - 动画效果

3. **操作按钮**
   - 触发新构建
   - 手动刷新
   - 跳转 Gitee

4. **实时日志**
   - 时间戳
   - 类型区分（info/success/error/warning）
   - 自动滚动

5. **快速链接**
   - 代码仓库
   - 发布版本
   - 构建指南
   - 品牌文档

---

## ⚙️ 自动化配置

### 自动触发规则

```yaml
triggers:
  push:
    branches:
      include: [master]
      exclude: [docs/**]
    tags:
      include: ["v*"]
  pull_request:
    branches: [master]
  manual: [run_build]
```

### 构建产物

```yaml
artifacts:
  - LUODA_WINDOWS_EXE: ./target/release/luoda.exe
  - LUODA_WINDOWS_MSI: ./target/release/*.msi
  - LUODA_ANDROID_APK: ./flutter/build/app/outputs/flutter-apk/app-release.apk
  - LUODA_LINUX_DEB: ./*.deb
```

---

## 📞 支持资源

### 文档
- `CI_GUIDE.md` - CI/CD 详细指南
- `BRANDING_SUMMARY.md` - 品牌化说明
- `.workflow/*.yml` - 流水线配置

### 工具
- `monitor.html` - Web 监控面板
- `ci-logger.py` - Python 监控工具
- `monitor-ci.sh` - Shell 监控脚本

### 链接
- 流水线：https://gitee.com/soulemo_1/dicad/pipelines
- 仓库：https://gitee.com/soulemo_1/dicad
- 帮助：https://help.gitee.com/devops/

---

## 📋 检查清单

构建前检查：
- [ ] Gitee Token 已设置
- [ ] 分支为 master 或已创建 v* 标签
- [ ] CI 配置文件已推送
- [ ] 监控工具已就绪

构建后验证：
- [ ] EXE 文件生成
- [ ] MSI 文件生成
- [ ] APK 文件生成
- [ ] DEB 文件生成
- [ ] 所有测试通过
- [ ] 产物已下载

---

**配置完成时间**: 2026-05-09  
**版本**: v1.0.0  
**最后更新**: 2026-05-09
