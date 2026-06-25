#!/bin/bash

set -u

# 为指定 ComfyUI 实例创建软链接，指向共享 ComfyUI 目录。
# 如果实例中的目标位置已存在真实文件或目录，可选择先备份；默认不备份。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DEFAULT_INSTANCE_DIR="$SCRIPT_DIR"
DEFAULT_SHARED_DIR="/Users/Laven/ComfyUI-Shared"
DEFAULT_LINK_DIRS="models custom_nodes"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

expand_path() {
    local value="$1"
    if [[ "$value" == "~" ]]; then
        printf '%s' "$HOME"
    elif [[ "$value" == "~/"* ]]; then
        printf '%s/%s' "$HOME" "${value#~/}"
    else
        printf '%s' "$value"
    fi
}

echo "ComfyUI 共享目录软链接创建工具"
echo

if [ $# -ge 1 ]; then
    INSTANCE_DIR="$1"
    shift
else
    echo "请输入需要创建软链接的 ComfyUI 实例目录，直接回车使用脚本所在目录："
    echo "  $DEFAULT_INSTANCE_DIR"
    read -r INSTANCE_DIR
fi

INSTANCE_DIR="$(trim "${INSTANCE_DIR:-}")"
if [ -z "$INSTANCE_DIR" ]; then
    INSTANCE_DIR="$DEFAULT_INSTANCE_DIR"
fi
INSTANCE_DIR="$(expand_path "$INSTANCE_DIR")"
INSTANCE_DIR="${INSTANCE_DIR%/}"

if [ ! -d "$INSTANCE_DIR" ]; then
    echo "错误：实例目录不存在："
    echo "  $INSTANCE_DIR"
    read -r -p "按回车键关闭窗口..."
    exit 1
fi

if [ ! -f "$INSTANCE_DIR/main.py" ] && [ ! -d "$INSTANCE_DIR/comfy" ]; then
    echo "警告：实例目录不像 ComfyUI 根目录，未发现 main.py 或 comfy 目录。"
    read -r -p "仍然继续？输入 y 继续，其他任意键退出： " CONTINUE_ANYWAY
    if [ "$(trim "${CONTINUE_ANYWAY:-}")" != "y" ]; then
        echo "已取消。"
        read -r -p "按回车键关闭窗口..."
        exit 1
    fi
fi

if [ $# -ge 1 ]; then
    SHARED_DIR="$1"
    shift
else
    echo
    echo "请输入共享目录路径，直接回车使用默认值："
    echo "  $DEFAULT_SHARED_DIR"
    read -r SHARED_DIR
fi

SHARED_DIR="$(trim "${SHARED_DIR:-}")"
if [ -z "$SHARED_DIR" ]; then
    SHARED_DIR="$DEFAULT_SHARED_DIR"
fi
SHARED_DIR="$(expand_path "$SHARED_DIR")"
SHARED_DIR="${SHARED_DIR%/}"

if [ ! -d "$SHARED_DIR" ]; then
    echo "错误：共享目录不存在："
    echo "  $SHARED_DIR"
    read -r -p "按回车键关闭窗口..."
    exit 1
fi

if [ $# -gt 0 ]; then
    LINK_DIRS="$*"
else
    echo
    echo "请选择需要创建软链接的目录："
    echo "  1) 使用默认目录：$DEFAULT_LINK_DIRS"
    echo "  2) 自定义输入目录"
    echo
    read -r -p "请输入选项 [1/2]，直接回车选择 1： " LINK_MODE
    LINK_MODE="$(trim "${LINK_MODE:-}")"

    case "$LINK_MODE" in
        ""|"1")
            LINK_DIRS="$DEFAULT_LINK_DIRS"
            ;;
        "2")
            echo
            echo "请输入目录名，多个目录用空格或逗号分隔。"
            echo "相对目录会按共享目录下的同名目录处理。"
            echo "示例：models custom_nodes input output user"
            echo "也支持输入绝对路径，链接名会使用路径最后一级目录名。"
            read -r LINK_DIRS
            ;;
        *)
            echo "错误：无效选项。"
            read -r -p "按回车键关闭窗口..."
            exit 1
            ;;
    esac
fi

LINK_DIRS="$(trim "${LINK_DIRS:-}")"
if [ -z "$LINK_DIRS" ]; then
    echo "错误：没有指定需要创建软链接的目录。"
    read -r -p "按回车键关闭窗口..."
    exit 1
fi

echo
echo "如果实例目录中已有同名真实文件或目录，是否先保留备份？"
echo "默认不备份：会删除旧目标后创建软链接。"
read -r -p "保留备份？[y/N]： " KEEP_BACKUP
KEEP_BACKUP="$(trim "${KEEP_BACKUP:-}")"

LINK_DIRS="${LINK_DIRS//,/ }"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo
echo "实例目录："
echo "  $INSTANCE_DIR"
echo "共享目录："
echo "  $SHARED_DIR"
if [ "$KEEP_BACKUP" = "y" ] || [ "$KEEP_BACKUP" = "Y" ]; then
    echo "已存在目标处理：保留备份"
else
    echo "已存在目标处理：不备份，直接删除旧目标"
fi
echo

created=0
skipped=0
failed=0

for item in $LINK_DIRS; do
    item="$(trim "$item")"
    [ -z "$item" ] && continue

    if [[ "$item" = /* || "$item" == "~/"* || "$item" == "~" ]]; then
        source_path="$(expand_path "$item")"
        link_name="$(basename "$source_path")"
    else
        link_name="${item%/}"
        source_path="$SHARED_DIR/$link_name"
    fi

    source_path="${source_path%/}"
    target_path="$INSTANCE_DIR/$link_name"

    echo "处理目录：$link_name"
    echo "  来源目录：$source_path"
    echo "  链接位置：$target_path"

    if [ ! -d "$source_path" ]; then
        echo "  错误：来源目录不存在。"
        failed=$((failed + 1))
        echo
        continue
    fi

    if [ -L "$target_path" ]; then
        current_target="$(readlink "$target_path")"
        if [ "$current_target" = "$source_path" ]; then
            echo "  跳过：软链接已经正确。"
            skipped=$((skipped + 1))
            echo
            continue
        fi

        echo "  替换旧软链接：$current_target"
        rm -- "$target_path"
    elif [ -e "$target_path" ]; then
        if [ "$KEEP_BACKUP" = "y" ] || [ "$KEEP_BACKUP" = "Y" ]; then
            backup_path="${target_path}.local-backup-${TIMESTAMP}"
            echo "  目标已存在，先备份为：$backup_path"
            mv "$target_path" "$backup_path"
        else
            echo "  目标已存在，不保留备份，删除旧目标。"
            rm -rf -- "$target_path"
        fi
    fi

    if ln -s "$source_path" "$target_path"; then
        echo "  已创建：$target_path -> $source_path"
        created=$((created + 1))
    else
        echo "  错误：软链接创建失败。"
        failed=$((failed + 1))
    fi

    echo
done

echo "处理完成。"
echo "  新建：$created"
echo "  跳过：$skipped"
echo "  失败：$failed"
echo
read -r -p "按回车键关闭窗口..."
