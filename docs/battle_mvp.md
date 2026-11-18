# 戟兵、弓兵与骑兵战斗

已接入当前九州经营工程。大地图的商军据点由守军战斗决定归属；中立空据点仍可相邻占领。

哪吒使用最新无风火轮资源与灼烧/引爆规则，详见 [nezha_art_v2.md](nezha_art_v2.md)。该资源已同时接入大地图头像、战斗人物与头像、地图施法；新实战截图在 `previews/nezha/runtime/`。

## 体验

- 在默认朝歌场景按 **B**，当前选中的哪吒或闻仲会与相邻敌军接战。战后按 **Enter** 回到地图查看各编队战损，结束回合可补满再试。在经营战役按 **B** 可进入独立的三军演武。
- 实战：选中商军据点 → “行军至附近” → 行军到真实陆地相邻格，保留至少 1 点行动力 → 点击“接战”或按 C。内景右下同样提供“接战”。
- 战前列阵 3 秒。近翼和远翼错开接敌，戟兵从中路推进，弓手从后排放箭。
- 英雄自动普攻和施放战技，各武将的普攻按自己的命中时刻结算。戟兵一次普攻长 0.68 秒，出手后 0.32 秒进入第 9 帧并判定命中。
- **R** 手动释放终结技：双方每战初始士气均为 50，实际击杀每 10 名士兵增加 1 点，上限 100。列阵结束、士气达到 100、主将存活时可立即打断普攻、战技或移动并释放，消耗 100；之后可重新积累。没有额外 8 秒门槛或每战一次限制。敌方遵循相同条件并自动释放。
- **Space** 暂停/继续；**X** 在 1× / 2× 之间切换；战果出现后 **Enter** 返回地图。**F3** 显示碰撞轮廓，**F4** 切换伤害飘字。关闭飘字仍可看到命中与受击。
- 战斗期间暂停地图输入、回合、存读档和补兵。战果结算一次，消耗 1 点行动力；胜利占领，失败保留原格与敌方残余守军。
- 士气按实际人数战损累计，包括尚未完全倒下的百人模型；过量伤害和重复攻击尸体不重复计数。战果保留本场剩余士气，下场战斗重新从 50 开始。
- 地图按 **Q** 或右侧技能按钮进入选点；左键施放，右键 / **Esc** 取消。成功施法后本队行动力归零，本轮不能继续行军、接战或施法；无效目标不消耗行动。完整四技能与属性说明见 [hero_skills.md](hero_skills.md)。

## 编制与演算

每军一位主将和三个编队。朝歌测试战双方各有 1200 戟兵、800 弓兵、400 骑兵。新战役与初始守军按 3∶2∶1 分兵。大地图和战斗面板分别显示各编队的实时人数，战果按原编队带回幸存者。旧档中的戟兵编队保留原有人数，在军营补兵时可补入弓兵和骑兵。

- 戟兵在前排接敌，第二排可从前排的空隙递戟。
- 弓兵从后排接近到 565 地面单位内停步张弓，第 9 帧松弦。箭矢以每秒 800 地面单位飞向出手时预判的位置，画面表现为抛物线。箭抵达时检验目标位置，目标移开可避开，射手倒下后已离弦的箭仍可命中。
- 骑兵从两翼发起一次开场冲锋，每秒推进 340 地面单位。独立 16 帧动画从疾驰过渡到压枪，在第 12 帧检查距离，命中造成普通骑兵攻击的 1.8 倍物理伤害。冲锋落空或受阻超时也会消耗这次机会，随后改用独立的 16 帧马上普攻。

[朝歌实战 · 全景与主将局部回放](../previews/battle/hero-art/chaoge-heroes.mp4) · [同一帧的角色与终结技对照](../previews/battle/hero-art/combat-before-after.jpg) · [开场冲锋与齐射慢放](../previews/battle/combined-arms/charge-and-volley.gif)

弓弦、落箭和冲锋各有独立音效。武器火星和箭头落在实际命中位置，同一编队附近的普通战损会合并显示。哪吒的莲火和闻仲的雷电沿受击目标展开，终结技时镜头最多推近 7.5%。底栏保持固定，己方可释放时终结技圆环才会亮起。

哪吒的火尖枪两次命中时，金色三首六臂法相依次从后肩展臂。乾坤圈按出手和回收方向留下两道轨迹，三昧真火在落点开莲。闻仲的雷鞭从实际鞭尖发出，九霄雷殛在主雷落下后向受击者分叉。终结命中前后，战场短暂压暗，火莲上部和雷光透过前排阵列。

每名士兵对应 1 点生命。每个满编兵模为 100 人、100 血，同一编队的 237 人会分成 100、100、37 血的三个模型。小数伤害会累计，每损失一个完整生命点扣除一名士兵。战斗面板、击杀、士气和带回地图的兵力按同一份战损计算。主将采用自己的生命属性。兵员归零时本军溃散，最长交战 75 秒，超时比较双方剩余兵力比例。

戟兵与弓兵的地面碰撞半径为 32，骑兵为 36，主将为 38。所有存活单位相互阻挡。渲染按地面深度排序，影子、精灵和技能目标使用同一坐标。逻辑为固定 60 Hz、确定性演算；渲染帧率、暂停与倍速不改变同一输入下的结果。死亡单位退出阻挡，播放倒地帧再淡出。

周军和商军戟兵各有 16 帧普攻。前八帧从斜持长戟到压低重心，第九帧踏步平刺，随后回收戟杆，转回守势。两军另有待机、跑步、受击、倒地各四帧。大地图行军与列阵直接取用同一兵模的跑步与待机动作。战斗时钟统一驱动帧动画、读条、伤害和特效，结束后留出 1.35 秒让倒地与特效播完。

[两军普攻半速对照](../previews/battle/infantry/halberd-thrust.gif) · [朝歌新兵模实战录像](../previews/battle/infantry/halberdiers-chaoge.mp4)

守军默认兵力：城市 4200、关隘 2800、村庄 1200、渡口 1500；开战士气 50。本版商军守将统一用闻仲演示，哪吒使用新动作图，其他我方英雄暂共用通用武将动作图。各武将已使用独立的四技能和六项通用属性，当前数值为可调整的 MVP 参数；尚未添加野战巡逻敌军和自由混编配置界面。

## 人物尺寸与战场站位

朝歌战场使用一张完整的手绘背景，灰青的城墙和远山衬出近景暖沙。1920×1080 设计画面上，脚底在 y=438 至 802 之间随纵深变化。后排的横向间距略微收窄，箭路、命中点与角色脚底共用地面投影。

1920×1080 下，普通步卒的基准站立身高为 108 px，骑兵连马为 137 px，哪吒为 205 px，闻仲为 219 px。纵深倍率为 0.88–1.03，横纵等比缩放。待机、跑步、普攻、受击、倒地和施法保持各角色的同一比例。人物以脚底为锚点转向，前伸的兵器和披风使用各自的画幅。

戟兵按人数展开正面，相邻两排错开半个间距。交锋时每支部队定期分配敌人周围的空位，行进中的戟兵会避开挡路的友军并补入空位。前排接敌后，第二排可从身侧空隙递戟。协击在命中帧检查射程和沿途的存活单位。脚步动画按碰撞处理后的实际位移推进。

[朝歌同一开局调整前后对照](../previews/battle/infantry/chaoge-comparison.gif) · [实战录像](../previews/battle/infantry/chaoge-melee.mp4)

`data/battle_frames.json` 保存图集的取样范围、可见范围、锚点及基准身高，由 `tools/measure_battle_frames.gd` 测量。两军三兵种和通用武将合计 248 帧，由 `tests/battle_layout_check.gd` 验证两种朝向、四个战场边界位置和 122 个实体。哪吒与闻仲的独立图集分别由 `tests/nezha_check.gd` 与 `tests/wenzhong_check.gd` 验证。

弓兵与骑兵的两军图集分别位于 `assets/battle/archers/` 与 `assets/battle/cavalry/`。戟兵原画与透明动作图集位于 `assets/battle/halberdiers/`。周军以朱红巾帻、青黑札甲与象牙白衣袖识别，商军以紫巾、靛甲与卷云肩饰识别。两套图集逐帧对齐脚底，普攻时后脚保持落地，前脚随身体重心前移。通用武将使用 `assets/battle/motion/general_upright_v3.png`。

人物按原画自然比例等比缩放；待机以双足承重为基准，跑动、攻击、受击保留动作倾斜。逐帧测量脚底重心，跳跃与倒地保留相对地面的高度。哪吒人物面板裁切第二版正式立绘；其他角色沿用原全身图。

正式窗口与设计尺寸统一为 **1920×1080**，渲染目标 60 FPS，战斗固定演算 60 Hz。采用项目统一帧率控制（macOS 由 `frame_pacer.gd` 调度），避免 OpenGL 垂直同步和帧率上限叠加造成帧等待。`tests/battle_performance.gd` 临时解除帧率上限，在真实 1080p 渲染下测试普通 50 实体及满编 122 实体的冲锋、碰撞、自动施法和终结技，记录实际帧间隔 P95/P99；性能结论应结合硬件和报告，不能以设置值代替实测。

碰撞最多进行六次圆形分离迭代；某一轮既无碰撞调整也无边界调整时提前结束，密集接触仍保留六次。使用 80px 空间格过滤不可能接触的单位，并在紧凑坐标数组内完成循环后回写角色。最近敌人查询按阵营分组。当前提前结束优化保持战果、碰撞数与最大残余重叠一致；相较最早的旧排序，个别战损结果可能不同。

上一版人物的截图和报告位于 `previews/battle/upright-v3/`，对应的绘制、透明底处理和枪尖修正提示保存在 `data/battle_art_v3_prompts.json`。

### 1080p 实测（2026-11-16）

以下保留四技能改造前的历史采样。四技能改造后的历史实测见 [hero_skills.md](hero_skills.md)，满编场景尚未稳定达到 60 FPS。哪吒新美术尚未在该硬件重新做性能验收。

硬件：Intel i7-8750H / Radeon Pro 555X，Godot 4.7.2 OpenGL Compatibility。正式 60 FPS 帧调度，双方各 2400 人（50 实体）与双方各 6000 人（122 实体），各采样约 20 秒，覆盖接战、自动技能及终结技：

| 场景 | 平均 FPS | 帧间隔 P95 | 帧间隔 P99 |
| --- | ---: | ---: | ---: |
| 50 实体 | 60.00 | 16.680 ms | 16.746 ms |
| 122 实体 | 59.90 | 17.696 ms | 18.962 ms |

源报告：`previews/battle/upright-v3/performance-paced.json`。满编平均接近目标，但 P95 仍超过严格的 16.67 ms 帧预算，不能声称所有帧稳定 60。该结果不代表其他硬件、分辨率或 2× 倍速的最低帧率保证。未锁帧的余量测量另见 `performance-report.json`。

确定性、战果回写和碰撞规则 37 项通过；122 实体、900 固定演算步约 3.15 秒（无渲染，仅用于演算成本比较），采样最大剩余重叠约 5.99 世界像素。六次分离迭代是有限迭代近似，密集接触不是严格零穿透。

最终立绘布局检查 4877 项通过，覆盖全部 112 帧、双朝向、四角边界、运行时等比绘制及土地范围。实机流程 13 项通过，覆盖暂停、倍速、自动技能、终结技、战果返回和真实地图战损回写。全流程报告的帧率包含截图、窗口切换和 2× 倍速，不作为 1× 实战性能数据；性能以独立 `performance-paced.json` 为准。

## 存档

统一存档使用 schema 7，记录野战与守城各编队的幸存人数，同时保存网格版本、武将身份、六项基础属性、临时效果及到期回合、地图施法后的行动状态，以及原有士气、三个编制槽和受损守军。当前网格为 grid_revision 3，schema 1–6 的旧档继续兼容，自动补齐默认属性与技能身份并转换旧网格位置；保留之前的经营 schema 2 → 3 扩容迁移。加载先完整验证数据，再修改当前状态。不能在战斗中保存中间状态。

## 代码与验证

- `scripts/battle_rules.gd`：固定步长演算、伤害、碰撞、士气规则。
- `data/unit_catalog.json` / `scripts/unit_catalog.gd`：四技能、六项属性、被动及临时增减益、物理 / 魔法减伤公式。
- `scripts/battle_view.gd` 绘制战场与人物帧动画，并随战斗事件播放音效。
- `scripts/battle_cinematics.gd` 控制主将施法镜头与火、雷特效。`scripts/battle_impact_art.gd` 绘制兵种命中、扬尘与落地影子。
- `scripts/world_model.gd`：接战事务、战果回写、存档兼容。
- `scripts/game.gd`：地图与战斗切换、输入隔离、演武入口。
- `tests/combined_arms_check.gd` 验证远射、在途箭、冲锋倍率与次数、逐编队战损回写及整场朝歌战斗的确定性。
- `tests/battle_check.gd`：规则、伤害时点、门槛、重复结算、编制验证、存档、122 实体碰撞压力测试。
- `tests/battle_runtime.gd`：真实键鼠、两种窗口分辨率、完整行军接战与返回。独立演武不覆盖用户存档。
- `tests/skills_check.gd` / `tests/skills_runtime.gd`：技能结算、移动力、地图施法、行动消耗、效果过期、存档迁移及真实窗口键鼠流程。
- `previews/skills/`：四技能版实际截图与规则、操作、战斗回归报告。
- `previews/battle/`：实际 Godot 截图与 JSON 报告。

命令（macOS 使用 /Applications/Godot.app/Contents/MacOS/Godot；其他系统使用 godot）：

```sh
godot --headless --editor --path . --import --quit
godot --headless --path . --script tests/battle_check.gd
godot --path . -- --battle-demo
godot --path . -- --battle-capture=/绝对路径/截图目录
```

原有经营和导航规则回归也已执行。最终测试数字、实机平均帧率及最大碰撞残余重叠见各 JSON 报告；平均帧率包含正常演武、截图和暂停，不能当作所有场景的最低帧率保证。

## 美术资源与来源

新增图通过 **内置 image_gen** 制作并保存到工程中：

- `assets/battle/motion/nezha_clean.png`：4×6 哪吒动作图，真实透明背景。
- `assets/battle/motion/zhou_halberd_clean.png`：4×5 周军双手长戟动作图；初版背景残留经 image_gen 去除，使用修正版。

从用户既有本地 Project Fengshen 工程复用已有生成素材：

- `assets/battle/fortress_amber.webp`：暖色二次元关城战场。
- `assets/battle/motion/shang.webp`：商军戟兵动作。
- `assets/battle/motion/wenzhong.webp`：闻仲动作。
- `assets/battle/motion/jifa.webp`：通用我方将领动作。
- `assets/battle/wenzhong_bust.webp`：闻仲半身立绘。
- `assets/battle/{drum,clash,fire,thunder}.wav`：原型合成音效。
- 旧哪吒头像 `assets/ui/nezha_portrait.png` 作为历史资源保留；地图与战斗人物卡均已使用 `assets/characters/nezha/nezha_fullbody_v2.png`。

### 新增周军戟兵生成提示

Use case: stylized-concept. Asset type: production transparent 2D game animation atlas. Draw ONE Chinese fantasy Zhou halberd infantryman, warm anime painted cel shaded style, vermilion cloth, ivory and bronze lamellar armor, red helmet crest, sturdy leather boots, TWO HANDED long ornate ji halberd with clearly visible crescent side blade and spear point. No shield. Full-body side three-quarter view facing RIGHT in EVERY cell. Exactly FOUR equal columns and FIVE equal rows, twenty isolated poses total on genuine transparent background, no labels or grid lines. Each cell has the same scale and hip center; feet at 88% of each cell height. Long weapon fully contained with ample transparent gutters. Row 1 four breathing idle frames. Row 2 four running frames with clearly different alternating legs. Row 3 four attack frames: draw back, swing forward, fully extended halberd strike, recover. Row 4 four hit recoil frames. Row 5 four defeat frames: stagger, kneel, collapse, lying horizontal. Keep consistent anatomy, clothing, weapon, face across all frames; readable silhouettes, polished hand-painted tactical RPG art. No background, no ground shadows, no effects, no text. Wide canvas 4:5 grid suitable for atlas slicing.

### 新增哪吒生成提示

Use case: stylized-concept. Asset type: production transparent 2D game animation atlas. ONE hero NEZHA from Chinese Fengshen fantasy. Youthful male anime hero, dark hair in two topknots with red ties, red and ivory outfit with ornate gold lotus armor, long red silk sash, TWO HANDED long fire-tipped spear. Feet in red boots, no wheels or floating props. Warm anime cel shaded painted RPG art. Full-body side three-quarter view always facing RIGHT. EXACTLY FOUR equal columns and SIX equal rows, twenty-four isolated full-body poses. Genuine transparent background no grid labels. Same body scale and hip center, feet baseline 88% of each cell; all long spears fully within each cell with generous gutters. Row 1 four subtle idle poses; row 2 four distinct running poses alternating legs; row 3 attack sequence windup, extend, strike contact, recover; row 4 hit recoil sequence; row 5 defeat stagger, kneel, collapse, lying; row 6 special cast sequence: bracing low, spear raised upward, dramatic forceful sweeping spear strike, recover. Distinct limb poses, consistent costume and identity, complete weapon in every cell. No background, no ground shadows, no magical effects, no words.

### 戟兵透明边缘修正提示

Edit this exact 4 columns by 5 rows halberd infantry animation atlas ONLY to remove the background cleanly. Keep every character, pose, weapon, position, cell layout, scale and colors exactly unchanged. Remove ALL gray/tan/pink noisy matte and ground shadows between and around the sprites. Every empty pixel outside the figures must have alpha exactly 0, clean genuinely transparent cutouts. No colored or smoky background at all. Preserve the twenty separate characters and full polearms. Output genuine transparent PNG sprite sheet.

### 哪吒图集边缘修正提示

Repair this Nezha animation atlas for use as a real game sprite sheet. Preserve this exact youthful Chinese hero design, outfit colors, fire-tipped spear, painted warm anime style, twenty-four distinct poses and EXACTLY 4 columns by 6 rows. Crucial correction: every individual character including all sash ends, both feet and entire spear must fit COMPLETELY WITHIN ITS OWN CELL, with at least 10% transparent empty padding on all four sides. Slightly reduce each character uniformly as necessary. No part may cross into neighboring cells; no cut-off cape or feet. Use equal rectangular cells; feet near 88% of cell height, hips horizontally centered at 50%, consistent character scale through idle/run/attack/recoil/fall/cast rows. Truly transparent background, alpha exactly 0 in empty space. No background wash or ground shadows, no text. Repaint silhouettes if necessary to ensure full weapons and cloth stay within each cell. Keep four columns, six rows, same facing RIGHT. Output portrait 1024x1536.

### 哪吒最终透明背景清理提示

Remove the background completely from this EXACT 4 columns by 6 rows Nezha animation sheet. Do not redraw or move or resize a single figure. Preserve every pose, face, weapon, red sash, pixel placement and entire 4x6 layout. Remove ALL beige/pink/gray haze and shadows around characters. Every empty pixel outside the figures MUST have alpha 0, clean fully transparent isolated cutouts, with NO residual translucent background. No added effects. This is strictly background removal for a game texture.

## 修正版人物图集生成提示（内置 image_gen）

### 修长闻仲

Use the attached old Wen Zhong sprite sheet ONLY as costume, identity and action reference. Create a NEW production game animation atlas of the SAME Wen Zhong as a TALL SLENDER adult martial commander with elegant eight-head adult proportions, long legs, narrow waist, lean shoulders, imposing upright stature. He must NOT be squat, chubby, dwarf-like or chibi. Same mature black-and-gray long beard, hair in a topknot, third eye, warm bronze/gold armor over dark plum robes and red-brown cape, ornate TWO long segmented bronze whips held in hands. Warm anime cel shaded tactical RPG art. Side three-quarter facing LEFT in ALL cells. Exact FOUR columns by SIX rows (24 separate sprites). Row 1 four idle poses; row 2 four running poses with alternating legs; row 3 four attack poses windup, advance, full strike, recover; row 4 four hit recoils; row 5 four defeat poses stagger, kneel, collapse, fully lying; row 6 four spellcasting poses charge, raise whip, discharge, recover. Consistent character scale, face, weapon length and hip center across all cells, 8-head physique. Standing figure body from head to soles about 72% of own cell height; planted feet at 88% cell height, pelvis centered at 50% width. Entire weapons, both feet, hair and cape fully visible and contained in each individual cell with 8% empty padding on every side. True clean alpha transparent background, empty pixels alpha zero. NO shadows, ground, background wash, colored haze, text, grid or effects. Portrait 1024x1536 sheet.

### 戟兵完整留白

Create a corrected production animation atlas using this Zhou halberd soldier design. EXACT 4 columns by 5 rows, twenty isolated frames, each character full body and entire long two-handed crescent ji halberd completely inside its own cell. Main fix: smaller illustrations inside larger empty cell gutters. Leave a STRICT 14% fully transparent border on EVERY side of EACH cell. No touching cell boundaries at all. Same warm anime vermilion and bronze/ivory armor, red helmet plume, no shield, all facing RIGHT. Consistent scale with head-to-sole standing body 65% of cell height, soles at 82% of cell, hips centered. Row1 four idle frames, row2 four running frames with alternate legs, row3 four melee attack frames windup/extend/contact/recover, row4 four hit recoil frames, row5 four fall frames ending horizontal lying body. Retain same character and equipment across poses. Recompose weapon angle as needed to keep tip and shaft fully inside the safe 72% area. TRUE transparent PNG with alpha ZERO outside the sprites, no ground, no shadows, no background wash, no glow, no text or grid lines. Portrait 1024x1280.
