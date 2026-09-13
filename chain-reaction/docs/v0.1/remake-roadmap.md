# 重制路线图：Chain Reaction Godot

- 文档版本：v0.1
- 日期：2026-09-12
- 设计合同：[game-design.md](./game-design.md)
- 原作路径：`d:\GitHub\Unity-ChainReaction\ChainReaction`
- 原则：**先内核后外壳**。先冻 JSON 与确定性模拟，再表现与 40 关，再菜单/存档/音频/网页，最后局外编辑器

本文给后续实现用。当前阶段**只写文档，不改玩法代码与场景内容**。

---

## 0. 全局约束（每一阶段都遵守）

- Godot 4.7，GDScript，GL Compatibility，1920×1080
- 玩家规则以 GDD 为准，不以 Unity C# 的协程副作用为准
- 模拟层不依赖节点树、物理引擎、输入、音频
- 关卡权威数据是 `schema_version` JSON；禁止运行时读旧 `Maps.json` 字段凑合
- 不新增原子类型、模组、多模式、联网、游戏内编辑器
- 不提交无权分发的 BGM 录音
- 现有空壳可继续用：`scenes/main_menu.tscn`、`scenes/game.tscn`、`scripts/main_menu.gd`、`scripts/game.gd`

---

## 1. 建议目录（实现时再创建）

按职责拆文件，避免再长出一个 `MapController.gd`。

```text
data/maps/campaign/pack.json
data/maps/campaign/level_1-1.json
data/maps/custom/pack.json
data/maps/custom/level_relay-race.json
data/i18n/en.json

assets/sprites/          # 从 Unity 导入的 PNG
assets/audio/            # 有权使用的 BGM + 坍缩音效

scripts/core/hex_grid.gd
scripts/core/map_data.gd
scripts/core/simulation.gd
scripts/core/atom_runtime.gd
scripts/core/neutron_runtime.gd
scripts/core/behaviors/   # 每种 type 一个脚本，加注册表

scripts/content/map_loader.gd
scripts/content/unity_map_converter.gd   # 一次性/开发期工具，不进玩家流程

scripts/app/game_session.gd
scripts/app/save_account.gd
scripts/app/audio_service.gd
scripts/app/i18n.gd

scripts/view/board_view.gd
scripts/view/atom_view.gd
scripts/view/neutron_view.gd

addons/chain_reaction_map_editor/        # 最后一阶段

tests/                                   # 无场景或最小场景的模拟测试
```

名称可微调，边界不要并回去。

---

## 阶段 A — 数据合同与转换

**目标：** 新 JSON 能从原作生成、能校验、人能读。

**做：**

1. 按 GDD §10 写下包目录 + `level_{id}.json` 的加载与校验（schema 版本、合法格、同格冲突、未知 type、纠缠缺 group）
2. 写转换器：读原 `Maps.json` 与 `CustomMaps.json`
   - 数字 type / 中子数字串 → 字符串 ID
   - 生成短 `id`
   - `1-5` 同格去重
   - 丢掉越界原子（`Relay Race` 的 `(2,3)`）
   - 输出转换报告（改了哪关、删了什么）
3. 把 40+2 关提交进 `data/maps/`（报告里的例外写进注释或 `data/maps/CONVERSION.md`，一两页即可）

**出口：**

- 用校验器加载两包，零未知错误
- `campaign` 恰好 40 关，顺序与原 `maps` 数组一致
- `1-5` 不再有同格双原子；转换报告记载 `Relay Race` 删除项
- 尚未要求能玩

**不要做：** 场景里摆原子、编辑器、菜单。

---

## 阶段 B — 无头模拟

**目标：** 规则在测试里可重复，而不是在编辑器里「看起来对」。

**做：**

1. `HexGrid`：合法格、odd-r 世界坐标、世界→格、间距 3.0 / 1.8
2. `Simulation`：状态机、步数、释放、飞行、墙、核命中、捕获窗口 0.1s、纠缠连带、坍缩、胜负
3. 行为注册表：GDD 六种 type 分文件
4. 测试至少覆盖：
   - 点 `normal` 扣 1 步；中子撞核不扣步
   - 单层释放后坍缩；双层先外后内
   - `movable` 按下不释放，移到空格成功、移到实格失败
   - 捕获：一发中子入轨，0.1s 后 `catching`→`normal`；窗口内可接第二发
   - `catching_movable` 窗口结束后变为 `movable` 且仍不能点爆
   - 纠缠：点一个扣一步，组员一起放；已坍缩的组员不放
   - 自释放中子不立刻打到自己
   - 同帧次序稳定（两次跑同一输入，事件序列一致）
   - 全坍缩为胜；步数为 0 且仍有原子为负

测试框架选一种并固定（GdUnit4 或项目当时可用的 Godot 测试方案）。测试直接 `new` 模拟对象，不 `instantiate` 整局场景。

**出口：** 上述测试全绿。插件以后只能链这套 API。

**不要做：** 精灵、HUD、Godot Physics、Autoload 里藏规则。

---

## 阶段 C — 盘面表现与操作

**目标：** Game 场景能加载一张图，用鼠标按 GDD 操作，画面认得出是原作。

**做：**

1. 从 Unity 导入原子/中子/轨道/箭头/格子标记 PNG 到 `assets/sprites/`
2. `BoardView`：按模拟状态画格、原子、中子；Godot y 向下只在这一层翻转
3. 核高亮、可移动箭头、虚实轨道、坍缩缩放、释放轨道淡出、中子拖尾
4. 把鼠标/触控映射到会话：点爆、拖动吸附
5. `game.gd` / `game.tscn` 接上「指定 MapData → 开局」；临时可用开发跳关（不进正式菜单）
6. 立即重开、回菜单按钮；胜负文案与 2 秒自动跳（可先写死下一关为同一张或列表下一张）

**出口：**

- 用 `1-1`、`2-1`、`3-1`、`4-1` 各手动走通一次教学意图
- 拖动吸附与空格/非法格符合 GDD
- 反应中无法点核

**不要做：** 完整解锁、网页发布、编辑器。

---

## 阶段 D — 正篇内容接入

**目标：** 40 关 + 2 自定义关都从 JSON 进游戏，规则与内容对上。

**做：**

1. 会话按包 + 下标读图；通关 `currentLevel++`，包末回 0
2. 用阶段 B 的模拟对每张图做「能加载」测试；对转换改过的关做烟雾试玩
3. `Relay Race`：按删除越界原子后的数据实玩。若明显不可解，**停下来人工改 JSON**（仍不算新机制），并在 `CONVERSION.md` 记一笔，不要改模拟去迁就坏图
4. 校准间距、半径、墙外扩，使飞行轨迹与原作观感接近（允许帧表现差，不允许胜负与原规则冲突）

**出口：** Campaign 可从第 1 关连着玩到包末（开发跳关或临时全解锁均可，正式解锁在下一阶段）。Custom 两关能进。

---

## 阶段 E — 外壳：菜单、存档、文案、音频

**目标：** 玩家侧对齐原作，不再靠开发跳关。

**做：**

1. 主菜单：Campaign/Custom 切换、关卡格数字、通关色/解锁色/锁定、退出
2. 解锁：未通关最多 3 个可进（GDD §8.1）
3. `user://` 存通关列表；Custom 不写通关
4. `data/i18n/en.json`；HUD 与模式名走表
5. 音频服务：BGM 列表顺序播放、全局音量、静音按钮、坍缩 SE（最多 3 路）
6. 去掉阶段 C 的临时跳关，或留 `debug` 开关且默认关

**出口：** 新存档只能进 campaign 前 3 关；通关第 1 关后第 4 关可进；静音立刻生效；文案无场景硬编码英文节点（关卡名除外）。

---

## 阶段 F — 网页导出

**目标：** 与 itch 原作一样能打开页面玩。

**做：**

1. 用现有 GL Compatibility 导出 Web
2. 确认点核、拖动在触控/鼠标下可用
3. 关卡 JSON 打进包内；不要 FileDialog
4. 音频在浏览器手势后能播（按 Godot Web 音频策略处理首次点击）
5. 存档走 `user://` 在 Web 上的持久化是否够用：不够则改为同一套存档接口下的浏览器存储实现，**接口不要分裂**

**出口：** 桌面包与 Web 包都能完整打完一关、刷新网页后仍能读到通关（若平台允许）。不为此重做手机 UI。

---

## 阶段 G — 局外编辑器

**目标：** 设计师打开本 Godot 工程即可改关，玩家包没有入口。

**做：**

1. `addons/chain_reaction_map_editor/`：EditorPlugin
2. 读/写 `data/maps/*.json`（权威格式）
3. 摆放、改 type/group/orbits/steps/尺寸，合法格与同格校验
4. 试玩调用阶段 B 的 `Simulation`，不要在插件里重写碰撞
5. `export` 预设排除 `addons/chain_reaction_map_editor`（或等价方式保证玩家包无入口）
6. 主菜单不加「Editor」

**出口：** 改一关 JSON → 游戏运行读到同样数据；试玩胜负与游戏一致。未做模组、多模式、联网。

实施形态：开发场景 `scenes/level_editor.tscn` / `scenes/level_tester.tscn`（F6），不是 EditorPlugin。`export_presets.cfg` 的 `exclude_filter` 排除这两个场景和 `scripts/dev/*`。主菜单无入口。

---

## 2. 阶段依赖

```text
A 数据转换
    → B 无头模拟
        → C 表现与操作
            → D 40 关接入
                → E 菜单存档音频
                    → F 网页
                        → G 编辑器
```

G 理论上在 B 完成后就能开始做只读校验，但**写回与试玩**必须等 B 稳定、建议等 D 之后，避免规则还在改时双边修。

---

## 3. 风险

| 风险 | 对策 |
| --- | --- |
| 确定性模拟与原作物理在个别关上胜负不一致 | 以 GDD 规则为准；用 `1-1`/`2-1`/`3-1`/`4-1` 做黄金关。仅当半径/墙导致「明明应对上却擦过」时调常量，不改操作语义 |
| Unity 音频/部分资源不在 git 里 | 从本地原工程拷贝精灵；BGM 换有权文件 |
| `Relay Race` 删原子后不可解 | 阶段 D 人工复核，记录在转换说明 |
| Godot y 向下把方向搞反 | 模拟层冻结 y 向上；测试方向向量，不测屏幕坐标 |
| 网页拖动 | 阶段 C 就用同一套指针抽象，F 只补手势与音频解锁 |
| 一个脚本重新膨胀成 Godot 版 MapController | 代码审阅对照「建议目录」；模拟测试必须在无节点下通过 |

---

## 4. 刻意延后

- 中文本地化（表结构在 E 就位，不填 `zh`）
- 新原子类型
- 一关一文件的拆分（对象形状已稳定，拆文件不是 v0.1 实现目标）
- 独立可执行文件版编辑器
- 手机竖屏布局
- 关卡平衡重做

---

## 5. 当前进度

| 项 | 状态 |
| --- | --- |
| GDD v0.1 | 本目录已写 |
| 路线图 v0.1 | 本文 |
| JSON / 模拟 / 场景玩法 | 未开始 |
| Godot 空壳场景 | 已有，可在阶段 C 接上 |

下一步实现从**阶段 A**开始，不要先做编辑器或菜单美化。
