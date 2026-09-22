# dsh 纯净模式（只加载出厂随附插件）

> 仓库：<https://github.com/zzk203/dsh-pure>　启动器：[`dsh-pure.sh`](./dsh-pure.sh)

## 它解决什么问题

官方做破坏性更新后（`git pull` + 重新构建），web profile 里的第三方 bundle
只要有一个在启动期抛错，`dsh web` 就是 **fail-loud**：整棵树 dispose、进程 `exit 1`、
18080 没人监听 → GUI 直接消失。而"用插件市场把坏插件卸掉"这条路同时是死的——
市场自己就是被炸掉的组合里的插件。

纯净模式 = **另一个 profile，bundle 列表只有出厂随附的两个**：

```
@deepseek-ai/dsh-base  ＋  @deepseek-ai/dsh-web-app
```

它和正常模式**共用同一个 `~/.dsh`**，所以会话历史、`settings.yaml`、
`.credentials.yaml`、agent preset 全都在——起来就能让 agent 去修插件。

## 怎么用

三种写法启动的是**同一个纯净服务**，只差两个开关：**首选端口**和**要不要自动打开浏览器**。

```bash
cd /home/zzk/geo/dsh-pure
./dsh-pure.sh                      # ① 手动救火：首选 18080，自动开浏览器
./dsh-pure.sh --no-open            # ② 脚本 / agent 里拉起：同样端口，不开浏览器
DSH_PURE_PORT=19000 ./dsh-pure.sh  # ③ 固定端口：首选 19000
```

| 写法 | 首先试 | 被占用时 | 浏览器 | 什么时候用 |
|---|---|---|---|---|
| ① `./dsh-pure.sh` | 18080 | 18081→18082…（连续试 5 个） | 自动打开带 token 的页面 | 你自己在终端救火，想立刻看到 GUI |
| ② `./dsh-pure.sh --no-open` | 18080（同 ①） | 同上 | 不开；地址打在 stdout | 脚本 / systemd / agent 里拉起，没人能点浏览器 |
| ③ `DSH_PURE_PORT=19000 ./dsh-pure.sh` | 19000 | 19001→19002… | 自动打开 | 想固定端口，或 18080 被别的东西长期占着 |

② 和 ① 只差浏览器；③ 只改"第一个候选端口"，可以和 ①② 叠加：
`DSH_PURE_PORT=19000 ./dsh-pure.sh --no-open` = 固定 19000 且不开浏览器。
其余参数（`--host`、`--trusted-host`…）原样透传给 `dsh web`。

### 端口是怎么定的

- 默认首选 **18080**——故意和正常服务同一个 URL，浏览器书签不用改。
- 首选被占用就往后连续试 5 个（18080→18081→…；`DSH_PURE_PORT=19000` 时是 19000→19001→…），
  并打一行 `注意：xxx 已被占用，本次监听 yyy`。
- 占用判断沿用你现有脚本的口径：`curl` 拿到 `200` 或 `401` 都算"有人在听"。
- 18080 被**没坏透的正常服务**占着时，纯净服务会自动落到 18081：两个页面并排开着对比，
  是排查插件故障最顺手的姿势。
- `DSH_PURE_PORT=0` → 交给内核随机挑，端口看启动横幅。
- 想先确认某个端口空着（`000` = 没人听）：

  ```bash
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 http://127.0.0.1:19000/
  ```

### URL 和 token

- 不带 `--no-open`：`dsh web` 自己用默认浏览器打开**带 token** 的地址，不用手抄。
- 带 `--no-open`：从 stdout（或日志）里复制这一行：

  ```
  dsh web: http://127.0.0.1:18080/?token=xxxxxxxx
  ```

- 不带 token 直接访问 `http://127.0.0.1:18080/` 会返回 **401**——这是鉴权，不是故障。

### 怎么停

- 前台跑：`Ctrl-C`。
- 后台 / 脚本跑的，按端口找进程再杀：

  ```bash
  PID=$(ss -ltnpH 'sport = :18080' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2); kill "$PID"
  ```

- ⚠️ 纯净服务运行期间**别跑** `/home/zzk/geo/restart-dsh-web.sh`：它按 `dsh web` 匹配进程，
  看不到 `dsh --profile pure …` 这个服务，却可能在 18080 上再拉一个。

### 第一次运行会做什么

- 自动创建 `~/.dsh/profiles/pure`（用出厂 `web` 模板：只含
  `@deepseek-ai/dsh-base` + `@deepseek-ai/dsh-web-app`），之后直接启动。
- 没改 `deepseek-harness` 的任何文件，官方升级不会覆盖它。
- 验证组合（boot-free，只组合不启动；正常模式 156 行，纯净模式 152 行，
  少的正好是那 4 个第三方行）：

  ```bash
  node /usr/local/bin/dsh --profile pure --dump-config | tail -20
  ```

### 可调环境变量

| 变量 | 默认 | 作用 |
|---|---|---|
| `DSH_PURE_PORT` | `18080` | 首选端口；`0` = 内核随机 |
| `DSH_PURE_PROFILE` | `pure` | 纯净 profile 名（换名等于新建一个） |
| `DSH_PURE_CWD` | `/home/zzk/geo` | 启动时工作目录 = 会话工作区起点 |
| `DSH_BIN` | `/usr/local/bin/dsh` | dsh 入口 |
| `DSH_NODE` | PATH 里的 node | 用哪个 node 跑 |
| `DSH_HOME` | `~/.dsh` | 会话 / 设置 / 凭据所在（与正常模式同一份） |

## 覆盖不到的情况（要手工修文件，纯净模式也救不了）
| 故障 | 处理 |
|---|---|
| `~/.dsh/settings.yaml` 语法坏（官方 settings 行抛错） | `mv ~/.dsh/settings.yaml{,.bak}` |
| `~/.dsh/.credentials.yaml` 坏 | `mv ~/.dsh/.credentials.yaml{,.bak}` |
| `~/.dsh/cordis.patch.yml`（home 层）坏 | 修或删掉它——所有 profile 都会读 |
| 出厂 bundle 自身与你的定制不兼容 | 换 `--from-default-profile` 的模板重建，或临时 `.git stash` |

## 为什么不用 `--patch` 按行禁用
`dsh web --patch 禁用.yml`（`- id: dsh-market` + `disabled: true`）能救"插件代码抛错"
（被禁用行根本不 import），但它：① 要手工维护行 id；② 救不了 bundle 的
`cordis.patch.yml` 语法坏、依赖装坏/被删这两类（层在 patch 生效前就解析失败，
连 `--dump-config` 都会一起死）。纯净 profile 一次覆盖全部四类插件故障。
