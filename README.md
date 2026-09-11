# 🦞 OpenClaw 龙虾 · macOS 菜单栏版

给 [OpenClaw](https://github.com/openclaw/openclaw) 网关做一个**一键开关**:右上角一只龙虾,
**左键**开 Control UI,**右键**开关网关,退出即停服务。

![平台](https://img.shields.io/badge/平台-macOS-black)
![形态](https://img.shields.io/badge/形态-菜单栏常驻-red)
![语言](https://img.shields.io/badge/Swift-AppKit-orange)
![许可](https://img.shields.io/badge/许可-MIT-blue)

> 同一套骨架的兄弟项目:**[🐳 大肥鱼](https://github.com/zhqowo/dsh-whale-tray)** ——
> DeepSeek Harness 的托盘 / 菜单栏启动器。装好后两个图标可以并排放在菜单栏上。

## 下载

不想编译就直接用打包好的(**解压即用**):

| 文件 | 说明 |
|---|---|
| [`OpenClaw.app.zip`](https://github.com/zhqowo/openclaw-menubar/releases/latest) | macOS 菜单栏版龙虾(ad-hoc 签名) |

因为是 ad-hoc 签名,首次打开会被 Gatekeeper 拦一下:右键 →「打开」,或

```sh
xattr -d com.apple.quarantine OpenClaw.app
```

⚠️ **下载版需要 `openclaw-ctl.sh` 在 `~/DeepSeekHarness/bin/` 下**(app 里写死了这个路径)。
原因与替代方案见下面「[服务层脚本放哪](#服务层脚本放哪)」。

## 用法

| 操作 | 行为 |
|---|---|
| **左键** | 打开 Control UI。网关没开就先开;**已有标签页就切过去**,不重复开新页 |
| **右键** | 只有两项:`开启网关` / `关闭网关`(随状态变)+ `退出` |
| **图标全彩** | 网关运行中 |
| **图标变暗** | 网关已停止 |

没有重启项、没有状态行、没有充值 —— 状态全在图标亮度上。

## 关键设计

**Mac 上启动是静默的。** 网关由 launchd 以 LaunchAgent 拉起
(`~/Library/LaunchAgents/ai.openclaw.gateway.plist`),后台运行、无终端窗口、无 Dock 图标。
Windows 版要费劲藏控制台,Mac 不需要。

**退出 = 停网关。** `applicationWillTerminate` 调 `openclaw-ctl.sh stop`,
免得菜单栏图标没了、服务还在后台裸跑。

> 如果你希望**退出只收图标、网关继续跑**(比如要让它托管微信/定时任务),
> 删掉 `main.swift` 里的 `applicationWillTerminate` 整个函数再重新 build 即可。

**左键直达免验证。** Control UI 认 `gateway.auth.token`,官方 `openclaw dashboard` 就是把 token
拼进 URL 片段。本应用直接从 `~/.openclaw/openclaw.json` 现读 token 拼同样的 URL,
所以 **token 轮换后不用重新编译**。

## 目录

```
main.swift         # 主程序(Swift / Cocoa)
icon_compose.swift # 合成 app 图标(浅色卡片 + 龙虾)
svg2png.swift      # SVG → 透明 PNG(qlmanage 会垫白底,不能用)
make_assets.sh     # 从已装的 OpenClaw 包重新导出图标素材
build.sh           # 编译 + 打包 + 安装到 ~/Desktop/OpenClaw.app
openclaw-ctl.sh    # 服务层:start/stop/restart/status/pid/url/open/log
assets/
  favicon.svg         # 官方矢量吉祥物(从 npm 包复制)
  lobster1024.png     # 1024×1024 透明龙虾
  claw.png / claw@2x.png   # 菜单栏 18pt @1x/@2x
  apple-touch-icon.png     # 官方 180px 备选
```

## 服务层脚本放哪

⚠️ **这是唯一的部署约束。** `main.swift` 顶部有一行:

```swift
let CTL = "\(HOME)/DeepSeekHarness/bin/openclaw-ctl.sh"
```

app 只是 shell out 到这个脚本,所以**脚本必须在那个路径**,否则菜单项点了没反应。
下载预编译版的人要注意这一点(`build.sh` 不会自动帮你放)。

三个办法任选:

1. 把 `openclaw-ctl.sh` 复制到 `~/DeepSeekHarness/bin/`(保持默认,不用改代码)
2. 改 `main.swift` 里的 `CTL` 常量指向你放的位置,然后 `zsh build.sh`
3. 干脆不用 `openclaw-ctl.sh`,自己写个同名脚本放那个路径,只要支持 `status` / `start` / `stop` 三个子命令

## 构建

```sh
zsh build.sh          # 重新编译并安装
zsh make_assets.sh    # 升级 OpenClaw 后刷新图标素材
```

产物:`~/Desktop/OpenClaw.app`(bundle id `local.openclaw.menubar`,ad-hoc 签名)

## 服务层行为

- `start` — 先 `openclaw gateway start`(launchd 托管,挂了会自动重启);
  launchd 不可用时回退成 `nohup openclaw gateway run` 脱离进程,同样无窗口
- `stop` — 无论有没有监听,**都会卸载 LaunchAgent**;否则一个"已加载但已死"的 job
  会在背后把网关重新拉起来。卸载没生效才退化成 `kill` → `kill -9`
- 判定"在跑"的唯一依据是 **18789 端口有没有监听进程**(`lsof`),
  因为 `launchctl list` 里可能是个崩溃重启中的 job

## 图标是怎么来的

OpenClaw 官方吉祥物的**矢量图**就在它自己的 npm 包里:
`~/.local/node/lib/node_modules/openclaw/dist/control-ui/favicon.svg`

`svg2png.swift` 把它渲染成 1024×1024 **透明背景** PNG 再用 ——
用 `qlmanage -t` 渲染会垫一层**不透明白底**,放进菜单栏就是一块白疙瘩,不能用。
`NSImage` 能直接读 SVG 并按目标尺寸重新栅格化,所以放大到 1024 依然锐利。

菜单栏图标同时塞 18px(@1x)和 36px(@2x)两个 rep:
`NSImage(contentsOfFile:)` **不会**自动加载 `@2x` 兄弟文件,只塞一个的话 Retina 下会发虚。

素材版权归 OpenClaw 项目所有,这里只是为了菜单栏图标和上游品牌一致才内置。

## ⚠️ 需要权限吗

**这个 app 本身不需要任何 TCC 授权。** 它只做三件事:TCP 探测端口、跑 `openclaw-ctl.sh`、
用 AppleScript 切标签页(需要**自动化**权限,首次点左键会弹窗,拒绝也只是回退成新开标签)。

所以它**可以随便重新编译** —— 不像「大肥鱼」那样受"重建 = 授权全废"的 cdhash 铁律约束
(ad-hoc 签名下系统按二进制哈希记授权,重建就换哈希;大肥鱼吃屏幕录制 / 辅助功能 / 完全磁盘访问
这些重权限,所以冻结了二进制。详见
[大肥鱼仓库的 TCC 章节](https://github.com/zhqowo/dsh-whale-tray/blob/main/macos/README.md))。

## 已验证

- 开启 5.9s / 关闭 4.3s,重复 `start` 幂等(报 `already running`)
- 菜单栏龙虾两态正确:网关在跑 = 全彩,停掉 3 秒内变暗
- 左键落地的 URL 带 token,Control UI **直接进聊天界面,不弹验证**
- Retina 下图标锐利(用的是 36px @2x 图,不是 18px 放大)
- 右键菜单实测就是「开启网关 / 退出」两项,点「开启网关」后网关起来、HTTP 200
- 桌面图标被 macOS 正常套圆角

## 许可

[MIT](LICENSE) © 2026 zhqowo —— 随便用、改、商用,保留版权声明即可。
内置的龙虾素材版权归 OpenClaw 项目,详见 [LICENSE](LICENSE) 末尾。
