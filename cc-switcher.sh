cc-switcher() {
    # 1. 定义环境变量和路径 (支持通过环境变量覆盖默认路径)
    local conf_dir="${CC_SWITCHER_CONF_PATH:-$HOME/cc-switcher}"
    local cred_dir="${CC_SWITCHER_CRED_PATH:-$HOME/.config/cc-switcher}"
    local claude_dir="$HOME/.claude"
    local target_json="$claude_dir/settings.json"

    # 将状态记录文件放在 conf_dir 下，保持 ~/.claude 的纯净
    local state_file="$conf_dir/.cc_current"

    # 2. 自动初始化目录（如果不存在的话）
    if [ ! -d "$conf_dir" ]; then
        mkdir -p "$conf_dir"
        echo "📁 已自动创建配置模版目录: $conf_dir"
    fi
    if [ ! -d "$cred_dir" ]; then
        mkdir -p "$cred_dir"
    fi
    if [ ! -d "$claude_dir" ]; then
        mkdir -p "$claude_dir"
    fi

    # 3. 核心功能路由
    case "$1" in
        status)
            if [ -f "$state_file" ]; then
                echo "🟢 当前使用的配置: $(cat "$state_file")"
            else
                echo "⚪ 当前状态未知 (可能尚未设置)"
            fi
            ;;
            
        list)
            local current=""
            if [ -f "$state_file" ]; then
                current=$(cat "$state_file")
            fi

            echo "📋 所有可用配置 ($conf_dir):"
            
            local found=0
            # 遍历 conf_dir 下所有的 settings-*.json
            for f in "$conf_dir"/settings-*.json; do
                [ -e "$f" ] || continue
                found=1
                # 提取厂商名称
                local name=$(basename "$f" | sed 's/settings-\(.*\)\.json/\1/')
                # 跳过公共配置文件（它不是供应商）
                [ "$name" = "common" ] && continue
                if [ "$name" = "$current" ]; then
                    echo "  * $name  (当前激活)"
                else
                    echo "    $name"
                fi
            done
            
            if [ $found -eq 0 ]; then
                echo "  (空) 未找到配置！请在 $conf_dir 下创建 settings-<name>.json"
            fi
            ;;
            
        set)
            if [ -z "$2" ]; then
                echo "❌ 错误: 请指定要切换的配置名称。"
                echo "用法: cc-switcher set <name> (例如: cc-switcher set deepseek)"
                return 1
            fi
            
            local source_file="$conf_dir/settings-$2.json"
            # 修复点：这里 if 和 [ 之间加入了空格
            if [ ! -f "$source_file" ]; then
                echo "❌ 错误: 找不到配置文件 $source_file"
                return 1
            fi
            
            # jq 是合并配置的必需依赖
            if ! command -v jq &> /dev/null; then
                echo "❌ 错误: 未找到 jq，请先安装 jq (brew install jq)"
                return 1
            fi

            # 必须先有对应的 .env 凭证文件，否则拒绝加载
            local env_file="$cred_dir/.env-$2"
            if [ ! -f "$env_file" ]; then
                echo "❌ 错误: 未找到凭证文件 $env_file"
                echo "   请创建该文件并设置 ANTHROPIC_API_KEY 或 ANTHROPIC_AUTH_TOKEN"
                return 1
            fi

            # 清理旧的认证环境变量，避免不同供应商间 token 污染
            #unset ANTHROPIC_API_KEY
            unset ANTHROPIC_AUTH_TOKEN
            source "$env_file"

            # 核心动作：合并公共配置 + 供应商配置，写入 ~/.claude/settings.json
            local common_file="$conf_dir/settings-common.json"
            if [ -f "$common_file" ]; then
                jq -s '.[0] * .[1]' "$common_file" "$source_file" > "$target_json"
            else
                jq '.' "$source_file" > "$target_json"
            fi

            # 记录当前状态
            echo "$2" > "$state_file"

            echo "Switched to [$2] — settings applied to ~/.claude/settings.json"
            ;;
            
        *)
            echo "🎛️  CC-Switcher: Claude Code 极简配置管理器"
            echo "-------------------------------------------------"
            echo "📂 模版存放路径: $conf_dir"
            echo "🔐 凭证存放路径: $cred_dir"
            echo "🎯 目标写入路径: $target_json"
            echo "-------------------------------------------------"
            echo "环境变量:"
            echo "  CC_SWITCHER_CONF_PATH - 配置模版目录 (默认 ~/cc-switcher)"
            echo "  CC_SWITCHER_CRED_PATH - 凭证文件目录 (默认 ~/.config/cc-switcher)"
            echo "-------------------------------------------------"
            echo "用法:"
            echo "  cc-switcher status     - 打印当前使用的配置"
            echo "  cc-switcher list       - 打印所有可用配置"
            echo "  cc-switcher set <name> - 切换到指定配置 (如: deepseek, qwen)"
            ;;
    esac
}

# 自动恢复上一次使用的配置
_cc_switcher_auto_restore() {
    local conf_dir="${CC_SWITCHER_CONF_PATH:-$HOME/cc-switcher}"
    local state_file="$conf_dir/.cc_current"
    [ -f "$state_file" ] || return 0
    local last
    last=$(cat "$state_file")
    [ -n "$last" ] && cc-switcher set "$last" 2>/dev/null
}
_cc_switcher_auto_restore
unset -f _cc_switcher_auto_restore