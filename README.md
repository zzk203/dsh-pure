# dsh 纯净模式（只加载出厂随附插件）

> 一个 bash 启动器：在第三方插件把 dsh 启动搞崩之后，仍然能起一个**能用的 GUI**，
> 好让 agent 去把插件修回来。启动器：[`dsh-pure.sh`](./dsh-pure.sh)

## 它解决什么问题

dsh 的启动是 **fail-loud**：只要组合里有一个自装（第三方）bundle 在启动期抛错，
整棵树就会被 dispose、进程 `exit 1`、端口没人监听 —— GUI 直接消失。而"打开插件市场
把坏插件卸掉"这条路同时是死的，因为市场自己就是被炸掉的组合里的一个插件。

官方做破坏性更新（换大版本、删旧导出、改 peer 依赖）之后，这种情况最容易发生。

**纯净模式 = 另建一个 profile，bundle 列表只有出厂随附的模板**（web 模板 =
`@deepseek-ai/dsh-base` + `@deepseek-ai/dsh-web-app`）。它和正常 profile **共用同一个
`$DSH_HOME`**，所以会话历史、`settings.yaml`、`.credentials.yaml`、agent preset
全都在 —— 起来就能让 agent 去修插件。它不改 dsh 本身的任何文件，官方升级不会覆盖它。

## 前置条件

- 已经装好 dsh，`dsh` 在 `PATH` 里（`dsh --version` 能跑）
- `bash`；`node` 在 `PATH` 里（或 `dsh` 本身可执行、不需要 node）
- 可选：`curl`（判断端口占用用；没有就退回 bash 的 `/dev/tcp`）

## 用法

```bash
git clone https://github.com/zzk203/dsh-pure.git
cd dsh-pure
./dsh-pure.sh
```

只想拿脚本也可以：

```bash
curl -fsSLO https://raw.githubusercontent.com/zzk203/dsh-pure/main/dsh-pure.sh
chmod +x dsh-pure.sh && ./dsh-pure.sh
```

三种写法启动的是**同一个纯净服务**，只差两个开关：**首选端口**和**要不要自动打开浏览器**。

```bash
./dsh-pure.sh                      # ① 手动救火：首选 3080，自动开浏览器
./dsh-pure.sh --no-open            # ② 脚本 / agent 里拉起：同样端口，不开浏览器
DSH_PURE_PORT=19000 ./dsh-pure.sh  # ③ 指定首选端口：19000
```

| 写法 | 首先试 | 被占用时 | 浏览器 | 什么时候用 |
|---|---|---|---|---|
| ① `./dsh-pure.sh` | 3080 | 3081→3082…（连续试 5 个） | 自动打开带 token 的页面 | 在终端救火，想立刻看到 GUI |
| ② `./dsh-pure.sh --no-open` | 3080（同 ①） | 同上 | 不开；地址打在 stdout | 脚本 / systemd / agent 里拉起，没人能点浏览器 |
| ③ `DSH_PURE_PORT=19000 ./dsh-pure.sh` | 19000 | 19001→19002… | 自动打开 | 想固定端口，或那段端口被别的东西占着 |

② 和 ① 只差浏览器；③ 只改"第一个候选端口"，可以和 ①② 叠加：
`DSH_PURE_PORT=19000 ./dsh-pure.sh --no-open` = 固定 19000 且不开浏览器。
其余参数（`--host`、`--trusted-host`…）原样透传给 `dsh web`。

### 端口是怎么定的

- 默认首选 **3080**，也就是 `dsh web` 的出厂默认端口 —— 正常服务停着的时候，
  纯净服务和平时是同一个 URL，书签不用改。
- 首选被占用就往后连续试 5 个（3080→3081→…；`DSH_PURE_PORT=19000` 时是 19000→19001→…），
  并打一行 `注意：xxx 已被占用，本次监听 yyy`。
- 占用判断是"端口上有人在听"：`curl` 拿到任何 HTTP 状态码（**包括 401**）都算占用，
  所以不能只看 200；`curl` 不在时用 bash 的 `/dev/tcp` 连一下。
- 首选被**没坏透的正常服务**占着时，纯净服务会自动落到下一个端口：
  两个页面并排开着对比，是排查插件故障最顺手的姿势。
- `DSH_PURE_PORT=0` → 交给内核随机挑，端口看启动横幅。
- 想先确认某个端口空着（`000` = 没人听）：

  ```bash
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 http://127.0.0.1:3080/
  ```

### URL 和 token

- 不带 `--no-open`：`dsh web` 自己用默认浏览器打开**带 token** 的地址，不用手抄。
- 带 `--no-open`：从 stdout（或日志）里复制这一行：

  ```
  dsh web: http://127.0.0.1:3080/?token=xxxxxxxx
  ```

- 不带 token 直接访问 `http://127.0.0.1:3080/` 会返回 **401** —— 这是鉴权，不是故障。

### 怎么停

- 前台跑：`Ctrl-C`。
- 后台 / 脚本跑的，按端口找进程再杀：

  ```bash
  # Linux
  PID=$(ss -ltnpH 'sport = :3080' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2); kill "$PID"
  # macOS
  PID=$(lsof -ti tcp:3080); kill "$PID"
  ```

- ⚠️ 如果你的守护 / 重启脚本是按 `dsh web` 匹配进程的，它**看不到**纯净模式的服务
  （真实命令行是 `dsh --profile pure …`），有可能在同一个端口上再拉一个。
  纯净模式运行期间，别让那类脚本自动拉起服务。

### 第一次运行会做什么

- 自动创建 `<DSH_HOME>/profiles/pure`（默认 `~/.dsh/profiles/pure`），内容取自
  出厂 `web` 模板：`@deepseek-ai/dsh-base` + `@deepseek-ai/dsh-web-app`，之后直接启动。
- 不改 dsh 的任何文件，官方升级不会覆盖它。
- 验证组合（boot-free，只组合不启动；比正常 profile 少的行正好是你的第三方插件）：

  ```bash
  dsh --profile pure --dump-config | tail -20
  ```

### 环境变量

| 变量 | 默认 | 作用 |
|---|---|---|
| `DSH_PURE_PORT` | `3080` | 首选端口；`0` = 内核随机 |
| `DSH_PURE_PROFILE` | `pure` | 纯净 profile 名（换名等于再建一个） |
| `DSH_PURE_TEMPLATE` | `web` | 用来创建纯净 profile 的出厂模板（`web` / `headless` / `acp` / `sdk` / `sdk-minimal`） |
| `DSH_PURE_CWD` | 当前目录 | 启动时切到的目录 = 会话工作区起点 |
| `DSH_BIN` | `PATH` 里的 `dsh` | dsh 入口 |
| `DSH_NODE` | `PATH` 里的 `node` | 仅在 dsh 不能直接执行时用到 |
| `DSH_HOME` | `~/.dsh` | 会话 / 设置 / 凭据所在（与正常模式同一份） |

> `DSH_PURE_TEMPLATE` 换成别的模板时，`--port` / `--no-open` 这些是 **web 应用**的参数，
> 要按对应应用的参数传（先看看 `dsh --profile <模板> --help`）。

## 覆盖不到的情况（要手工修文件，纯净模式也救不了）

| 故障 | 处理 |
|---|---|
| `settings.yaml` 语法坏（出厂 settings 行自己抛错） | `mv ~/.dsh/settings.yaml{,.bak}` |
| `.credentials.yaml` 坏 | `mv ~/.dsh/.credentials.yaml{,.bak}` |
| `~/.dsh/cordis.patch.yml`（home 层）坏 | 修或删掉它 —— 所有 profile 都会读 |
| 出厂 bundle 自身与你的定制不兼容 | 用 `--from-default-profile` 换个模板重建，或临时 `git stash` |

## 为什么不用 `--patch` 按行禁用

`dsh web --patch 禁用.yml`（`- id: <行id>` + `disabled: true`）能救"插件代码抛错"
（被禁用的行根本不会被 import），但它：① 要手工维护行 id；② 救不了 bundle 的
`cordis.patch.yml` 语法坏、依赖装坏/被删这两类 —— 层在 patch 生效之前就解析失败，
连 `--dump-config` 都会一起死。纯净 profile 一次覆盖全部四类插件故障。
