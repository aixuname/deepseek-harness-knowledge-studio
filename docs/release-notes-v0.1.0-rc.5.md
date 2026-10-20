# Knowledge Studio v0.1.0-rc.5

首个面向 Windows x64 的非官方可下载发行包，适配 DeepSeek Harness `0.1.2-rc.1`。

## 主要功能

- 中文 Obsidian 风格 Markdown 知识库
- 双链、反向链接、标签、搜索与大纲
- 以当前知识点为主体、可切换中心的星系关系图谱
- 每篇笔记独立的 Excalidraw 画布，支持图片和常用图形
- 仅按当前任务组装上下文并显示 Token 估算的 AI 助手
- 一键安装与安全卸载；卸载不会删除笔记、图片或画布

## 安装

1. 下载并解压 `knowledge-studio-windows-x64-v0.1.0-rc.5.zip`。
2. 完全退出 DeepSeek Harness。
3. 双击 `install.cmd`。
4. 重启 Harness，在侧边栏进入“知识库”。

安装器会校验全部插件包的 SHA-256，并在修改前自动备份配置。详细说明见仓库 README。

发行 ZIP SHA-256：`A634EC98F99F9B041417ADE59854E2EFE72778E9923ADCF773FCD75F5523FAF8`

> 这是非官方编译发行封装，不包含 DeepSeek Harness 本体，也不包含原始 TypeScript 源码。六个插件包保留原始 MIT 许可和元数据。
