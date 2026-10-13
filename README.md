# AC-8 私有破片 · AC-8 Private Fragment

**速度与寿命可调 / Speed and Life Adjustable** · v1.0.0

给 AC-8 机炮的高射炮弹一份**独立的破片行**，与其它武器彻底脱钩。

Gives the AC-8 autocannon's flak shell its own **private fragment row**, fully decoupled from every other weapon.

---

## 中文

### 功能

| 项目 | 范围 | 默认 |
|---|---|---|
| 高射炮弹速度 | 400~1500 米/秒 | 820（出厂值） |
| 破片速度 | 400~1500 米/秒 | 820 |
| 破片存活时间 | 0.05~3 秒 | 0.5 |

步长 20。共享破片行**一个字节都不动**，所以其它任何用到该破片的爆炸（R-36 爆裂铳、破片手雷、40mm 近炸、JarPhoenix、70mm 火箭、炮塔损毁等）保持出厂行为。高射炮弹弹体只被 AC-8 引用（已核对全部 1574 个数据文件、168 个武器部件），所以调整弹体速度只影响本武器。

### 物理说明（重要）

破片速度等于高射炮弹速度时，破片散布范围为前方半圆扇区；小于高射炮弹速度时，破片更向前方汇聚；大于高射炮弹速度时，破片开始向后方扩散。请勿将破片速度与高射炮弹速度的比值调整过大，否则可能导致伤害大幅提高，或破片向后对使用者造成伤害。

### 使用方式

游戏内 **MODS 标签页**提供开关与三个滑条，菜单文本**跟随游戏语言**（中文 / English 自动切换）。

菜单依赖 **ModOptionsMenu**（可选）：可单独安装，也可使用 Vanilla Plus Megapack 里内置的那个选项 —— **二选一，不要同时装**。未安装时通过配置文件控制：

```
%LOCALAPPDATA%\Hd2Ac8PrivateFrag\ac8_private_frag.cfg
```

关闭开关后**逐字节还原**所有改动。

### 安装

1. 用 Arsenal 或 HD2MM 导入 `dist/` 下的 zip
2. 启用后 **Purge → Deploy**
3. 需要 **Bingus Shared Loader v15+ / API 1**

---

## English

### Features

| Item | Range | Default |
|---|---|---|
| Shell speed | 400-1500 m/s | 820 (factory value) |
| Fragment speed | 400-1500 m/s | 820 |
| Fragment lifetime | 0.05-3 s | 0.5 |

Step 20. The shared fragment row is left **byte-for-byte untouched**, so every other explosion that uses it (R-36 Eruptor, frag grenades, 40mm proximity, JarPhoenix, 70mm rockets, destroyed turrets, and more) keeps its factory behaviour. The flak shell row is referenced only by the AC-8 (verified against all 1574 data files and 168 weapon components), so changing shell speed affects this weapon only.

### Physics note (important)

At equal fragment and shell speed, fragments cover a forward half-circle; lower converges forward, higher spreads backwards. Keep the ratio close: damage can rise sharply, or fragments can fly back and hurt the user.

### Usage

An in-game **MODS tab** provides an on/off toggle and three sliders; its text **follows the game's language** (Chinese / English switch automatically).

The menu needs **ModOptionsMenu** (optional): install it standalone, or use the option bundled in Vanilla Plus Megapack — **use one, not both**. Without it, use the config file at:

```
%LOCALAPPDATA%\Hd2Ac8PrivateFrag\ac8_private_frag.cfg
```

Turning the toggle off **restores every byte** it wrote.

### Install

1. Import the zip from `dist/` with Arsenal or HD2MM
2. Enable it, then **Purge → Deploy**
3. Requires **Bingus Shared Loader v15+ / API 1**

---

## 致谢 / Credits

本模组基于**他人模组**修改而来，在此致谢。

This mod is **based on modifications of other people's mods**. Thanks to them.

## 许可 / License

仅供个人使用。请遵守原作者的相关要求。

For personal use. Please respect the original authors' terms.
