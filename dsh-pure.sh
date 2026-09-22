#!/bin/bash
# 纯净模式启动 dsh web —— 只加载出厂随附插件。
#
# 为什么需要它：官方做破坏性更新后，web profile 里任何一个第三方 bundle
# （dshmarket / dsh-cost-meter / dsh-better-sidebar / dsh-geo-workflow）在启动期
# 抛错，`dsh web` 整棵树 fail-loud 退出（exit 1），18080 没人监听 → GUI 没了；
# 而此时"用市场卸载坏插件"这条路也是死的，因为市场自己就是被炸掉的组合里的插件。
#
# 做法：另一个 profile（默认名 pure），bundle 列表只有出厂随附的两个：
#   @deepseek-ai/dsh-base + @deepseek-ai/dsh-web-app
# 它和 web profile 共用同一个 $DSH_HOME，所以会话历史、settings.yaml、
# .credentials.yaml、agent preset 全都在 —— 起来就能让 agent 去修插件。
#
# 不改 deepseek-harness 里的任何文件，官方升级不会覆盖它。
#
# 仓库：https://github.com/zzk203/dsh-pure（同目录的 dsh-纯净模式.md 是完整使用说明）
#
# 用法（三者只差"首选端口"和"要不要自动开浏览器"）：
#   ./dsh-pure.sh                     # 首选 18080；被占则 18081/18082…；自动打开浏览器
#   ./dsh-pure.sh --no-open           # 同上端口，但不开浏览器：从 stdout 复制带 token 的 URL
#   DSH_PURE_PORT=19000 ./dsh-pure.sh # 首选 19000；被占则 19001/19002…
#   DSH_PURE_PROFILE=rescue ./dsh-pure.sh   # 换一个纯净 profile 名
#
# 其它可调环境变量：
#   DSH_BIN  /usr/local/bin/dsh    DSH_NODE  PATH 里的 node
#   DSH_PURE_CWD  /home/zzk/geo    启动时的工作目录（=会话工作区起点）
set -u

DSH_BIN=${DSH_BIN:-/usr/local/bin/dsh}
PROFILE=${DSH_PURE_PROFILE:-pure}
NODE_BIN=${DSH_NODE:-$(command -v node)}
# 与 dsh 自己的口径一致：DSH_HOME 优先，否则 ~/.dsh
DSH_HOME_DIR=${DSH_HOME:-${HOME}/.dsh}
PROFILE_DIR=${DSH_HOME_DIR}/profiles/${PROFILE}

# 首次使用：从出厂 web 模板创建纯净 profile（--dump-config 只组合、不启动）。
if [ ! -f "${PROFILE_DIR}/package.json" ]; then
  echo "[dsh-pure] 首次创建纯净 profile：${PROFILE_DIR}"
  "${NODE_BIN}" "${DSH_BIN}" --profile "${PROFILE}" --from-default-profile web --dump-config >/dev/null || {
    echo "[dsh-pure] 创建失败，请检查 '${DSH_BIN}' 是否可用" >&2
    exit 1
  }
fi

# 端口占用判断沿用你现有脚本的口径：200 和 401 都算"有人在听"。
listening() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$1/" 2>/dev/null || true)
  [ "$code" = "200" ] || [ "$code" = "401" ]
}

PREFERRED=${DSH_PURE_PORT:-18080}
PORT=
if [ "${PREFERRED}" = "0" ]; then
  PORT=0   # 交给内核挑一个空闲端口（排障用，URL 会在启动横幅里打印）
else
  # 从首选端口起连续试 5 个：18080→18081→…，19000→19001→…
  for offset in 0 1 2 3 4; do
    candidate=$((PREFERRED + offset))
    if ! listening "${candidate}"; then PORT=${candidate}; break; fi
  done
fi
if [ -z "${PORT}" ]; then
  echo "[dsh-pure] ${PREFERRED} 起连续 5 个端口都被占用；先停掉在用服务，或用 DSH_PURE_PORT 指定别的端口" >&2
  exit 1
fi

echo "[dsh-pure] 纯净模式：profile=${PROFILE}（只含 @deepseek-ai/dsh-base + @deepseek-ai/dsh-web-app）"
if [ "${PORT}" != "${PREFERRED}" ]; then
  echo "[dsh-pure] 注意：${PREFERRED} 已被占用，本次监听 ${PORT}（可能就是那个没坏透的正常服务）"
fi
echo "[dsh-pure] 修插件：dsh plugin --profile web remove|add <包名>；修完用 /home/zzk/geo/restart-dsh-web.sh 回到正常模式"
echo "[dsh-pure] 纯净模式期间不要跑 restart-dsh-web.sh —— 它按 'dsh web' 匹配进程，看不到这个服务"

# 工作目录跟正常服务保持一致（会话的工作区、相对路径都以它为起点）。
RUN_CWD=${DSH_PURE_CWD:-/home/zzk/geo}
if [ -d "${RUN_CWD}" ]; then cd "${RUN_CWD}" && echo "[dsh-pure] 工作目录=${RUN_CWD}"; fi
exec "${NODE_BIN}" "${DSH_BIN}" --profile "${PROFILE}" --port "${PORT}" "$@"
