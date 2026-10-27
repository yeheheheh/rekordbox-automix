# rekordbox-automix

Rekordbox 7 外部桥接器 + 离线 DJ 排 set / 自动接歌引擎。

Rekordbox 没有公开插件 SDK，所以这不是一个嵌进 Rekordbox 界面的原生插件，而是一个本地伴生程序：读 Rekordbox 曲库、分析音频、排 set、规划过渡、用 Demucs 分轨渲染，再把结果写成 Rekordbox 播放列表或 `rekordbox.xml`。

- 输入：本地音频 / Rekordbox 7 `master.db`
- 分析：BPM、调性、拍网格、8 小节乐句、能量、人声、Demucs 四轨
- 排 set：兼容性图 + 束搜索，统一 target BPM，能量曲线
- 过渡：`long_blend` / `bass_swap` / `filter_out` / `cut` / `double_drop`
- 渲染：rubberband 逐拍变速、分轨增益/EQ、限幅、−14 LUFS、WAV/MP3 + JSON 报告
- 出口：Rekordbox 播放列表（自动备份）或 `rekordbox.xml`
- 入口：CLI、本地 FastAPI、MCP stdio

> 站点控制台 `#/dj/automix` 在主站仓库：[yeheheheh/electronic-music-field-notes](https://github.com/yeheheheh/electronic-music-field-notes)。本仓库只负责引擎、Rekordbox 桥接和安装器。

## 一键安装（Windows）

1. 下载本仓库 ZIP 并解压。
2. 双击 `install.bat`。
3. 安装完成后双击 `start-api.bat`。

安装器会：

- 检测 Python 3.12；缺失时尝试用 `winget` 安装。
- 优先用 `uv pip`（如果 PATH 里有 `uv`），否则回退到 `pip`。
- 在 `%LOCALAPPDATA%\djcore` 建 venv、安装依赖。
- 有 NVIDIA GPU 时安装 CUDA 12.8 版 PyTorch；没有则安装 CPU 版。
- 安装 `imageio-ffmpeg`（自带 ffmpeg）和便携 rubberband（失败则回退 librosa）。
- 自动发现 `%APPDATA%\Pioneer\rekordbox\master.db` 并写入 `config.json`。
- 生成 `start-api.bat`、`rekordbox-status.bat`、`local-demo.bat`、`mcp-config.json`，以及桌面快捷方式。

也可以用 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\install.ps1
```

常用参数：

```powershell
# 只看检测结果，不安装
powershell -ExecutionPolicy Bypass -File .\install\install.ps1 -DryRun

# 没有 NVIDIA GPU（或不想装 CUDA）
powershell -ExecutionPolicy Bypass -File .\install\install.ps1 -Cpu

# 国内网络：用镜像装 cu128（也可用其他镜像）
powershell -ExecutionPolicy Bypass -File .\install\install.ps1 `
  -TorchIndexUrl https://mirrors.nju.edu.cn/pytorch/whl/cu128

# 已经有本地 wheel（最快）
powershell -ExecutionPolicy Bypass -File .\install\install.ps1 `
  -TorchWheel D:\wheels\torch-2.9.1+cu128-cp312-cp312-win_amd64.whl `
  -TorchaudioWheel D:\wheels\torchaudio-2.9.1+cu128-cp312-cp312-win_amd64.whl
```

- 默认安装目录：`%LOCALAPPDATA%\djcore`
- 默认 Torch 索引：`https://download.pytorch.org/whl/cu128`
- 50 系显卡（sm_120）需要 cu128 或更新；cu126 会报 `no kernel image is available`。
- 首次安装会下载 PyTorch（约 2.4–2.9GB）和 Demucs 模型（约 80MB）；请预留 6GB 以上磁盘。

## 安装后

| 文件 | 用途 |
|---|---|
| `start-api.bat` | 启动本地 API：`127.0.0.1:5601` |
| `rekordbox-status.bat` | 查看 Rekordbox 库与写库状态 |
| `local-demo.bat` | 用合成 fixture 跑一遍「分析 → 排 set → 渲染」 |
| `mcp-config.json` | 粘到 Claude Desktop / Qoder 的 MCP 配置 |
| `uninstall.bat` | 卸载（会二次确认） |

站点控制台（可选）：

```bash
git clone https://github.com/yeheheheh/electronic-music-field-notes.git
cd electronic-music-field-notes
node scripts/serve.mjs
```

打开 `http://127.0.0.1:5501/#/dj/automix`，左侧 `SOURCE / 曲库` 切到 **Rekordbox**。

## CLI

```bat
cd %LOCALAPPDATA%\djcore\app
..\venv\Scripts\python -m djcore.adapters.cli rekordbox status
..\venv\Scripts\python -m djcore.adapters.cli rekordbox scan
..\venv\Scripts\python -m djcore.adapters.cli rekordbox plan --preset melodic-techno --duration 4
..\venv\Scripts\python -m djcore.adapters.cli rekordbox export --set <setId> --name "my set" --mode xml
```

- `--db-path` 可指定 Rekordbox DB 副本。
- `--tracks` 指定具体曲目（`rb-` ID 或标题）；不指定时按风格 BPM 选最多 8 首（`--limit`）。
- `--export db|xml|both` 在渲染后直接导出；`db` 会备份并写播放列表。
- `export --mode db` 需要 `--confirm`；不确认只导出 XML。

## Rekordbox 写库安全

- 写库前必须关闭 Rekordbox；运行中直接拒绝。
- 自动备份 `master.db`、`master.db-wal`、`master.db-shm`、`masterPlaylists6.xml` 到 `outputs/rekordbox-backups/<时间戳>/`。
- 只创建普通播放列表，不碰 Smart Playlist / folder。
- 写入后重新打开 DB，按 `TrackNo` 校验顺序。
- 开发/验收请先写 DB 副本：

```bat
..\venv\Scripts\python -m djcore.adapters.cli rekordbox plan ^
  --preset melodic-techno --duration 4 --export both ^
  --db-path outputs\rekordbox-test\master.db ^
  --name "djcore rb demo"
```

## MCP

把 `%LOCALAPPDATA%\djcore\mcp-config.json` 的内容合并到客户端的 MCP 配置。它长这样：

```json
{
  "mcpServers": {
    "djcore": {
      "command": "C:\\Users\\<you>\\AppData\\Local\\djcore\\venv\\Scripts\\python.exe",
      "args": ["-m", "djcore.adapters.mcp_server"],
      "env": { "PYTHONPATH": "C:\\Users\\<you>\\AppData\\Local\\djcore\\app" }
    }
  }
}
```

工具：`dj_health`、`dj_analyze`、`dj_plan_set`、`dj_render_set`、`dj_get_set`、`rb_status`、`rb_library`、`rb_plan_set`、`rb_export_playlist`。

`rb_export_playlist` 默认只做 dry-run；写库必须传 `confirm=true`。

## 目录

```
djcore/
  contracts.py          # TrackAnalysis / SetPlan / RenderResult
  analysis/             # 节拍、调性、结构、人声、Demucs、缓存
  planning/             # intent、兼容性、束搜索、过渡
  render/               # rubberband、自动化、混音、报告
  adapters/             # CLI、FastAPI、MCP
  library/rekordbox.py  # RB7 读库 / 备份 / 写播放列表 / XML
  service.py            # 三个适配器共用
install/                # install.ps1 / uninstall.ps1
data/genres.json        # 92 条风格模型（来自主站听感层）
fixtures/sidecars/      # 合成 fixture 的手标结构
docs/                   # 设计与桥接规范
```

## 开发

```bat
py -3.12 -m venv .venv
.venv\Scripts\python -m pip install -e .
.venv\Scripts\python -m pytest
```

- `fixtures/audio/` 由 `djcore.adapters.cli fixtures` 生成，不提交 WAV。
- Rekordbox 写库测试会复制 live DB 到临时目录，不会改原库；没有 RB 库时自动 skip。

## 已知限制

- RB7.2.14 读写已验证；RB6 只做了 pyrekordbox 兼容读取，未做写库验收。
- v1 不写 Cue / Hot Cue / 内存点，不做 USB 设备导出，不控制 Mixxx。
- 曲目 BPM=0 或 key 未知时，以音频分析结果为准并标记 warning。
- 真实曲库的调性/drop 检测是启发式；关键 set 建议人工复核。

## License

MIT
