# bf3-repair

> Battlefield 3（Steam 版）启动失败 / 无法激活的**诊断与修复**工具集，外加一套不依赖 EA 服务器的
> **离线机器人对战**方案（Venice Unleashed）。

Windows · PowerShell 5.1+ · 无外部依赖 · 全程可逆

---

## 1. 项目解决什么问题

BF3 在 Steam 上（appid `1238820`）经常出现**点了没反应**：Steam 显示"正在启动"，几秒后按钮又变回"开始游戏"，
游戏从未真正运行过。网上流传的原因五花八门（重装 VC++、修注册表、换节点、重装 EA App……），
但绝大多数人从来没定位到真正的断点在哪。

本项目把这类故障拆成**可验证的检查项**逐条测量，最终定位到**两个叠加的原因**，并验证修复后启动链恢复：

> **A. EA 自己的"安装登记簿"里写着一个已经不存在的旧路径。**
> **B. 残留的 `EASteamLauncher` 实例会与新启动冲突（日志里明确报错后退出）。**

### 根因 A：安装登记簿指向旧地址

EA 通过 `C:\ProgramData\Origin\LocalContent\Battlefield 3\*.dat` 判断游戏装在哪、装全了没。
如果这些清单里的路径（例如 `C:\Program Files (x86)\Origin Games\Battlefield 3`）和游戏实际位置
不一致，EA App 就找不到文件。`HKLM\...\Origin Games\70619` / `71067` 也缺 `Install Dir`。
`BF3-Repair-EA.ps1` 用目录联接修掉这一层。

### 根因 B：残留启动器实例

EA 的启动接力链是：

```
Steam / BF3WebHelper.exe
   → EA Desktop（收到 origin://LaunchGame/70619,71067...?ProductId=DR:225064100）
   → EASteamLauncher.exe
   → 打开 Battlelog 网页 https://battlelog.battlefield.com/bf3/
   → 网页里通过 origin:// 协议拉起 bf3.exe
```

当机器上残留上一次的 `EASteamLauncher / EALaunchHelper / EASteamAuthHelper` 进程时，日志里会出现：

```
WARN  Another instance of EASteamLauncher is already running. Retrying. Attempt=[1]...[5]
ERROR Another instance of EASteamLauncher is still running after retries. Exiting.
```

它会**静默退出、不弹任何错误**。`BF3-Play.ps1` 现在会在启动前自动清理这些实例。

### 验证：修复后启动链恢复

三者齐备（目录联接 + 清理残留 + EA App 重新认证）后实测：

```
▶ 通过 Steam 启动 (appid 1238820)
  ✔ Battlelog 页面已打开（tab 数 11 → 12）
  ✔ 启动成功
```

即 EA 的 web launch 每次都会在浏览器里新开一个
`https://battlelog.battlefield.com/bf3/?intcmp=originclient` 的 tab。
该页面（构建版本 `140606`）目前仍然存活，带 Server Browser / Matches / Leaderboards，
登录 EA 账号后即可从网页进入战役或多人。

> ⚠️ **注意 EA 的 web launch 是「在已有窗口里新开 tab」，窗口数量不变。**
> 本项目早期版本按"新窗口"判断，导致明明启动成功却报失败 —— 现已改为统计 tab 数。

### 本机实测的完整证据链（供对照）

| 检查项 | 结果 |
| --- | --- |
| Steam 安装状态 | ✅ `StateFlags=4`，34.46 GB，11 个 depot 全装，含全部 5 个 DLC |
| 主程序完整性 | ✅ `bf3.exe` v1.6.0.0，**Electronic Arts 有效签名**，未被改动 |
| VC++ 2010 / PunkBuster / 网络 | ✅ 全部正常（EA 三个授权域名均可达） |
| EA App 进程与登录 | ✅ 已认证（`DesktopFSM[authenticated]`） |
| BF3 授权文件 | ✅ `71067.dlf` 存在（577 字节） |
| EA 内容清单路径 | ⚠ 指向不存在的旧路径 → 目录联接修复 |
| 残留启动器进程 | ⚠ 会出现 `Another instance of EASteamLauncher` → 自动清理 |
| 直接运行 `bf3.exe` | ℹ️ 退出码 0 —— **属正常**，它只是 Battlelog 的启动器 |
| **修复后启动** | ✅ **Battlelog 页面每次正常新开 tab** |

**这个项目做三件事：**

1. **量出来**：给出可复现的诊断，指出到底哪一环断了，而不是让你挨个试偏方。
2. **修掉它**：清理残留启动器 + 修 EA 清单路径（目录联接，可一键撤销）。
3. **绕过去**：如果官方链路彻底修不好（或 Battlelog 哪天关停），用 Venice Unleashed
   起本地服务器 + AI 机器人，完全不依赖 EA 后端也能玩 —— 这是 BF3 社区目前的通行做法。

---

## 2. 主要功能

| 脚本 | 功能 | 是否修改系统 |
| --- | --- | --- |
| **`BF3-Doctor.ps1`** | 全量诊断：安装完整性、Steam 记录、EA App 状态、**EA 内容清单与授权**、注册表、运行库、网络。默认**只读** | 默认否（`-Fix` 才改） |
| **`BF3-Repair-EA.ps1`** | **根治**：修正 EA 内容清单路径错位 —— 建目录联接 + 补注册表 `Install Dir` + 重启 EA App | 是（需 UAC，`-Undo` 可完整回滚） |
| **`BF3-Play.ps1`** | 启动器：**清理残留启动器** → EA App 认证 → Steam 拉起 → 直接拉起；把"Battlelog 页面已打开"也算作启动成功 | 否（只结束残留进程、启动新进程） |
| **`BF3-VU-Offline.ps1`** | 离线玩法：检查 VU 环境 / 生成本地机器人服务器配置 / 启动 | 只新增 `Server\` 配置与一个 `.bat` |
| **`BF3-Common.ps1`** | 公共库：自动定位 Steam 根目录、Steam 库、BF3 安装目录、EA App（被上面脚本 dot-source） | 否 |

**设计上的几个取舍：**

- **不硬编码盘符**：自动从 Steam 注册表项 + `libraryfolders.vdf` 解析所有 Steam 库，多处安装也能找到。
- **不改 EA 的二进制清单**：那几份 `.dat` 是私有格式（路径以 UTF-16LE 存放、带长度字段），手改容易写坏。
  用操作系统级的目录联接实现"只读穿透"，EA 读到的就是真实文件，且删除联接不影响目标目录。
- **失败要说人话**：每个检查项给出具体路径与判断依据，而不是笼统的"初始化失败"。

---

## 3. 安装方法

### 环境要求

- Windows 10 / 11
- Windows PowerShell 5.1（系统自带）或 PowerShell 7+
- 已安装 Steam 与 EA App
- 已安装《Battlefield 3》（Steam appid `1238820`）

### 获取

```powershell
git clone https://github.com/miaom4702-art/bf3-repair.git
cd bf3-repair
```

或直接下载 ZIP 解压（仅 `Release` 页的 `bf3-repair-v0.1.0.zip` 即可，无需其它依赖）。

### 首次运行前

PowerShell 默认禁止运行未签名脚本。任选一种：

```powershell
# 方式 A：只对当前进程放行（推荐，不改系统设置）
powershell -ExecutionPolicy Bypass -File .\BF3-Doctor.ps1

# 方式 B：允许当前用户运行本地脚本（一次性设置）
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

> `BF3-Repair-EA.ps1` 需要管理员权限，脚本会自己弹 UAC 提权，**无需**手动右键"以管理员身份运行"。

---

## 4. 使用方法

### 推荐流程

```powershell
# 第 1 步：先诊断，看清断在哪（只读，不修改任何东西）
.\BF3-Doctor.ps1

# 第 2 步：修根因（会弹 UAC，点"是"）
.\BF3-Repair-EA.ps1

# 第 3 步：启动游戏
.\BF3-Play.ps1
```

### 各脚本详细用法

#### `BF3-Doctor.ps1` —— 诊断

```powershell
.\BF3-Doctor.ps1                    # 只诊断（默认）
.\BF3-Doctor.ps1 -Fix               # 修复常规项（注册表 Install Dir、重启 Steam/EA App）
.\BF3-Doctor.ps1 -Fix -Deep         # 深度修复（额外备份并清理 EA App 缓存、重装 PunkBuster）
.\BF3-Doctor.ps1 -GamePath "E:\Games\Battlefield 3"   # 手动指定游戏目录
```

#### `BF3-Repair-EA.ps1` —— 根治

```powershell
.\BF3-Repair-EA.ps1                 # 建目录联接 + 补注册表 + 重启 EA App
.\BF3-Repair-EA.ps1 -Undo           # 撤销（删联接 + 移除补写的注册表值，游戏文件不动）
.\BF3-Repair-EA.ps1 -NoElevate      # 已以管理员身份运行时，跳过提权
```

它只做三件事：

1. 创建 `C:\Program Files (x86)\Origin Games\Battlefield 3` 的 **Junction**
   → 指向真实游戏目录
2. 给 `HKLM\SOFTWARE\WOW6432Node\Origin Games\70619` 与 `71067` 补上 `Install Dir`
3. 重启 EA App，让它重新校验

#### `BF3-Play.ps1` —— 启动

```powershell
.\BF3-Play.ps1                      # 自动：先 Steam，失败再直接启动
.\BF3-Play.ps1 -Mode steam          # 只走 Steam
.\BF3-Play.ps1 -Mode direct         # 只直接启动 bf3.exe
.\BF3-Play.ps1 -SteamTimeout 60     # 调整每一步的观察时长
```

#### `BF3-VU-Offline.ps1` —— 离线机器人对战

```powershell
.\BF3-VU-Offline.ps1 -Check                 # 检查环境
.\BF3-VU-Offline.ps1 -Prepare -Bots 24      # 生成 24 个机器人的本地服务器配置
.\BF3-VU-Offline.ps1 -Launch                # 装好 VU 后启动
.\BF3-VU-Offline.ps1 -Prepare -Port 25201   # 换端口
```

> VU（Venice Unleashed）本体需自行下载安装：<https://veniceunleashed.net/> → Downloads → 装到游戏目录。
> 机器人模组（可选）：<https://github.com/Joe91/fun-bots> → 解压到 `Server\Mods\fun-bots\`。

---

## 5. 输入输出示例

### 示例 A：诊断一个"点了没反应"的安装

**输入**

```powershell
.\BF3-Doctor.ps1
```

**输出（节选，真实运行结果）**

```
========================================================================
  Battlefield 3 诊断  (appid 1238820)
========================================================================
  [信息] 游戏目录: D:\SteamLibrary\steamapps\common\Battlefield 3
  [信息] 模式: 只诊断（不改动）

========================================================================
  1. 安装完整性
========================================================================
  [OK]   bf3.exe v1.6.0.0  签名=Valid  (Electronic Arts)
  [OK]   安装体积 34.46 GB
  [问题] MessageDlg.exe 缺失（EACore_App.ini 的 AGENT_MESSAGE 指向它，缺失会导致激活错误静默无提示）

========================================================================
  2. Steam 记录
========================================================================
  [OK]   StateFlags=4（已完整安装）
  [问题] LastPlayed=0 → Steam 从未成功启动过这个游戏
  [信息] 最近启动链记录:
         10/21/26 18:10:27 [AppID 1238820] Exit Code (0) : "...\EAappInstaller.exe" EAX_LAUNCH_CLIENT=0 IGNORE_INSTALLED=1 GLE 0
  [问题] Steam 只拉了 EA App 的安装器（EAX_LAUNCH_CLIENT=0），跑完就断链，bf3.exe 没被启动

========================================================================
  3b. EA 内容清单与授权
========================================================================
  [问题] Origin Games\70619 缺少 Install Dir（EA 不知道游戏装在哪）
  [问题] Origin Games\71067 缺少 Install Dir（EA 不知道游戏装在哪）
  [信息] 清单声明的安装路径: C:\Program Files (x86)\Origin Games\Battlefield 3
  [问题] 清单路径不存在且不是联接 → EA 找不到游戏文件，校验/授权必然失败（这是激活失败的根因）

========================================================================
  汇总
========================================================================
  发现 6 个问题:
    ✖ ...
  下一步:
    · 根因是 EA 内容清单指向不存在的旧路径 → 运行 .\BF3-Repair-EA.ps1
```

### 示例 B：修复根因

**输入**

```powershell
.\BF3-Repair-EA.ps1
```

**输出（节选）**

```
========================================================================
  修复 BF3 激活路径（EA 内容清单指向错误）
========================================================================
  游戏真实目录: D:\SteamLibrary\steamapps\common\Battlefield 3
  清单期望目录: C:\Program Files (x86)\Origin Games\Battlefield 3

========================================================================
  2. 建立目录联接，让老路径指向真实安装位置
========================================================================
  ✔ 已创建联接: C:\Program Files (x86)\Origin Games\Battlefield 3  →  D:\SteamLibrary\steamapps\common\Battlefield 3

========================================================================
  3. 验证联接是否真的能读到游戏文件
========================================================================
  ✔ C:\Program Files (x86)\Origin Games\Battlefield 3\bf3.exe 可读（31.7 MB）
  ✔ 清单项可读: Update\Xpack2
  ✔ 清单项可读: Update\Xpack4
  ✔ 清单项可读: Update\Xpack5
  ✔ 清单项可读: Data\cas_01.cas
```

### 示例 C：启动

**输入**

```powershell
.\BF3-Play.ps1
```

**输出（成功）**

```
  Battlefield 3 启动器
  模式: auto   游戏: D:\SteamLibrary\steamapps\common\Battlefield 3

▶ 预检
  ✔ Steam 正在运行
  ✔ EA App 已认证（3 秒）

▶ 尝试 1/2：通过 Steam 启动 (appid 1238820)
  ✔ bf3.exe 已启动 (PID 24680)

  启动成功（Steam 链）
  ✔ 游戏已创建用户配置目录
```

**输出（失败时——会明确告诉你下一步做什么）**

```
▶ 尝试 2/2：直接启动 bf3.exe
  ✖ bf3.exe 已退出，退出码 0x00000000
  · 退出码 0 且无窗口 = 拿不到 EA 授权票据后静默退出
  · 报错组件 MessageDlg.exe 缺失，所以连错误框都弹不出来

========================================================================
  两条官方启动链都没成功
========================================================================
  · 1) 先跑 .\BF3-Repair-EA.ps1 修复激活链，然后再试
  · 2) 在 Steam 里右键 BF3 → 属性 → 已安装文件 → 校验完整性
  · 3) 在 EA App 里确认这个游戏出现在「我的库」中
  · 4) 想马上能玩：运行 .\BF3-VU-Offline.ps1
```

### 示例 D：生成离线机器人服务器

**输入**

```powershell
.\BF3-VU-Offline.ps1 -Prepare -Bots 20
```

**输出**

```
========================================================================
  生成离线机器人服务器配置（20 个机器人，端口 25200）
========================================================================
  ✔ 创建 ...\Battlefield 3\Server
  ✔ 创建 ...\Battlefield 3\Server\Admin
  ✔ 创建 ...\Battlefield 3\Server\Mods
  ✔ MapList.txt：8 张征服大地图
  ✔ ModList.txt：已登记 fun-bots
  ✔ Startup.txt：服务器名/端口/人数/关闭 PunkBuster 与全局排行
  ✔ 机器人数量 20 → ...\Server\Mods\fun-bots\bots.json
  ✔ 启动脚本：...\Start-Local-Bot-Server.bat
```

**生成的文件**

```
<游戏目录>\
├── Start-Local-Bot-Server.bat          # 一键启动（先服务器后客户端）
└── Server\
    ├── Admin\
    │   ├── MapList.txt                 # MP_001 ConquestLarge0 1 …（8 张图）
    │   ├── ModList.txt                 # fun-bots
    │   └── Startup.txt                 # 服务器名 / 端口 25200 / 32 人 / 关 PunkBuster
    └── Mods\fun-bots\
        ├── mod.json
        └── bots.json                   # BotCount: 20
```

---

## 灵感来源与致谢

本项目的诊断思路与部分方案建立在 BF3 社区多年积累之上，特此说明，避免重复造轮子或引起误解：

- **[Venice Unleashed](https://veniceunleashed.net/)** —— BF3 社区自建的模组与联机平台，
  提供独立启动器与主服务器。本项目的"离线机器人"路线完全依赖它，`BF3-VU-Offline.ps1`
  只做环境检查与配置生成，**不包含、不分发 VU 本体**。
- **[fun-bots](https://github.com/Joe91/fun-bots)**（作者 De_Joe-91）—— VU 的 AI 机器人模组。
  本项目只生成其配置文件，不分发模组本体。
- **[bf3_license_fixer](https://github.com/voidfnc/bf3_license_fixer)** —— 另一个处理 BF3 授权激活
  报错的工具。本项目与其思路不同：它侧重修复授权文件，本项目侧重"EA 内容清单路径与真实安装位置
  不一致"这一具体成因，并采用目录联接而非改写文件。
- EA 的 `LocalContent` 清单格式、`EACore_App.ini` 的 agent 机制等，来自对本机安装的实际观察，
  非官方文档。

本项目与 Electronic Arts、DICE、Venice Unleashed 团队、fun-bots 作者均无隶属或背书关系。

---

## 免责声明

- 本项目仅用于**诊断和修复你合法拥有的游戏安装**。
- 不包含、不分发任何盗版内容、破解补丁、DRM 绕过工具或游戏本体。
- 不修改 `bf3.exe` 或任何游戏可执行文件，不注入进程，不打补丁。
- `BF3-Repair-EA.ps1` 的修改**完全可逆**（`-Undo`），且只涉及目录联接与两个注册表值。
- 运行前请自行确认你拥有该游戏的合法授权。因使用本工具产生的一切后果由使用者承担。

---

## 许可证

[MIT](LICENSE) © 2026 miaom4702-art
