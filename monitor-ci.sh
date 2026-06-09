#!/bin/bash
# LUODA CI 构建监控脚本
# 使用方法：./monitor-ci.sh [pipeline_id]

OWNER="soulemo_1"
REPO="dicad"
GITEE_TOKEN="${GITEE_TOKEN:-}"

if [ -z "$GITEE_TOKEN" ]; then
    echo "❌ 错误：请设置 GITEE_TOKEN 环境变量"
    echo ""
    echo "获取方式："
    echo "1. 访问 https://gitee.com/profile/personal_access_tokens"
    echo "2. 创建新令牌，勾选 'projects' 权限"
    echo "3. export GITEE_TOKEN=your_token_here"
    echo ""
    echo "或者手动触发流水线："
    echo "1. 访问 https://gitee.com/soulemo_1/dicad/pipelines"
    echo "2. 点击 '运行流水线' 按钮"
    echo "3. 选择 'luoda-full-build' 流水线"
    exit 1
fi

# 获取最新的流水线 ID
if [ -z "$1" ]; then
    echo "📋 获取最新的流水线..."
    response=$(curl -s -H "Authorization: Bearer $GITEE_TOKEN" \
        "https://gitee.com/api/v5/repos/$OWNER/$REPO/pipelines?page=1&per_page=1")
    
    pipeline_id=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    
    if [ -z "$pipeline_id" ]; then
        echo "❌ 未找到流水线"
        exit 1
    fi
    
    echo "✅ 找到流水线 ID: $pipeline_id"
else
    pipeline_id=$1
fi

# 轮询监控
echo "⏳ 开始监控流水线 $pipeline_id ..."
echo "流水线链接：https://gitee.com/soulemo_1/dicad/pipelines/$pipeline_id"
echo ""

max_attempts=180  # 最多监控 30 分钟 (180 * 10 秒)
attempt=0

while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 获取流水线状态
    response=$(curl -s -H "Authorization: Bearer $GITEE_TOKEN" \
        "https://gitee.com/api/v5/repos/$OWNER/$REPO/pipelines/$pipeline_id")
    
    state=$(echo "$response" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    trigger=$(echo "$response" | grep -o '"trigger":"[^"]*"' | cut -d'"' -f4)
    
    echo "[$attempt/$max_attempts] $timestamp - 状态：${state:-unknown}, 触发：${trigger:-manual}"
    
    case "$state" in
        "success")
            echo ""
            echo "✅ 构建成功!"
            echo "📦 产物链接：https://gitee.com/soulemo_1/dicad/pipelines/$pipeline_id/artifacts"
            exit 0
            ;;
        "failure")
            echo ""
            echo "❌ 构建失败!"
            echo "📄 查看日志：https://gitee.com/soulemo_1/dicad/pipelines/$pipeline_id/jobs"
            exit 1
            ;;
        "cancelled")
            echo ""
            echo "⚠️  构建已取消"
            exit 2
            ;;
        *)
            # 继续等待
            sleep 10
            ;;
    esac
done

echo ""
echo "⏰ 监控超时 (30 分钟)"
echo "📄 查看最新状态：https://gitee.com/soulemo_1/dicad/pipelines/$pipeline_id"
exit 3
