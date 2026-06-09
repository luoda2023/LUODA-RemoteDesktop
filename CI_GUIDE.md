# LUODA CI/CD 构建指南

## 📋 自动触发配置

CI 流水线已配置为自动触发，触发条件：

### 自动触发
- ✅ `master` 分支推送代码
- ✅ 创建 `v*` 标签（如 v1.0.0）
- ✅ 手动触发（在 Gitee 界面）

### 支持的构建类型
- 🪟 **Windows**: EXE + MSI 安装包
- 🤖 **Android**: APK 安装包
- 🐧 **Linux**: DEB 包 + 可执行文件

---

## 🚀 手动触发流水线

### 方法 1: Gitee Web 界面（推荐）

1. **访问流水线页面**
   ```
   https://gitee.com/soulemo_1/dicad/pipelines
   ```

2. **点击 "运行流水线" 按钮**

3. **选择流水线**
   - 选择 `luoda-full-build` (完整构建)
   - 或 `luoda-release` (简化构建)

4. **选择分支/标签**
   - 分支：`master`
   - 或标签：`v1.0.0`

5. **点击 "运行" 开始构建**

### 方法 2: 使用监控脚本

```bash
# 1. 获取 Gitee 私人令牌
# 访问：https://gitee.com/profile/personal_access_tokens
# 创建令牌，勾选 'projects' 权限

# 2. 设置环境变量
export GITEE_TOKEN=your_token_here

# 3. 运行监控脚本
cd /workspace/LUODA-RemoteDesktop
./monitor-ci.sh
```

### 方法 3: 使用 API（需要 Token）

```bash
# 设置 Token
export GITEE_TOKEN=your_token_here

# 触发流水线
curl -X POST \
  -H "Authorization: Bearer $GITEE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"ref":"master","pipeline_name":"luoda-full-build","trigger_type":"manual"}' \
  "https://gitee.com/api/v5/repos/soulemo_1/dicad/pipelines"
```

---

## 📊 监控构建进度

### 实时监控

1. **Web 界面查看**
   ```
   https://gitee.com/soulemo_1/dicad/pipelines
   ```
   - 查看最新流水线
   - 点击查看详情
   - 查看每个步骤的日志

2. **使用监控脚本**
   ```bash
   ./monitor-ci.sh [pipeline_id]
   ```

3. **查看构建产物**
   - 构建成功后访问：`https://gitee.com/soulemo_1/dicad/pipelines/[ID]/artifacts`

---

## 🔧 构建配置说明

### 流水线文件

- `.workflow/luoda-full-build.yml` - 完整构建（推荐）
- `.workflow/luoda-release.yml` - 简化构建
- `.workflow/master-pipeline.yml` - 主分支构建

### 构建产物

| 平台 | 产物路径 | 文件名 |
|------|---------|--------|
| Windows EXE | `./target/release/` | `luoda.exe` |
| Windows MSI | `./target/release/` | `luoda-*.msi` |
| Android APK | `./flutter/build/app/outputs/flutter-apk/` | `app-release.apk` |
| Linux DEB | `./` | `luoda-*.deb` |
| Linux Bin | `./target/release/` | `luoda` |

---

## 🐛 故障排查

### 构建失败常见原因

1. **依赖缺失**
   ```bash
   # 检查 Flutter 版本
   flutter --version
   # 应该是 3.16.x
   
   # 检查 Rust 版本
   rustc --version
   # 应该是 1.75.x
   ```

2. **证书问题（Android）**
   ```bash
   # 接受许可证
   yes | flutter doctor --android-licenses
   ```

3. **内存不足**
   - Windows 构建需要至少 4GB 可用内存
   - Android 构建需要至少 8GB 可用内存

### 查看构建日志

1. **Gitee Web 界面**
   ```
   https://gitee.com/soulemo_1/dicad/pipelines/[ID]/jobs
   ```

2. **下载日志**
   - 在流水线详情页面点击 "下载日志"

3. **本地调试构建**
   ```bash
   # Windows
   python3 build.py --flutter --release
   
   # Android
   cd flutter && flutter build apk --release
   
   # Linux
   cargo build --release
   ```

---

## 📱 下载构建产物

### 方式 1: Gitee 界面下载

1. 访问成功的流水线页面
2. 点击 "制品" 标签
3. 下载需要的文件

### 方式 2: 直接下载（如果公开）

```bash
# Windows
wget https://gitee.com/soulemo_1/dicad/releases/download/v1.0.0/luoda-1.0.0.exe

# Android
wget https://gitee.com/soulemo_1/dicad/releases/download/v1.0.0/luoda-1.0.0.apk

# Linux
wget https://gitee.com/soulemo_1/dicad/releases/download/v1.0.0/luoda-1.0.0.deb
```

---

## ⚙️ 自定义构建

### 修改版本号

编辑 `Cargo.toml`:
```toml
[package]
version = "1.0.0"  # 修改这里
```

编辑 `flutter/pubspec.yaml`:
```yaml
version: 1.0.0+1  # 修改这里
```

### 添加新的构建目标

编辑 `.workflow/luoda-full-build.yml`，添加新的 stage。

### 配置自动发布

创建 `.workflow/release.yml` 配置自动创建 Release。

---

## 📞 支持

- 流水线问题：查看 Gitee 文档 https://help.gitee.com/devops/
- 构建问题：查看 `BRANDING_SUMMARY.md`
- 代码问题：查看 `.github/workflows/` 中的配置

---

**最后更新**: 2026-05-09
**版本**: v1.0.0
