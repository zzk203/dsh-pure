#!/bin/bash
# dsh 纯净模式启动器 —— 只加载出厂随附插件。
#
# 为什么需要它：只要有一个自装（第三方）bundle 在启动期抛错，`dsh web` 就是
# fail-loud：整棵树 dispose、进程 exit 1、端口没人监听 → GUI 直接消失；而此时
# "用插件市场把坏插件卸掉"这条路同时是死的 —— 市场自己就是被炸掉的组合里的插件。
#
# 做法：另建一个 profile（默认名 pure），bundle 列表只有出厂随附的模板
# （web 模板 = @deepseek-ai/dsh-base + @deepseek-ai/dsh-web-app）。它和正常
# profile 共用同一个 $DSH_HOME，所以会话历史、settings.yaml、.credentials.yaml、
# agent preset 全都在 —— 起来就能让 agent 去修插件。不改 dsh 本身的任何文件，
# 升级也不会覆盖它。
#
# 用法：
#   ./dsh-pure.sh                       # 起纯净 web（默认从 3080 起找空闲端口）
#   ./dsh-pure.sh --no-open             # 不开浏览器；其余参数原样透传给 dsh web
#   DSH_PURE_PORT=19000 ./dsh-pure.sh   # 指定首选端口
#
# 环境变量：
#   DSH_PURE_PORT      首选端口，默认 3080（dsh web 的出厂默认）；0 = 内核随机
#   DSH_PURE_PROFILE   纯净 profile 名，默认 pure；换名等于再建一个
#   DSH_PURE_TEMPLATE  用来创建纯净 profile 的出厂模板，默认 web
#   DSH_PURE_CWD       启动时切到的目录（=会话工作区）；默认留在当前目录
#   DSH_BIN            dsh 可执行文件；默认从 PATH 找 dsh
#   DSH_NODE           node 可执行文件；仅在 dsh 不能直接执行时用到
#   DSH_HOME           dsh home（会话/设置/凭据所在）；默认 ~/.dsh
set -u

# ---- 定位 dsh 与 node ------------------------------------------------------
DSH_BIN=${DSH_BIN:-$(command -v dsh 2>/dev/null || true)}
if [ -z "${DSH_BIN}" ]; then
  echo "[dsh-pure] PATH 里找不到 dsh；用 DSH_BIN=/path/to/dsh 指定" >&2
  exit 127
fi
if [ -x "${DSH_BIN}" ]; then
  DSH_CMD=("${DSH_BIN}")            # 带 shebang 且可执行，直接跑
else
  NODE_BIN=${DSH_NODE:-$(command -v node 2>/dev/null || true)}
  if [ -z "${NODE_BIN}" ]; then
    echo "[dsh-pure] ${DSH_BIN} 不可执行，且 PATH 里找不到 node；用 DSH_NODE=/path/to/node 指定" >&2
    exit 127
  fi
  DSH_CMD=("${NODE_BIN}" "${DSH_BIN}")
fi

PROFILE=${DSH_PURE_PROFILE:-pure}
TEMPLATE=${DSH_PURE_TEMPLATE:-web}
# 与 dsh 自己的口径一致：DSH_HOME 优先，否则 ~/.dsh。
# 引号里的 ~ 不会自动展开，手工处理开头这一个。
DSH_HOME_DIR=${DSH_HOME:-${HOME}/.dsh}
case "${DSH_HOME_DIR}" in "~/"*) DSH_HOME_DIR=${HOME}/${DSH_HOME_DIR#\~/} ;; esac
PROFILE_DIR=${DSH_HOME_DIR}/profiles/${PROFILE}

# ---- 首次使用：创建纯净 profile（--dump-config 只组合、不启动）-------------
if [ ! -f "${PROFILE_DIR}/package.json" ]; then
  echo "[dsh-pure] 首次创建纯净 profile：${PROFILE_DIR}（出厂 ${TEMPLATE} 模板）"
  if ! "${DSH_CMD[@]}" --profile "${PROFILE}" --from-default-profile "${TEMPLATE}" --dump-config >/dev/null; then
    echo "[dsh-pure] 创建失败：确认 dsh 可用，且 '${TEMPLATE}' 是这套安装里有的出厂模板" >&2
    exit 1
  fi
fi

# ---- 选端口：从首选端口起连续试 5 个 ---------------------------------------
# 端口上"有人在听"就算被占用 —— 纯净模式最常见的场景正是正常服务还占着端口。
# curl 不在时退回 bash 的 /dev/tcp；两者都不可用就当它空闲，交给 dsh 自己报错。
listening() {
  local port=$1 code
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:${port}/" 2>/dev/null || true)
    case "${code}" in ''|000) return 1 ;; *) return 0 ;; esac
  fi
  (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
}

PREFERRED=${DSH_PURE_PORT:-3080}
PORT=
if [ "${PREFERRED}" = "0" ]; then
  PORT=0   # 交给内核挑一个空闲端口，URL 在启动横幅里
else
  for offset in 0 1 2 3 4; do
    candidate=$((PREFERRED + offset))
    if ! listening "${candidate}"; then PORT=${candidate}; break; fi
  done
fi
if [ -z "${PORT}" ]; then
  echo "[dsh-pure] ${PREFERRED} 起连续 5 个端口都被占用；先停掉占用者，或用 DSH_PURE_PORT 换一段端口" >&2
  exit 1
fi

echo "[dsh-pure] 纯净模式：profile=${PROFILE}（出厂 ${TEMPLATE} 模板，不含任何自装插件）"
if [ "${PORT}" != "${PREFERRED}" ]; then
  echo "[dsh-pure] 注意：${PREFERRED} 已被占用，本次监听 ${PORT}"
fi
echo "[dsh-pure] 修插件（不需要 dsh 能启动）：dsh plugin --profile <你的正常 profile> remove|add <包名>"
echo "[dsh-pure] 提醒：守护/重启脚本若按 'dsh web' 匹配进程，看不到本服务（--profile ${PROFILE}），别让它重复拉起"

# ---- 工作目录：默认留在当前目录（会话工作区以它为起点）---------------------
if [ -n "${DSH_PURE_CWD:-}" ]; then
  if [ -d "${DSH_PURE_CWD}" ]; then
    cd "${DSH_PURE_CWD}" && echo "[dsh-pure] 工作目录=${DSH_PURE_CWD}"
  else
    echo "[dsh-pure] DSH_PURE_CWD=${DSH_PURE_CWD} 不是目录，留在当前目录" >&2
  fi
fi

exec "${DSH_CMD[@]}" --profile "${PROFILE}" --port "${PORT}" "$@"
