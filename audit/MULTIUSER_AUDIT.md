# cudo 多用户安装与共享注册表审计

审计日期：2026-10-17（Asia/Shanghai）。基线：`6b03030eb5f9c41007a4c5a677a1c5defe158286`，克隆时 master 指向该提交。全部修改仅在本地分支；未推送、未修改服务器，也未重跑远端 CI。

## 结论与适用范围

当前系统安装的共享注册表不应继续作为多用户之间的可信数据源。最小修复应共享只读程序、隔离每个用户的可写状态，而不是仅把 `777` 改成 `1777` 或 `2770`。

提供的补丁将两种安装模式统一到调用者的 `~/.local/share/cudo-global`：目录 0700，新建/原子替换文件 0600。`CUDO_GLOBAL_CONFIG_DIR` 可以覆盖，但必须指向调用者拥有的私有目录。目录、祖先和条目校验失败时，在扫描注册表、同步项目或调用 Docker 之前拒绝执行。root 默认 home 来自 UID 0 的 passwd 条目，不使用继承的 HOME。

这支持多人在同一服务器上各自管理项目，但有意取消了原来的“所有人的项目放进同一可写注册表”。`list/enter/rename/cleanup` 均只覆盖当前用户。**补丁没有实现全服务器共享项目发现、跨用户共同编辑同一项目或 Docker/GPU 租户隔离。** 如需共享发现，见后文的独立只读目录方案。

## 已确认问题（源码可证；未将推演标为实际利用）

| 问题 | 基线证据 | 后果/边界 |
|---|---|---|
| 系统目录无 sticky bit、全员可写 | `install.sh:install_cudo` 对 `/var/lib/cudo-global` 执行 chmod 777 | 对目录有 wx 的用户通常可删除、重命名、替换其他人的文件；不要求对被删除文件有写权限。原用户描述的“只能修改自己有权限的文件”不足以涵盖目录项替换。未在本环境真实双 UID 利用。 |
| 目录可写被当作修改全部记录的依据 | `GLOBAL_CONFIG_WRITABLE`、`sync_global_env_names`、`update_global_status`、`cleanup_deleted_projects`、`cleanup_old_global_configs` | 未检查逐记录所有者；可能更新他人记录、清理他人状态。临时文件加 mv 也可能替换只读于自己的记录。 |
| 注册表包含敏感信息 | `save_to_global` 写入 `SSH_PASSWORD_HASH_B64`；回滚/迁移还支持 `SSH_PASSWORD_B64` | 前者可离线猜测，后者是可逆编码；默认 umask 022 下 cat 创建的记录可为 0644。是否真实暴露取决于实际 umask、目录和文件权限。补丁保留既有运行时字段以避免破坏回滚，但改为私有存储。 |
| 普通用户安装的列表读取路径不一致 | 安装器替换 shell 的 GLOBAL_CONFIG_DIR；Python helper 仍默认 `/var/lib/cudo-global`；shell 未导出安装后默认值 | 无外部环境变量时，个人 build/注册与 list 可能读写不同注册表。系统安装与用户安装切换也会切换可见项目集合。 |
| 路径重定向/文件类型未校验 | 安装器 mkdir/cp/chmod；注册表 cat、临时文件、find/glob 读取 | 在攻击者可写的父目录里，可预置 symlink；写入可能跟随链接。提升为任意 root 写入需要 root 后续执行相关路径、目标存在及系统软链接防护等条件，未实际验证提权。 |
| 不可访问被当作不存在 | `update_global_status` 用 `-d "$project_path/.cudo"` 判断 | 用户无权穿越他人的私有 home 时，可误标 deleted；cleanup 继续删除记录。私有注册表消除默认跨用户扫描，但本人权限失效/NFS 故障仍可能产生类似误判。 |
| 环境名全局占用，哈希未按 UID 分区 | `env_name_exists`、按 hash 查找、`cuda-project-${hash}-container` | 其他用户可占用名称；项目复制或相同 hash 可混淆项目/容器。补丁隔离注册表名称；**没有改变既有 Docker 容器 hash 命名**。跨用户复制已有 `.cudo` 的容器身份冲突仍需处理。 |
| root/user 混用造成所有权冲突 | sudo 执行项目命令创建 `.cudo` 文件；普通用户之后继续使用 | 私有注册表不能自动修复 root-owned 项目文件。不要以 sudo 运行普通用户项目命令。 |
| CI 没有安装测试 | workflow fast 只跑 shellcheck、fast mocks 和 GPU Python 单测；不执行 install.sh | 不能据 fast 失败推断安装失败；以前 fast 通过也不能证明两种安装模式正确。 |
| shellcheck 标准不一致 | workflow 用 `--severity=error`，fast 中再次运行不带该选项 | warning/info 可使 fast 的 syntax 子测试失败；这是可疑独立原因，**没有旧日志或本机 ShellCheck 运行结果，不能认定为本次历史根因**。 |
| 测试可能漏报中间断言失败 | test_case 通过 `if function` 调用，函数中部分断言不显式传播返回码 | Bash 在这种调用上下文中不依赖 errexit；本地已观察 JSON 解析报错却显示 PASS。补丁修复该 JSON 断言，未全面重写全部历史测试。 |

源码链接：[安装器](https://github.com/IMath123/cudo/blob/6b03030eb5f9c41007a4c5a677a1c5defe158286/install.sh)、[主程序](https://github.com/IMath123/cudo/blob/6b03030eb5f9c41007a4c5a677a1c5defe158286/cudo)、[列表工具](https://github.com/IMath123/cudo/blob/6b03030eb5f9c41007a4c5a677a1c5defe158286/scripts/cuda-env-list-simple.py)、[CI](https://github.com/IMath123/cudo/blob/6b03030eb5f9c41007a4c5a677a1c5defe158286/.github/workflows/test.yml)。

## 最小权限方案

| 对象 | 所有者/权限 | 普通用户权限 |
|---|---|---|
| 系统可执行文件与 helper | root；目录/可执行文件 0755，Python 模块 0644 | 读取/执行，不得修改 |
| 个人可执行文件与 helper | 当前 UID；位于其受信任 home | 仅所有者维护；不能把这种可修改版本当作管理员信任的程序 |
| 每用户注册表 | 当前 UID，0700 | 本人读写；不读取/同步其他 UID 注册表 |
| 新注册记录和配置更新 | 当前 UID，0600；mktemp 后 rename | 避免暴露哈希、半写文件；没有跨文件事务或完整并发串行化 |
| 旧 `/var/lib/cudo-global` | 管理员验证真实目录后封存为 root-only | 新程序不自动使用、导入或递归修复 |
| GPU agent socket | 现有 root 管理的 `/run/cudo` 0755，socket 0666 | 连接不等于允许任意 PID 查询；agent 通过 SO_PEERCRED 获得调用进程 PID，并按容器 cgroup 过滤 |

为什么不只改 chmod：

- 1777 只能约束删除/重命名，不会防读取、命名抢占、错误的全局状态维护，也不会让程序正确处理逐文件权限失败。
- root:cudo 2770 允许组内互相影响，只有整个组作为同一信任域时才合适；它不是用户隔离。
- root-owned 0755 父目录 + 管理员预建 UID/0700 子目录也可实现私有注册表，但需要用户开通/迁移流程；本补丁选择 home 内私有目录以保留无 root 安装能力。

如业务需要“所有用户看到公共环境清单”，应单独提供 root 管理的只读 inventory（目录 0755、公开记录 0644），只发布 UID、显示名、CUDA 版本等非敏感字段。不能把其中的 PROJECT_PATH、mount 或 container ID 直接作为可写管理操作的授权。自主发布需要一个窄权限代理：使用内核 peer credentials 确定 UID，每个 UID 只能发布自己的条目，采用原子更新和限额；不接受用户自行声明 OWNER。此代理及 inventory **属于建议，不在当前补丁中**。

## 补丁具体行为

1. root 安装不再创建或 chmod 共享注册表；普通用户安装也不把安装时 HOME 写死到主程序里。
2. 新 `scripts/cudo_paths.py` 检查路径必须绝对、无 `..`；使用目录 fd 和 O_NOFOLLOW 打开各层，拒绝 symlink。祖先只能由 root/当前 UID 拥有，且不可被其他用户写入（root-owned sticky 临时父目录例外）。最终注册表必须当前 UID 所有且没有 group/other 权限。
3. 拒绝 registry 中非普通文件、symlink、hardlink、foreign owner、group/other 可写文件。已有 0644 记录在私有目录下允许读取；不会自动扫描外部目录或迁移历史内容。
4. 安装目标预检查拒绝已有 symlink/hardlink/非普通文件/他人拥有或可写文件。显式设置程序和 helper 的模式，避免继承调用者 umask 077 而导致系统安装不可读。
5. shell 导出已校验的注册表路径，Python helper 用相同规则；read-only 命令不创建目录。`doctor` 对尚未创建的多层私有路径检查最近存在的父目录。
6. 新建项目状态用 umask 077；本地配置和注册记录用安全临时文件后替换；set/remove-config 的固定 PID 临时名替换为 mktemp。查找限制在一层，项目路径匹配改为固定字串整行匹配。
7. 不再在安装 Docker 时悄悄把 SUDO_USER 加入 root 等价的 docker 组。
8. CI 加入安装/权限回归，将 ShellCheck severity 统一为 error，并覆盖 installer。修复 doctor 对 systemctl stdout 的抑制及 JSON 测试返回值传播。

## 迁移与兼容性

1. 停止旧版本进程，备份；确认 PATH 上个人版本与系统版本的实际优先级，避免混用新旧程序。审计并移除旧 CUDO_GLOBAL_CONFIG_DIR 环境变量。
2. 管理员先 lstat 验证 `/var/lib/cudo-global` 是预期的 root-owned 真目录，再将其封存为 0700。**本补丁不自动触碰历史目录**，所以仅升级不会撤销旧目录的已有暴露；封存是部署必须完成的步骤。
3. 不盲信历史注册记录的 owner 或路径：在 777 目录中攻击者可能已替换它。由项目所有者从可信项目配置重新注册；重建可能影响现有镜像/容器，应先确认备份和操作窗口。
4. 现有个人注册表若是 0755 将被拒绝：核验它的 owner、链接和条目后改为 0700，普通记录改 0600。历史 `.cudo/config` 也单独检查。已暴露的哈希/旧 Base64 密码应轮换。
5. 默认 home 带空格/单引号的安装路径已有回归用例；但 symlink home 被主动拒绝，可用真实规范路径指定私有 registry。ACL、NFS root-squash、自动挂载和容器 namespace 兼容性必须在目标服务器验证。
6. 多人可用相同环境显示名；跨用户 `enter`/`rename` 不再由公共注册表支持。共同开发同一个可写 `.cudo` 仍不在 UID 隔离模型内。

## CI 取证与运行结果

针对 [run 36823226688](https://github.com/IMath123/cudo/actions/runs/36823226688)，GitHub API 返回 fast=failure（job 110243124947）、integration=skipped（job 110243126160）。fast 日志请求返回 404 BlobNotFound，steps 为空。因此不能还原实际失败命令或错误栈。

integration 的 workflow 条件是 `github.event_name == 'workflow_dispatch'`；没有 `needs: fast`。所以它被跳过不能解释为 fast 失败后的连锁跳过。

基线和修复后均运行了 fast 测试。本环境没有 Docker/GPU、ShellCheck，也禁止创建 AF_UNIX socket；UID/GID 映射仅包含 0。结果：

| 验证 | 结果 | 能证明什么 |
|---|---|---|
| 补丁新增权限/安装测试（11 项） | 9 通过、2 跳过 | 私有目录、危险模式/链接拒绝、不创建只读状态、危险 cleanup 拒绝、root HOME 隔离、staged root 安装和 installed list 已运行 |
| 真实双 UID 文件操作、普通用户安装（含带引号 HOME） | 本机 UID 不可映射，跳过 | **未验证**；CI 中 sudo + CUDO_REQUIRE_MULTIUSER_TESTS=1 要求真实执行，不能跳过 |
| fast 原有 23 项 | 22 通过、1 失败 | 失败为 GPU 客户端真实 AF_UNIX socket 被环境拒绝；不能当成历史 CI 根因 |
| GPU Python 单测 7 项 | 6 通过、1 socket 错误 | 其余逻辑单测运行；不等于真实 GPU/容器隔离验证 |
| bash -n、Python 编译、git diff --check | 通过 | 基本语法和补丁格式 |
| ShellCheck | 未安装，未运行 | CI severity 不一致已从源码修正；不能报告 ShellCheck 通过 |
| 真实 root 安装/包安装/systemd/GPU integration | 未运行 | root 回归用临时前缀、fake systemctl；未对宿主 `/usr`、`/etc` 或 Docker 做安装操作 |

基线 doctor JSON 的额外内容来自本环境的 systemctl wrapper 向 stdout 打印提示；同时测试函数忽略中间失败。补丁抑制该输出并显式传播 JSON 断言失败。这个本地现象同样不能证明 GitHub 上的失败原因。

**可支持的 CI 结论：没有证据表明旧 fast 失败由安装逻辑造成；当时 fast 不执行安装器。日志缺失使历史根因仍未确定。** 新测试应在普通 Linux CI/目标服务器运行后再决定合入与部署。

## 仍需考虑的安全边界与潜在风险

- rootful Docker 的 docker 组/socket 本身提供 root 等价能力。[Docker 官方文档](https://docs.docker.com/engine/install/linux-postinstall/) 明确说明这一点。0700 不能隔离有此能力的恶意用户。互不信任用户需要管理员调度、隔离运行时/daemon 或 VM；NVIDIA/rootless 支持需单独测试。
- agent socket 0666 与目录 777 不是同一种漏洞。现有 agent 按 SO_PEERCRED/cgroup 过滤，且 systemd 有 NoNewPrivileges、ProtectSystem 等限制；但服务默认 root、串行处理、每次请求触发 nvidia-smi，可能遭受请求洪泛；PID 退出/复用和特殊 cgroup 布局也需专项压力/集成测试。没有确认越权泄漏。
- 安装器仍支持远程 Docker 安装管道、apt-key/apt-get 和 dpkg 检测，未成为跨发行版安装器。systemctl 存在不代表 systemd 可用；依赖安装失败可能产生部分状态。没有对这些路径作实机验证。
- root 执行另一个用户可写 checkout/项目、继承不可信 PATH/PYTHONPATH，或读取不可信 Docker Compose，本来就跨越信任边界；仅校验 registry 不能使这些操作安全。
- 目录校验保护不同无特权 UID；不防同 UID 恶意进程、root、具备特权能力的攻击者。ACL 和共享网络文件系统未专项验证。文件原子替换不等于多步骤事务；同 UID 并发更新仍可能丢失逻辑修改。
- 8 位项目 hash 的碰撞、跨用户复制项目保留 hash、SSH 端口争用和 GPU 资源争抢未解决。不要把注册表补丁宣称为完整多租户系统。

## 应用和回归

在基线提交上，先检查再应用提供的 patch：

```bash
git switch -c fix/private-user-registry
git apply --check /path/to/cudo-multiuser.patch
git apply /path/to/cudo-multiuser.patch
python3 tests/test_permissions.py
sudo env CUDO_REQUIRE_MULTIUSER_TESTS=1 /usr/bin/python3 tests/test_permissions.py
./tests/run_all_tests.sh
shellcheck --severity=error cudo install.sh get-cudo.sh tests/*.sh
# 在管理员批准的隔离 Docker/NVIDIA 测试主机上：
./tests/run_all_tests.sh --integration
```

补丁未自动创建 PR、发布版本或重跑远端 workflow。
