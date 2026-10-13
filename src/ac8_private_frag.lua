-- HD2-Addon: mods/dsh/ac8_private_frag
--
-- AC-8 机炮 · 私有破片(速度/寿命可调, 不影响其它武器)
-- ============================================================================
--
-- 做什么
-- ------
--   1. 把共享破片(ProjectileType_Shrapnel)复制到一份空闲弹头行
--   2. 高射炮弹速度(母弹行)与破片速度各自可调: 均 400~1500, 默认 820, 步长 20
--   3. 副本开 inherit_velocity; 母弹开 explosions_inherit_velocity
--   4. 副本寿命 = cfg 的 frag_life (0.05~3 秒)
--   5. 只改 AC-8 那条爆炸行的 shrapnel 指针, 指向副本
--
-- 共享破片行一个字节都不动 -> 其它武器用该破片的爆炸保持出厂行为。
-- 母弹行只被 AC-8 引用(离线核过 1574 个数据文件, 168 个武器部件里只有 1 个引它)。
--
-- 配置 %LOCALAPPDATA%\Hd2Ac8PrivateFrag\ac8_private_frag.cfg
-- ---------------------------------------------------------------
--   enable=1            # 0 = 关(并把所有改动还原)
--   shell_speed=820     # 高射炮弹速度, 400~1500
--   frag_speed=820      # 破片速度, 400~1500
--   frag_life=0.5       # 秒, 0.05~3
--   scan_ms=3.0         # 查找每帧预算(毫秒)
--   frag_visible=1      # 1=副本外观与破片一致(默认); 0=副本隐形
--   cache_block=0x...   # 上次找到的表基址(自动维护, 0=不用)
-- cfg 每 240 帧重读, 改完存盘即可, 无需重启。
--
-- 定位: 找 12 字节 LDLD 签名 dlsum("ExplosionSettings")=0x2AEA2592,
--       四行由块内固定偏移算出, 每项写入前校验, 结果缓存进 cfg。
-- 依赖(已按官方 README 核对)
-- --------------------------
--   必需: Bingus Shared Loader v15+ / API 1
--         官方 docs/AUTHORING.md: "a requirement for Bingus Shared Loader
--         v15 or newer / API 1"。加载器 README 当前为 v18(v19 已出)。
--   可选: ModOptionsMenu —— 两种取得方式, **二选一, 不要同时装**:
--           (a) 独立包 CowboyBingus/ModOptionsMenu
--           (b) Vanilla Plus Megapack 里的同名选项(打包内含该 addon)
--         官方 README 原文: "Vanilla Plus Megapack also contains Mod Options
--         Menu as an option; use either the Megapack option or this package,
--         not both."
--         本模组检测 _G.ModOptionsMenu; 没有它也能跑, 只是没有游戏内菜单,
--         此时用上面的 cfg 控制。
--
-- 只在内存生效。

local NAME = 'mods/dsh/ac8_private_frag'
local KEY = 'Hd2Ac8PrivateFrag'
local REVISION = 'ac8-private-frag-1.0.0'
if rawget(_G, KEY) then return end

-- ============================================================================
-- 常量
-- ============================================================================
-- ProjectileSettings 行距 272。偏移来自 178/177 号模组实测锚点(非本模组猜测):
--   speed .20 / mass .24 / drag .28 / gravity .2C / life .34 / dmgtype .3C
--   unit .80 / impact .90 / expire .9C / flags .F0 (13 布尔位域) / raycast .F4
local P_STRIDE, P_READ = 272, 0x110
local P_TYPE, P_CAL, P_NUMP = 0x00, 0x18, 0x1C
local P_SPEED, P_MASS, P_DRAG, P_GRAV = 0x20, 0x24, 0x28, 0x2C
local P_LIFE, P_DMG = 0x34, 0x3C
local P_UNIT = 0x80
local P_IMPACT, P_EXPIRE = 0x90, 0x9C
local P_FLAGS = 0xF0
local BIT_FRAG, BIT_FWD = 1, 32

-- 外观段 0x48..0x88 (64 字节) 一次性整段复制 —— 这就是"副本隐形"的修复点。
--   破片自己 projectile_unit_path(+0x80)=0(根本没模型), 它在游戏里能被看见
--   完全靠推进粒子 particle_thruster_effect_path(+0x48) + 长度(+0x58)=0.01。
--   段内布局(偏移取自 schema 顺序 + 178 号模组实测锚点, 已交叉验证):
--     +0x48 推进粒子路径(8)  +0x50 低弹药推进粒子(8)  +0x58 粒子长度(f32)
--     +0x60 尾迹粒子(8)      +0x68 消散粒子(8)        +0x70 崩解粒子(8)
--     +0x78 命中方向提示(8)  +0x80 单位模型路径(8)
--   注意: 不复制 +0x00(type)。副本必须保留空闲行自己的 type, 否则与共享破片
--   同 type, 重定向就失去了隔离意义(共享行才是被 6 处爆炸共用的那一行)。
local P_LOOK, P_LOOK_END = 0x48, 0x88

-- ExplosionSettings 行距 152
local X_STRIDE, X_READ = 152, 0x98
local X_TYPE, X_COUNT, X_SHRAP = 0x00, 0x50, 0x54

-- LDLD 块头。dlsum 是 djb2(见经验包 05 §2), 离线交叉验证:
--   dlsum("ExplosionSettings") = 0x2AEA2592
-- 与 v1.0.x 硬编码的 X_DLSUM 一致 -> 这个块就是爆炸设置表。
-- 签名 = 'LDLD' + u32 版本 1 + u32 dlsum, 共 12 字节, 全局唯一。
local LDLD = 'LDLD'
local X_DLSUM = 0x2AEA2592
local SIG_LEN = 12

-- 块内固定偏移(两次真实会话逐位一致, 见文件头 C 说明)。
-- 每一项都用内容校验兜底: 不符 -> 整轮作废 -> 退避重试。
local OFF_SHELL = 0x022118      -- 母弹行
local OFF_BLAST = 0x0049C8      -- 爆炸行(母弹 impact 指向的那行)
local OFF_SPARE = 0x027B68      -- 空闲行(副本落点)
local OFF_FRAG  = 0x033FF8      -- 共享破片行
-- 空闲行的回退搜索范围(仅当固定偏移处不合格时, 在块内就近找)
local SPARE_REACH = 512

-- 指纹(数据转储实测) —— 仅用于**校验**固定偏移算出的行
-- ⚠️ 母弹速度不在这里校验: 发布版支持改母弹速度, 写过后 speed != 出厂值,
--    若仍拿 820 硬校验, 下次启动走缓存路径必失败 -> 反复重扫(退化成 v1.0.x 的病)。
local FLAK_MASS, FLAK_DRAG, FLAK_GRAV = 130.0, 0.3, 1.0
local FRAG_SPEED, FRAG_MASS, FRAG_DRAG, FRAG_GRAV = 30.0, 100.0, 0.4, 1.0

local VICTIM_MAX_SPEED, VICTIM_MAX_MASS = 1.0, 30.0

-- 可调参数集中放一张表: LuaJIT 每个函数**最多 60 个 upvalue**, 散着加 local
-- 会让 apply() 超限(实测撞过 "function at line ... has more than 60 upvalues")。
-- 范围/默认/步长(用户定稿): 两个速度均为 400~1500、默认 820、步长 20。
--   820 恰好落在网格上 (400 + 20*21 = 820), 所以"破片=母弹"这个临界点可精确选中。
local SPD = {
    min = 400, max = 1500, step = 20,
    shell_default = 820, frag_default = 820,
    life_min = 0.05, life_max = 3, life_step = 0.05,
}

local CHUNK = 0x10000
local SMALL_MAX = 2 * 1024 * 1024
local LOG_CAP = 128 * 1024

-- 分帧纪律(经验包 02 §3/§4): 预算检查在循环内, 且**每帧块数上限**作第二道闸
local CHUNKS_PER_FRAME = 4096

-- ============================================================================
-- FFI
-- ============================================================================
local ok_ffi, ffi = pcall(require, 'ffi')
if not ok_ffi or not ffi then return end
pcall(ffi.cdef, [[
    void *GetModuleHandleA(const char *name);
    void *GetProcAddress(void *module, const char *name);
    void *GetCurrentProcess(void);
    int ReadProcessMemory(void *, const void *, void *, size_t, size_t *);
    int WriteProcessMemory(void *, void *, const void *, size_t, size_t *);
    size_t VirtualQuery(const void *, void *, size_t);
    void *CreateFileW(const uint16_t *, uint32_t, uint32_t, void *, uint32_t, uint32_t, void *);
    int ReadFile(void *, void *, uint32_t, uint32_t *, void *);
    int WriteFile(void *, const void *, uint32_t, uint32_t *, void *);
    int CloseHandle(void *);
    int CreateDirectoryA(const char *path, void *sa);
]])
-- 零垃圾搜索用; 撞名时 pcall 吞掉, 自动走字符串回退(经验包 02 §3 的注意事项)
pcall(ffi.cdef, "void *memchr(const void *s, int c, size_t n);")
pcall(ffi.cdef, "int memcmp(const void *a, const void *b, size_t n);")

local kernel = ffi.load('kernel32')
local process = kernel.GetCurrentProcess()

-- ============================================================================
-- 内存原语(读缓冲全局复用, 热路径零分配)
-- ============================================================================
local rd_buf = ffi.new('uint8_t[?]', CHUNK)
local vq_buf = ffi.new('uint8_t[48]')
local got = ffi.new('size_t[1]')
local fb1 = ffi.new('float[1]')
local wb1 = ffi.new('uint32_t[1]')
local b64 = ffi.new('uint64_t[1]')
local b64b = ffi.new('uint64_t[1]')
local u32b = ffi.new('uint32_t[1]')
local u32b2 = ffi.new('uint32_t[1]')
local u32b3 = ffi.new('uint32_t[1]')

-- 读取计数(经验包 02 §7)
local rd_calls, rd_bytes = 0, 0

local function rd(addr, size)
    if type(addr) ~= 'number' or addr < 65536 or addr > 0x7FFFFFFFFFFF then return nil end
    if size < 1 or size > CHUNK then return nil end
    rd_calls = rd_calls + 1
    if kernel.ReadProcessMemory(process, ffi.cast('const void *', addr), rd_buf, size, got) == 0 then
        return nil
    end
    if tonumber(got[0]) ~= size then return nil end
    rd_bytes = rd_bytes + size
    return ffi.string(rd_buf, size)
end

local function u32(s, o)
    if not s or #s < o + 4 then return nil end
    local a, b, c, d = s:byte(o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function f32(s, o)
    if not s or #s < o + 4 then return nil end
    ffi.copy(fb1, s:sub(o + 1, o + 4), 4)
    return fb1[0]
end

local function fbytes(v)
    fb1[0] = v
    return ffi.string(fb1, 4)
end

local function word(v)
    wb1[0] = v
    return ffi.string(wb1, 4)
end

local function near(a, b, tol)
    return type(a) == 'number' and math.abs(a - b) <= tol
end

local SIG_STR = LDLD .. word(1) .. word(X_DLSUM)
local SIG_BYTES = ffi.new('uint8_t[12]')
ffi.copy(SIG_BYTES, SIG_STR, 12)

-- MBI 布局(64 位): +0 BaseAddress(8) +8 AllocationBase(8) +16 AllocationProtect(4)
--   +20 pad(4) +24 RegionSize(8) +32 State(4) +36 Protect(4) +40 Type(4) +44 pad(4)
local MEM_COMMIT, MEM_PRIVATE = 0x1000, 0x20000
local function mbi_reading(addr)
    if kernel.VirtualQuery(ffi.cast('const void *', addr), vq_buf, 48) ~= 48 then
        return nil
    end
    ffi.copy(b64, vq_buf, 8)
    ffi.copy(b64b, vq_buf + 24, 8)
    ffi.copy(u32b, vq_buf + 32, 4)
    ffi.copy(u32b2, vq_buf + 36, 4)
    ffi.copy(u32b3, vq_buf + 40, 4)
    local b, n = tonumber(b64[0]), tonumber(b64b[0])
    if n <= 0 or b <= 0 then return nil end
    return b, n, u32b[0], u32b2[0], u32b3[0]
end

local function writable(addr)
    local b, n, st, pr = mbi_reading(addr)
    if not b then return false end
    return addr >= b and addr < b + n and st == MEM_COMMIT
        and (pr == 0x04 or pr == 0x08)
end

-- ============================================================================
-- 日志
-- ============================================================================
local logf, logged = nil, 0
local function log(msg)
    local line = ('[Ac8PrivateFrag] %s\n'):format(tostring(msg))
    pcall(print, line:sub(1, -2))
    if logf and logged + #line <= LOG_CAP then
        local ok = pcall(function() logf:write(line); logf:flush() end)
        if ok then logged = logged + #line
        else pcall(function() logf:close() end); logf = nil end
    end
end

local told = {}
local function once(tag, msg)
    if told[tag] then return end
    told[tag] = true
    log(msg)
end

-- ============================================================================
-- 配置
-- ----------------------------------------------------------------------------
-- ⚠️ v1.0.x 的 bug(实测确认): cfg 路径写成 %LOCALAPPDATA%\Arrowhead\Helldivers2\
--    但那个目录**在干净安装上不存在**, 而 CreateFileW 不会建目录 ->
--    读不到也写不进, cfg 从未落盘(实测该目录至今不存在), 菜单改动重启即丢。
--    178 号模组的源码注释记着同一个坑。修法: 用自己的目录 + CreateDirectoryA。
-- ============================================================================
local APP_DIR, CFG_PATH = nil, nil
do
    local lad = os.getenv('LOCALAPPDATA')
    if type(lad) == 'string' and #lad > 0 then
        APP_DIR = lad .. '\\Hd2Ac8PrivateFrag'
        CFG_PATH = APP_DIR .. '\\ac8_private_frag.cfg'
    end
end

local CFG_VER = 3
-- ⚠️ frag_visible 的迁移必须用**自己的标记**, 不能挂在 cfg_ver 上。
--    实测抓到的 bug: v2.0.0 为加 cache_block 把 CFG_VER 从 2 提到 3,
--    结果 cfg_ver=2 的老用户(可能已**主动**选了 frag_visible=0)被再次迁移,
--    用户的选择被覆盖。教训: 一次性迁移要对准"它迁移的那件事", 不要复用一个
--    会因无关原因增长的版本号。
local VIS_FIX = 1
-- 发布版的"速度参数重置"也要**独立标记**。
-- 为什么不能靠范围夹紧: 老范围是 600~1200, 用户可能存了 1200; 新范围 400~1500
-- **包含** 1200, 普通 clamp 不会动它 -> 重置不了。所以必须显式标记一次。
local SPD_RESET = 1

local state = {
    frame = 0, phase = 'idle', applied = false,
    writes = 0, enable = 1,
    shell_speed = 820.0, frag_speed = 820.0, frag_life = 0.5,
    scan_ms = 3.0, frag_visible = 1, cfg_at = 0, retry_at = 0, fails = 0,
    applied_speed = nil, applied_life = nil, applied_shell_speed = nil,
    cfg_migrated = false, cfg_ok = false, use_cache = 0, cache_block = 0,
    cache_hit = false, anchor_from = '-',
}
-- 发布状态表: 顶层 `if rawget(_G, KEY) then return end` 靠它做"只加载一次"的守卫,
-- 测试台与排错也要靠它读 phase/writes/reads。漏了这行守卫就形同虚设。
rawset(_G, KEY, state)

local function to_wide(s)
    local arr = ffi.new('uint16_t[?]', #s + 1)
    for i = 1, #s do arr[i - 1] = s:byte(i) end
    arr[#s] = 0
    return arr
end

local function read_utf16(path)
    local f = kernel.CreateFileW(to_wide(path), 0x80000000, 1, nil, 3, 0x08000000, nil)
    if f == nil or f == ffi.cast('void *', -1) then return nil end
    local buf = ffi.new('uint8_t[?]', 8192)
    local n = ffi.new('uint32_t[1]')
    local ok = kernel.ReadFile(f, buf, 8192, n, nil)
    kernel.CloseHandle(f)
    if ok == 0 then return nil end
    return ffi.string(buf, tonumber(n[0]))
end

local function ensure_dir(path)
    if not path then return false end
    -- 目录已存在时返回 0 且 GetLastError=ERROR_ALREADY_EXISTS; 不区分,
    -- 后续 CreateFileW 成功与否才是判据。
    pcall(kernel.CreateDirectoryA, path, nil)
    return true
end

local function write_all(path, text)
    local f = kernel.CreateFileW(to_wide(path), 0x40000000, 0, nil, 2, 0x08000000, nil)
    if f == nil or f == ffi.cast('void *', -1) then return false end
    local n = ffi.new('uint32_t[1]')
    kernel.WriteFile(f, text, #text, n, nil)
    kernel.CloseHandle(f)
    return true
end

local function clamp(v, lo, hi)
    if not v or v ~= v then return lo end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- 速度值的统一处理: **先吸附步长, 再夹紧**。
-- 顺序很重要: 先夹再吸附会把 1007 吸成 1010, 可能越上界。
-- ⚠️ 定义必须放在 load_cfg 之前: load_cfg 的迁移路径要用它。
--    (踩过的坑: 曾把 speed_snap 放在 apply() 附近, 结果 load_cfg 里调用到的是
--     未定义的全局 -> 迁移时静默失效。同类问题在 sig_off 上也犯过一次。)
local function speed_snap(v, fallback)
    v = tonumber(v)
    if not v then return fallback end
    v = math.floor(v / SPD.step + 0.5) * SPD.step
    if v < SPD.min then return SPD.min end
    if v > SPD.max then return SPD.max end
    return v
end

local save_cfg_all          -- 前置声明(load_cfg 的迁移路径要用)

local function load_cfg()
    if not CFG_PATH then return end
    local txt = read_utf16(CFG_PATH)
    if not txt then
        if ensure_dir(APP_DIR) then
            state.cfg_ok = write_all(CFG_PATH, table.concat({
                '# AC-8 私有破片 - 配置\r\n',
                '# 改完存盘, 游戏里约 4 秒后生效(无需重启)\r\n',
                ('cfg_ver=%d\r\n'):format(CFG_VER),
                ('vis_fix=%d\r\n'):format(VIS_FIX),
                ('spd_reset=%d\r\n'):format(SPD_RESET),
                'enable=1\r\n', ('shell_speed=%d\r\n'):format(SPD.shell_default),
                ('frag_speed=%d\r\n'):format(SPD.frag_default),
                'frag_life=0.5\r\n',
                'scan_ms=3.0\r\n', 'frag_visible=1\r\n', 'cache_block=0\r\n',
            }))
        end
        return
    end
    state.cfg_ok = true
    local vals = {}
    for k, v in txt:gmatch('([%a_]+)%s*=%s*([%-%d%.xXa-fA-F]+)') do
        vals[k] = tonumber(v)
    end
    local migrated = false
    -- v1.0.0 的默认 frag_visible=0, 而那版没抄外观段 -> 副本会隐形。
    -- 只看 vis_fix 标记: 没有或不低于 1 就不再动, 用户自己的选择永远被尊重。
    if (vals.vis_fix or 0) < VIS_FIX then
        if (vals.frag_visible or 0) == 0 then vals.frag_visible = 1 end
        vals.vis_fix = VIS_FIX
        migrated = true
    end
    -- 发布版把速度参数换成新范围/新默认, 旧值一律重置为 820。
    -- 必须**显式**重置: 老范围 600~1200 的旧值(如 1200)落在新范围 400~1500 内,
    -- 光靠 clamp 不会改它 —— 这是"重置成默认"和"夹到范围内"的区别。
    if (vals.spd_reset or 0) < SPD_RESET then
        vals.shell_speed = SPD.shell_default
        vals.frag_speed = SPD.frag_default
        vals.spd_reset = SPD_RESET
        migrated = true
    end
    if vals.enable then state.enable = clamp(vals.enable, 0, 1) end
    if vals.shell_speed then
        state.shell_speed = speed_snap(vals.shell_speed, SPD.shell_default)
    end
    if vals.frag_speed then
        state.frag_speed = speed_snap(vals.frag_speed, SPD.frag_default)
    end
    if vals.frag_life then state.frag_life = clamp(vals.frag_life, 0.05, 3) end
    if vals.scan_ms then state.scan_ms = clamp(vals.scan_ms, 0.5, 20) end
    if vals.frag_visible then state.frag_visible = clamp(vals.frag_visible, 0, 1) end
    if vals.cache_block and vals.cache_block > 65536
        and vals.cache_block < 0x7FFFFFFFFFFF then
        state.cache_block = vals.cache_block
    end
    if migrated and not state.cfg_migrated then
        state.cfg_migrated = true
        local okw = save_cfg_all()
        once('cfgver', ('配置已升级到 v%d (frag_visible=%d, 写入=%s)')
            :format(CFG_VER, state.frag_visible, tostring(okw)))
    end
end

save_cfg_all = function()
    if not CFG_PATH then return false end
    ensure_dir(APP_DIR)
    return write_all(CFG_PATH, table.concat({
        '# AC-8 私有破片 - 配置\r\n',
        '# 改完存盘, 游戏里约 4 秒后生效(无需重启)\r\n',
        ('cfg_ver=%d\r\n'):format(CFG_VER),
        ('vis_fix=%d\r\n'):format(VIS_FIX),
        ('spd_reset=%d\r\n'):format(SPD_RESET),
        ('enable=%d\r\n'):format(state.enable),
        ('shell_speed=%.0f\r\n'):format(state.shell_speed),
        ('frag_speed=%.0f\r\n'):format(state.frag_speed),
        ('frag_life=%.2f\r\n'):format(state.frag_life),
        ('scan_ms=%.1f\r\n'):format(state.scan_ms),
        ('frag_visible=%d\r\n'):format(state.frag_visible),
        ('cache_block=0x%X\r\n'):format(state.cache_block or 0),
    }))
end

-- ============================================================================
-- 区域收集
-- ----------------------------------------------------------------------------
-- 经验包 01 方法一: 游戏把配置放在**固定大小的私有分配**里。
-- 候选顺序 = 私有&可写&不太大 -> 可写 -> 全部可读(退路)。
-- ============================================================================
local regions_all, regions_fast, regions_priv = nil, nil, nil

local function collect_regions()
    if regions_all then return end
    local all, fast, priv = {}, {}, {}
    local address, guard = 65536, 0
    while address < 0x800000000000 do
        guard = guard + 1
        if guard > 400000 then break end
        local b, n, st, pr, mt = mbi_reading(address)
        if not b then break end
        -- VirtualQuery 对空洞返回"跨到下一个分配区"的大跨度(真实语义)
        if st == MEM_COMMIT and n >= 65536 then
            local readable = (pr == 2 or pr == 4 or pr == 8 or pr == 32
                or pr == 64 or pr == 128)
            if readable then
                all[#all + 1] = { base = b, size = n }
                if pr == 4 or pr == 8 or pr == 64 or pr == 128 then
                    fast[#fast + 1] = { base = b, size = n }
                    if mt == MEM_PRIVATE and n <= SMALL_MAX then
                        priv[#priv + 1] = { base = b, size = n }
                    end
                end
            end
        end
        local nxt = b + n
        if nxt <= address then break end
        address = nxt
    end
    table.sort(all, function(x, y) return x.size < y.size end)
    table.sort(fast, function(x, y) return x.size < y.size end)
    table.sort(priv, function(x, y) return x.size < y.size end)
    regions_all, regions_fast, regions_priv = all, fast, priv
end

-- ============================================================================
-- 状态
-- ============================================================================
local flak_row, frag_row, blast_row = nil, nil, nil
local victim = nil
local hunt = nil
local undo, undo_n = {}, 0
local flak_found, frag_found, blast_found = false, false, false

-- ============================================================================
-- 零垃圾分块搜索(memchr 预筛 + memcmp 确认) —— 照 M-103 V1.35 / APW
-- ============================================================================
local memchr_c, memcmp_c, C_SEARCH_OK = nil, nil, false
do
    local ok = pcall(function()
        memchr_c, memcmp_c = ffi.C.memchr, ffi.C.memcmp
        local probe = ffi.new('uint8_t[4]', { 0x4C, 0x44, 0x4C, 0x44 })
        assert(memchr_c(probe, 0x4C, 4) ~= nil, 'memchr nil')
        assert(memcmp_c(probe, probe, 4) == 0, 'memcmp ne')
    end)
    C_SEARCH_OK = ok
end

-- ⚠️ sig_off 必须在 find_sig_in_buf **之前**声明为 local:
--    否则函数里写的是全局 sig_off, 而后面 `local sig_off` 是另一个变量,
--    调用方永远读到 0 —— 这正是第一版草稿里的 bug。
local sig_off = 0

-- 在 rd_buf 的前 n 字节里找 12 字节签名; 只记**第一个**命中的缓冲内偏移
-- (命中就停, 不继续找 —— 设置表只有一份, 省掉剩余扫描)。
-- 返回 true 表示找到。
local function find_sig_in_buf(n)
    if n < SIG_LEN then return false end
    if C_SEARCH_OK then
        local cursor = ffi.cast('uint8_t *', rd_buf)
        local remaining = n
        while remaining >= SIG_LEN do
            local hit = memchr_c(cursor, 0x4C, remaining - (SIG_LEN - 1))
            if hit == nil then return false end
            hit = ffi.cast('uint8_t *', hit)
            local step = tonumber(hit - cursor)
            if memcmp_c(hit, SIG_BYTES, SIG_LEN) == 0 then
                sig_off = step
                return true
            end
            remaining = remaining - step - 1
            cursor = hit + 1
        end
        return false
    end
    local blob = ffi.string(rd_buf, n)
    local j = blob:find(SIG_STR, 1, true)
    if j then
        sig_off = j - 1
        return true
    end
    return false
end

-- ============================================================================
-- 校验: 固定偏移算出来的行必须逐项验过才敢写
-- ============================================================================
local function verify_flak(b)
    -- 只校验**不会被动到的**字段。speed 故意不查:
    -- 发布版允许改母弹速度, 写过后 speed 就不再是 820, 若在这里查会导致
    -- 缓存复验失败 -> 每次启动都重扫。
    return b ~= nil
        and near(f32(b, P_MASS), FLAK_MASS, 0.5)
        and near(f32(b, P_DRAG), FLAK_DRAG, 0.01)
        and near(f32(b, P_GRAV), FLAK_GRAV, 0.01)
        and (u32(b, P_IMPACT) or 0) ~= 0
end

local function verify_frag(b)
    return b ~= nil
        and near(f32(b, P_SPEED), FRAG_SPEED, 0.1)
        and near(f32(b, P_MASS), FRAG_MASS, 0.5)
        and near(f32(b, P_DRAG), FRAG_DRAG, 0.01)
        and (u32(b, P_IMPACT) or 0) == 0
        and (u32(b, P_EXPIRE) or 0) == 0
end

local function verify_spare(b, flak_type, frag_tp)
    if not b then return false end
    local sp, ms = f32(b, P_SPEED), f32(b, P_MASS)
    if not sp or sp > VICTIM_MAX_SPEED then return false end
    if not ms or ms > VICTIM_MAX_MASS then return false end
    if (u32(b, P_IMPACT) or 0) ~= 0 then return false end
    if (u32(b, P_EXPIRE) or 0) ~= 0 then return false end
    local lo, hi = u32(b, P_UNIT), u32(b, P_UNIT + 4)
    if not lo or not hi or lo ~= 0 or hi ~= 0 then return false end
    local tp = u32(b, P_TYPE)
    if not tp or tp < 1 or tp > 8191 then return false end
    if frag_tp and tp == frag_tp then return false end
    if flak_type and tp == flak_type then return false end
    return true
end

-- ============================================================================
-- 锚定: 找 LDLD 块头 -> 由固定偏移算四行(每项都校验)
-- ============================================================================
local function resolve_from_block(block)
    -- 四次**定点小读**(每次 ~272 字节)。不整表读:
    --   rd() 单次上限 CHUNK(64KB), 而固定偏移最大 0x33FF8;
    --   定点读 4 次 ≈ 4 us, 比读 213 KB 更省, 也不必造大字符串。
    local bshell = rd(block + OFF_SHELL, P_READ)
    if not verify_flak(bshell) then
        once('vflak', ('固定偏移校验失败: 母弹行(块+0x%X) speed=%s mass=%s impact=%s')
            :format(OFF_SHELL, tostring(f32(bshell or '', P_SPEED)),
                tostring(f32(bshell or '', P_MASS)),
                tostring(u32(bshell or '', P_IMPACT))))
        return false
    end
    local bfrag = rd(block + OFF_FRAG, P_READ)
    if not verify_frag(bfrag) then
        once('vfrag', ('固定偏移校验失败: 共享破片行(块+0x%X) speed=%s mass=%s')
            :format(OFF_FRAG, tostring(f32(bfrag or '', P_SPEED)),
                tostring(f32(bfrag or '', P_MASS))))
        return false
    end
    local want = u32(bshell, P_IMPACT)
    local flak_tp = u32(bshell, P_TYPE)
    local frag_tp = u32(bfrag, P_TYPE)
    local bblast = rd(block + OFF_BLAST, X_READ)
    local got_t = u32(bblast or '', X_TYPE)
    if got_t ~= want then
        once('vblast', ('固定偏移校验失败: 爆炸行(块+0x%X) type=%s 母弹 impact=%s')
            :format(OFF_BLAST, tostring(got_t), tostring(want)))
        return false
    end

    -- 空闲行: 先在固定偏移处试; 不合格就在块内就近找(有上限、有预算)
    local spare_off, bspare = OFF_SPARE, rd(block + OFF_SPARE, P_READ)
    local spare_from = 'fixed'
    if not verify_spare(bspare, flak_tp, frag_tp) then
        spare_off, bspare = nil, nil
        spare_from = 'search'
        local spent = 0
        for k = 1, SPARE_REACH do
            for sgn = 1, 2 do
                local off = OFF_SPARE + (sgn == 1 and k or -k) * P_STRIDE
                if off > 0 then
                    spent = spent + 1
                    local b = rd(block + off, P_READ)
                    if verify_spare(b, flak_tp, frag_tp) then
                        spare_off, bspare = off, b
                        break
                    end
                    if spent >= 2048 then break end
                end
            end
            if spare_off or spent >= 2048 then break end
        end
        if not spare_off then
            once('vspare', ('固定偏移处的空闲行不合格, 且在块内 ±%d 行也没找到 -> 本轮作废')
                :format(SPARE_REACH))
            return false
        end
    end

    flak_row, frag_row, blast_row = block + OFF_SHELL, block + OFF_FRAG, block + OFF_BLAST
    victim = block + spare_off
    flak_found, frag_found, blast_found = true, true, true
    log(('锚定成功(固定偏移): 块 @0x%X  母弹 @0x%X  破片 @0x%X  爆炸 @0x%X  空闲 @0x%X [%s]')
        :format(block, flak_row, frag_row, blast_row, victim, spare_from))
    log(('  校验: 母弹 %.0f/%.0f drag %.2f type=%s | 破片 %.0f/%.0f type=%s | 爆炸 type=%s | 空闲 type=%s speed=%.2f')
        :format(f32(bshell, P_SPEED), f32(bshell, P_MASS), f32(bshell, P_DRAG),
            tostring(flak_tp), f32(bfrag, P_SPEED), f32(bfrag, P_MASS),
            tostring(frag_tp), tostring(got_t),
            tostring(u32(bspare, P_TYPE)), f32(bspare, P_SPEED) or -1))
    state.anchor_from = spare_from
    return true
end

-- ============================================================================
-- 锚定切片(预算检查在**循环内部** + 每帧块数上限)
-- ============================================================================
local function start_anchor(pass)
    collect_regions()
    local list
    if pass == 1 then list = regions_priv
    elseif pass == 2 then list = regions_fast
    else list = regions_all end
    if not list or #list == 0 then return nil end
    local total = 0
    for i = 1, #list do total = total + list[i].size end
    log(('开始锚定 pass%d: %d 个区域, 共 %.1f MB')
        :format(pass, #list, total / 1048576))
    return { pass = pass, list = list, ri = 1, off = 0, scanned = 0, total = total }
end

-- 返回 (done, found)
local function step_anchor()
    local deadline = os.clock() + state.scan_ms / 1000
    local chunks = 0
    local list = hunt.list
    while true do
        if chunks % 8 == 0 and os.clock() > deadline then return false, false end
        if chunks > CHUNKS_PER_FRAME then return false, false end

        local r = list[hunt.ri]
        if not r then
            if hunt.pass < 3 then
                log(('pass%d 未命中: 走过 %.1f MB'):format(
                    hunt.pass, hunt.scanned / 1048576))
                hunt = start_anchor(hunt.pass + 1)
                if not hunt then return true, false end
                list = hunt.list
                r = list[hunt.ri]
                if not r then return true, false end
            else
                log(('锚定结束(3 轮全空): 共走过 %.1f MB')
                    :format(hunt.scanned / 1048576))
                hunt = false
                return true, false
            end
        end
        local remaining = r.size - hunt.off
        if remaining <= 0 then
            hunt.ri, hunt.off = hunt.ri + 1, 0
        else
            chunks = chunks + 1
            local want = CHUNK
            if want > remaining then want = remaining end
            local chunk = rd(r.base + hunt.off, want)
            local at = r.base + hunt.off
            hunt.off = hunt.off + want
            hunt.scanned = hunt.scanned + want
            if chunk and find_sig_in_buf(want) then
                local block = at + sig_off
                log(('签名命中 @0x%X (pass%d, 走过 %.1f MB)')
                    :format(block, hunt.pass, hunt.scanned / 1048576))
                if resolve_from_block(block) then
                    hunt = false
                    return true, true
                end
                once('resolve_fail', '签名命中但固定偏移校验不过 -> 继续找下一个块')
            end
        end
    end
end

-- ============================================================================
-- 缓存路径: 直接用上次的块基址试(零扫描)
-- ============================================================================
local function try_cache()
    local blk = state.cache_block
    if not blk or blk <= 65536 then return false end
    local head = rd(blk, SIG_LEN)
    if not head or head ~= SIG_STR then
        if state.cache_hit then
            log(('缓存块 @0x%X 签名不符 -> 丢弃, 回退锚定'):format(blk))
        end
        state.cache_block = 0
        return false
    end
    if resolve_from_block(blk) then
        state.cache_hit = true
        state.anchor_from = 'cache'
        return true
    end
    state.cache_block = 0
    return false
end

-- ============================================================================
-- 写入(记录原始值, 读回校验)
-- ============================================================================
local function write_at(addr, bytes, label)
    local len = bytes and #bytes or 0
    if len < 1 or len > 256 then return false end
    local cur = rd(addr, len)
    if cur == nil then
        once('wf' .. label, ('跳过(读不到): %s @0x%X'):format(label, addr))
        return false
    end
    if cur == bytes then return true end
    if not (writable(addr) and writable(addr + len - 1)) then
        once('wp' .. label, ('跳过(页不可写): %s @0x%X'):format(label, addr))
        return false
    end
    if undo[addr] == nil then undo[addr] = cur; undo_n = undo_n + 1 end
    local n = ffi.new('size_t[1]')
    if kernel.WriteProcessMemory(process, ffi.cast('void *', addr), bytes, len, n) == 0
        or tonumber(n[0]) ~= len then
        log(('写入失败: %s @0x%X'):format(label, addr))
        return false
    end
    if rd(addr, len) ~= bytes then
        log(('读回不符: %s @0x%X'):format(label, addr))
        return false
    end
    state.writes = state.writes + 1
    if len == 4 then
        log(('写入 %-20s @0x%X = %d'):format(label, addr, u32(bytes, 0) or -1))
    else
        log(('写入 %-20s @0x%X = %d 字节 (块首 = %d)')
            :format(label, addr, len, u32(bytes, 0) or -1))
    end
    return true
end

-- ============================================================================
-- 应用
-- ============================================================================
-- 处理用户输入的速度值: **先吸附步长, 再夹紧**。
-- 顺序很重要: 先夹再吸附会把 1007 吸成 1010, 越上界(max 可能不是 step 的整数倍)。
-- 唯一入口, apply() 与 tick 的参数变更都走这里, 避免两条路径行为不一致。
-- (实现已提到前面 —— load_cfg 的迁移路径也要用它)

-- 只报"能确定的事实": 破片速度 与 **当前** 高射炮弹速度 的比值。
-- 不报"最大偏角""余量百分比"之类 —— 那些是推算, 没有实测依据。
-- ⚠️ 分母用 state.shell_speed, 不能用常量 820: 发布版允许改母弹速度,
--    用常量会让日志里的比值恒等于错的。
local function speed_verdict(s)
    local base = tonumber(state.shell_speed) or SPD.shell_default
    if base <= 0 then base = SPD.shell_default end
    local r = s / base
    if r < 1.0 then
        return ('破片速度 = 高射炮弹速度的 %.0f%% (低于它)')
            :format(r * 100)
    elseif r > 1.0 then
        return ('破片速度 = 高射炮弹速度的 %.0f%% (高于它)')
            :format(r * 100)
    else
        return '破片速度 = 高射炮弹速度 (比值 1.00)'
    end
end

local function apply()
    if not (flak_row and frag_row and blast_row and victim) then return false end
    local sb = rd(frag_row, P_READ)
    if not sb then return false end
    local ok_any = false

    -- (a) 母弹: 开 bit5(爆炸才会带上母弹速度) + 写入可调的速度
    --     速度写入做成幂等: 已经在目标值就跳过, 免得稳态每帧都写。
    local fbody = rd(flak_row, P_READ)
    if fbody then
        local fl = u32(fbody, P_FLAGS) or 0
        if math.floor(fl / BIT_FWD) % 2 == 0 then
            ok_any = write_at(flak_row + P_FLAGS, word(fl + BIT_FWD),
                'shell.flags+bit5') or ok_any
        else
            ok_any = true
        end
        local want_shell = speed_snap(state.shell_speed, SPD.shell_default)
        local cur_shell = f32(fbody, P_SPEED)
        if cur_shell == nil or not near(cur_shell, want_shell, 0.01) then
            ok_any = write_at(flak_row + P_SPEED, fbytes(want_shell),
                'shell.speed') or ok_any
        end
    end

    -- (b) 副本外观段: 0x48..0x88 整段复制 —— 决定副本"看得见"还是"隐形"
    if state.frag_visible == 1 then
        if u32(sb, P_LOOK) == 0 and u32(sb, P_LOOK + 4) == 0 then
            once('nosrc', '共享破片自身外观段为空 -> 副本仍然看不见(版本可能不同)')
        else
            ok_any = write_at(victim + P_LOOK,
                sb:sub(P_LOOK + 1, P_LOOK_END), 'clone.look(外观段)') or ok_any
        end
    else
        once('nolook', 'frag_visible=0 -> 不抄外观段, 副本不可见(只保留弹道/伤害)')
    end

    -- (b2) 副本数值: 按 CFG 设速度/寿命, 其余照抄共享破片
    local frag_flags = (u32(sb, P_FLAGS) or 0) + BIT_FRAG
    -- (b2) 副本数值: 按 CFG 设速度/寿命, 其余照抄共享破片
    --     速度同样走 speed_snap: 保证菜单显示值与写进内存的值一致。
    local frag_flags = (u32(sb, P_FLAGS) or 0) + BIT_FRAG
    local frag_v = speed_snap(state.frag_speed, SPD.frag_default)
    local plan = {
        { P_CAL, sb:sub(P_CAL + 1, P_CAL + 4), 'clone.calibre' },
        { P_NUMP, word(1), 'clone.num_projectiles' },
        { P_SPEED, fbytes(frag_v), 'clone.speed' },
        { P_MASS, sb:sub(P_MASS + 1, P_MASS + 4), 'clone.mass' },
        { P_DRAG, sb:sub(P_DRAG + 1, P_DRAG + 4), 'clone.drag' },
        { P_GRAV, sb:sub(P_GRAV + 1, P_GRAV + 4), 'clone.gravity' },
        { P_LIFE, fbytes(state.frag_life), 'clone.life_time' },
        { P_DMG, sb:sub(P_DMG + 1, P_DMG + 4), 'clone.damage_type' },
        { P_FLAGS, word(frag_flags), 'clone.flags+bit0' },
    }
    for i = 1, #plan do
        ok_any = write_at(victim + plan[i][1], plan[i][2], plan[i][3]) or ok_any
    end

    -- (c) 重定向: 只改 AC-8 那条爆炸行
    local vt = u32(rd(victim + P_TYPE, 4) or '', 0)
    if not vt then return ok_any end
    local cur = rd(blast_row + X_SHRAP, 4)
    if cur == word(vt) then
        ok_any = true
    else
        ok_any = write_at(blast_row + X_SHRAP, word(vt), 'blast.shrapnel_ptr') or ok_any
        log(('重定向: AC-8 爆炸 -> 副本 type %d; 共享行 0x%X 未改动')
            :format(vt, frag_row))
    end

    if ok_any then
        log(('配置生效: 高射炮弹速度=%.0f  frag_speed=%.0f  frag_life=%.2f'):format(
            speed_snap(state.shell_speed, SPD.shell_default),
            frag_v, state.frag_life))
        log(('  speed 判定: %s'):format(speed_verdict(frag_v)))
        log('  共享行保持出厂 -> 其它用该破片的爆炸不受影响')
    end
    return ok_any
end

-- ============================================================================
-- 还原
-- ============================================================================
local function restore()
    local n = 0
    for addr, orig in pairs(undo) do
        local len = #orig
        local cur = rd(addr, len)
        if cur and cur ~= orig and writable(addr) and writable(addr + len - 1) then
            local c = ffi.new('size_t[1]')
            if kernel.WriteProcessMemory(process, ffi.cast('void *', addr), orig, len, c) ~= 0
                and tonumber(c[0]) == len then
                n = n + 1
            end
        end
    end
    undo, undo_n = {}, 0
    return n
end

-- ============================================================================
-- 存活检查(3 次小读, 稳态每 60 帧一步)
-- ============================================================================
local function alive()
    if not (frag_row and blast_row and victim) then return false end
    if rd(frag_row, 4) == nil then return false end
    local vt = u32(rd(victim + P_TYPE, 4) or '', 0)
    if not vt then return false end
    return u32(rd(blast_row + X_SHRAP, 4) or '', 0) == vt
end

-- ============================================================================
-- STATUS(经验包 02 §7)
-- ============================================================================
local function write_status()
    if not APP_DIR then return end
    ensure_dir(APP_DIR)
    write_all(APP_DIR .. '\\Ac8PrivateFrag_STATUS.log', table.concat({
        ('version=%s\r\n'):format(REVISION),
        ('phase=%s applied=%s cache_hit=%s anchor_from=%s\r\n'):format(
            state.phase, tostring(state.applied), tostring(state.cache_hit),
            state.anchor_from),
        ('writes=%d undo=%d\r\n'):format(state.writes, undo_n),
        ('reads=%d bytes=%.2f MB   <-- 验收: 稳态每 60 帧个位数读\r\n')
            :format(rd_calls, rd_bytes / 1048576),
        ('shell_speed=%.0f frag_speed=%.0f frag_life=%.2f frag_visible=%d\r\n'):format(
            state.shell_speed, state.frag_speed, state.frag_life, state.frag_visible),
        ('block=0x%X  search_kernel=%s\r\n'):format(
            state.cache_block or 0, C_SEARCH_OK and 'memchr/memcmp' or 'string.find'),
    }))
end

-- ============================================================================
-- 游戏内菜单(可选依赖: ModOptionsMenu; megapack 或独立包都行)
-- 该全局不存在时整段不运行, cfg 仍是唯一入口。
-- ============================================================================
local MENU_ID = {
    enable = 'ac8_pf_enable',
    shell  = 'ac8_pf_shell_speed',
    speed  = 'ac8_pf_speed',
    life   = 'ac8_pf_life',
}
-- mod_id: 让分类稳定(官方 README: mod_id 是"首选", api version 3 起支持)。
-- 有它之后, 分类不再依赖"菜单名第一次注册时是什么", 改语言也不会裂成两类。
local MENU_MOD_ID = 'dsh.ac8_private_frag'
-- 范围/步长统一取自 SPD(见文件开头), 免得两处各写一份日后不同步。
local MENU_SPEED = { min = SPD.min, max = SPD.max, step = SPD.step }
local MENU_LIFE = { min = SPD.life_min, max = SPD.life_max, step = SPD.life_step }
local MENU = { done = false, failed = false }

-- ============================================================================
-- 语言探测 + 双语取词
-- ----------------------------------------------------------------------------
-- 机制(已查证, 依据部署版 ModOptionsMenu v3 的源码 + 官方 README):
--   label / mod / description 可以传**函数**, 菜单在注册时和**每次打开 ESC
--   菜单时**重新调用 -> 改语言后重开菜单即生效, 不需要重进游戏。
--   官方 README: "may be a function that returns the text in the current
--   language ... The menu calls it when you register and again each time the
--   escape menu opens".
--
-- 语言来源顺序(与 MOM 内部 M.language() 保持一致):
--   BingusTranslations.override > game_language > steam_language
-- 读不到就英文 —— 不猜。实测本机日志: "text language: zh-Hans (game setting cn)"。
--
-- ⚠️ 部署版 MOM 的 api 表**没有** language 字段(实测), 别去读它; 语言在
--    全局 _G.BingusTranslations 里。
-- ============================================================================
local function read_language()
    local reg = rawget(_G, 'BingusTranslations')
    if type(reg) == 'table' then
        if type(reg.override) == 'string' and reg.override ~= '' then
            return reg.override, 'override'
        end
        if type(reg.game_language) == 'string' and reg.game_language ~= '' then
            return reg.game_language, 'game'
        end
        if type(reg.steam_language) == 'string' and reg.steam_language ~= '' then
            return reg.steam_language, 'steam'
        end
    end
    -- 兼容: 若将来 MOM 真的导出了 language, 也认
    local menu = rawget(_G, 'ModOptionsMenu')
    if type(menu) == 'table' then
        local v = menu.language
        if type(v) == 'string' and v ~= '' then return v, 'menu.str' end
        if type(v) == 'function' then
            local ok, r = pcall(v)
            if ok and type(r) == 'string' and r ~= '' then return r, 'menu.fn' end
        end
    end
    return 'en', 'default'
end

local function is_zh(l)
    return l == 'zh-Hans' or l == 'zh-Hant' or l:sub(1, 2) == 'zh'
end

-- pick 每次调用都重新取语言(**不是注册时快照**) -> 改语言后重开菜单即生效
local function pick(zh, en)
    local l = read_language()
    if is_zh(l) then return zh end
    return en
end

-- tx 返回**函数**: 交给菜单, 由菜单在需要时调用(这就是语言跟随的关键)
local function tx(zh, en)
    return function() return pick(zh, en) end
end

-- ---- 文案 -------------------------------------------------------------------
-- 母弹按游戏官方名: 英文 "20mm Flak Rounds" / 中文站与游戏内叫"高射炮弹"。
-- 长度契约: label<=64 / mod<=40 / description<=400, 且**按字符**计(部署版
-- 的 M.length 逐 UTF-8 序列计数, 一个汉字算 1)。下面每条都用部署版原样的 M.length
-- 实测过 —— 英文比中文长得多, 这里踩过一次坑:
--   FRAG_DESC_EN 原来 461 字符 > 400 -> 菜单**拒绝注册那一行**, 菜单里直接消失
--   (而中文环境正常, 因为中文同样内容只有 182 字符)。英文警告句因此压到 215。
local WARN_ZH = '破片速度等于高射炮弹速度时，破片散布范围为前方半圆扇区；'
    .. '小于高射炮弹速度时，破片更向前方汇聚；大于高射炮弹速度时，破片开始向后方扩散。'
    .. '请勿将破片速度与高射炮弹速度的比值调整过大，'
    .. '否则可能导致伤害大幅提高，或破片向后对使用者造成伤害。'
local WARN_EN = 'At equal fragment and shell speed fragments cover a forward half-circle; '
    .. 'lower converges forward, higher spreads backwards. Keep the ratio close: damage can '
    .. 'rise sharply, or fragments can fly back and hurt the user.'

local SHELL_DESC_ZH = '高射炮弹弹体初速，400~1500 米/秒，默认 820（出厂值）。' .. WARN_ZH
local SHELL_DESC_EN = 'Muzzle velocity of the flak shell, 400-1500 m/s, default 820 '
    .. '(factory value). ' .. WARN_EN
local FRAG_DESC_ZH = '破片自身抛出速度，400~1500 米/秒，默认 820（等于高射炮弹出厂初速）。'
    .. '破片合成速度 = 高射炮弹速度 + 自身抛出速度。' .. WARN_ZH
local FRAG_DESC_EN = 'Ejection speed of each fragment, 400-1500 m/s, default 820 (equal to '
    .. 'the shell factory muzzle velocity). Combined fragment speed = shell speed + ejection '
    .. 'speed. ' .. WARN_EN
local LIFE_DESC_ZH = '破片存活时间，0.05~3 秒。'
local LIFE_DESC_EN = 'Fragment lifetime, 0.05-3 seconds.'
local ENABLE_DESC_ZH = '关闭时还原本模组写入的所有改动。'
local ENABLE_DESC_EN = 'Turning this off restores every change this mod wrote.'

local function save_cfg_key(key, value)
    if not CFG_PATH then return end
    ensure_dir(APP_DIR)
    local txt = read_utf16(CFG_PATH)
    if not txt then
        write_all(CFG_PATH, key .. '=' .. value .. '\r\n')
        return
    end
    local line = key .. '=' .. value
    if txt:find('\r\n' .. key .. '=') or txt:find('^' .. key .. '=') then
        local new = txt:gsub('([\r\n]*)' .. key .. '=[^\r\n]*',
            function(prefix) return (prefix == '' and '' or prefix) .. line end, 1)
        write_all(CFG_PATH, new)
    else
        write_all(CFG_PATH, txt .. '\r\n' .. line .. '\r\n')
    end
end

local function menu_clamp(v, r, fallback)
    v = tonumber(v)
    if not v then return fallback end
    -- ⚠️ 先吸附步长再夹紧。反过来的话, 1007 会先被夹到上限(可能不是 step 的
    --    整数倍), 再吸附就超界 —— 菜单显示 1010 而内存里是 1000, 两边不一致。
    v = r.min + math.floor((v - r.min) / r.step + 0.5) * r.step
    if v < r.min then return r.min end
    if v > r.max then return r.max end
    return v
end

local function menu_step()
    if MENU.done or MENU.failed then return end
    local MOM = rawget(_G, 'ModOptionsMenu')
    if type(MOM) ~= 'table' or type(MOM.register_option) ~= 'function' then return end
    -- 契约(官方 README): ModOptionsMenu.api 恒为 1; version 表示能力级别。
    --   本机部署的是 version = 1, 所以**不能用** mod_id(version 3)或
    --   文本函数翻译(version 2) —— 那些会被旧版忽略, 白写。
    --   这里只做 api 检查: api 不是 1 就说明不是这个菜单, 直接不注册。
    if MOM.api ~= nil and MOM.api ~= 1 then return end

    -- 注册失败必须**看见**。契约: register_option 返回 true, 或 false + 原因。
    -- (旧版只检查 pcall 是否抛错, 于是"注册被拒"会被当成成功 —— 实测契约确实这么写。)
    local reg_fail = nil
    local function reg(id, spec)
        local ok2, r1, r2 = pcall(MOM.register_option, id, spec)
        if not ok2 then
            reg_fail = tostring(r1)
            return false
        end
        if r1 == false then
            reg_fail = tostring(r2)
            return false
        end
        return true
    end

    local shell = menu_clamp(state.shell_speed, MENU_SPEED, SPD.shell_default)
    local speed = menu_clamp(state.frag_speed, MENU_SPEED, SPD.frag_default)
    local life = menu_clamp(state.frag_life, MENU_LIFE, 0.5)
    -- 双语: label / mod / description 全部传**函数** -> 菜单会跟着游戏语言走。
    -- 传 mod_id 让分类稳定(不依赖首次注册时的名字)。
    local ok, err = pcall(function()
        reg(MENU_ID.enable, {
            type = 'toggle', mod_id = MENU_MOD_ID,
            mod = tx('AC-8 私有破片', 'AC-8 Private Fragment'),
            label = tx('启用模组', 'ENABLE MOD'),
            default = state.enable == 1,
            description = tx(ENABLE_DESC_ZH, ENABLE_DESC_EN),
        })
        reg(MENU_ID.shell, {
            type = 'slider', mod_id = MENU_MOD_ID,
            mod = tx('AC-8 私有破片', 'AC-8 Private Fragment'),
            label = tx('高射炮弹速度 (米/秒)', 'SHELL SPEED (m/s)'),
            min = MENU_SPEED.min, max = MENU_SPEED.max, step = MENU_SPEED.step,
            default = shell,
            description = tx(SHELL_DESC_ZH, SHELL_DESC_EN),
        })
        reg(MENU_ID.speed, {
            type = 'slider', mod_id = MENU_MOD_ID,
            mod = tx('AC-8 私有破片', 'AC-8 Private Fragment'),
            label = tx('破片速度 (米/秒)', 'FRAGMENT SPEED (m/s)'),
            min = MENU_SPEED.min, max = MENU_SPEED.max, step = MENU_SPEED.step,
            default = speed,
            description = tx(FRAG_DESC_ZH, FRAG_DESC_EN),
        })
        reg(MENU_ID.life, {
            type = 'slider', mod_id = MENU_MOD_ID,
            mod = tx('AC-8 私有破片', 'AC-8 Private Fragment'),
            label = tx('破片存活 (秒)', 'FRAGMENT LIFE (s)'),
            min = MENU_LIFE.min, max = MENU_LIFE.max, step = MENU_LIFE.step,
            default = life,
            description = tx(LIFE_DESC_ZH, LIFE_DESC_EN),
        })
        if reg_fail then
            -- 注册被拒: 记原因, 保留默认值, 不再每帧重试(cfg 仍可用)
            log('菜单注册被拒: ' .. reg_fail .. ' -> 继续用 cfg 控制')
        end

        if type(MOM.on_change) == 'function' then
            MOM.on_change(MENU_ID.enable, function(value)
                local on = value and 1 or 0
                state.enable = on
                save_cfg_key('enable', tostring(on))
                log('菜单: enable = ' .. tostring(on)
                    .. (on == 0 and ' (下一帧还原全部改动)' or ' (下一帧重新锚定并应用)'))
            end)
            MOM.on_change(MENU_ID.shell, function(value)
                state.shell_speed = menu_clamp(value, MENU_SPEED, SPD.shell_default)
                save_cfg_key('shell_speed', string.format('%.0f', state.shell_speed))
                log(('菜单: 高射炮弹速度 = %.0f mps'):format(state.shell_speed))
            end)
            MOM.on_change(MENU_ID.speed, function(value)
                state.frag_speed = menu_clamp(value, MENU_SPEED, SPD.frag_default)
                save_cfg_key('frag_speed', string.format('%.0f', state.frag_speed))
                log(('菜单: frag_speed = %.0f mps'):format(state.frag_speed))
            end)
            MOM.on_change(MENU_ID.life, function(value)
                state.frag_life = menu_clamp(value, MENU_LIFE, 0.5)
                save_cfg_key('frag_life', string.format('%.6g', state.frag_life))
                log(('菜单: frag_life = %s s'):format(
                    string.format('%.6g', state.frag_life)))
            end)
        end

        MOM.set(MENU_ID.enable, state.enable == 1)
        MOM.set(MENU_ID.shell, shell)
        MOM.set(MENU_ID.speed, speed)
        MOM.set(MENU_ID.life, life)
        local on = MOM.get(MENU_ID.enable) and 1 or 0
        local kept_shell = MOM.get(MENU_ID.shell)
        local kept_speed = MOM.get(MENU_ID.speed)
        local kept_life = MOM.get(MENU_ID.life)
        if on ~= state.enable then
            state.enable = on
            save_cfg_key('enable', tostring(on))
        end
        if kept_shell and kept_shell ~= state.shell_speed then
            state.shell_speed = kept_shell
            save_cfg_key('shell_speed', string.format('%.0f', kept_shell))
        end
        if kept_speed and kept_speed ~= state.frag_speed then
            state.frag_speed = kept_speed
            save_cfg_key('frag_speed', string.format('%.0f', kept_speed))
        end
        if kept_life and kept_life ~= state.frag_life then
            state.frag_life = kept_life
            save_cfg_key('frag_life', string.format('%.6g', kept_life))
        end
        MENU.done = true
        log(('菜单已注册: MODS 标签页 -> %s  (enable=%d, shell=%.0f, frag=%.0f, life=%.2f)')
            :format(pick('AC-8 私有破片', 'AC-8 Private Fragment'),
                state.enable, state.shell_speed,
                state.frag_speed, state.frag_life))
        log(('  语言探测: %s (来源 %s) -> 菜单文本跟随游戏语言')
            :format(read_language()))
    end)
    if not ok then
        MENU.failed = true
        log('菜单注册失败(不影响 cfg 控制): ' .. tostring(err))
    end
end

-- ============================================================================
-- 装载
-- ============================================================================
local loader = rawget(_G, 'CowboyBingusModLoader')
if type(loader) ~= 'table' or loader.api ~= 1 then return end
if type(rawget(_G, 'update')) ~= 'function' then return end

pcall(loader.open_log, 'Ac8PrivateFrag.log')
log(('AC-8 私有破片 %s 启动 (签名锚定架构)'):format(REVISION))
log('需要装载器 v15+ / API 1(必需); 菜单需 Vanilla Plus Megapack(可选)')
log('只在内存生效, 关掉即还原')
log(('搜索内核: %s'):format(C_SEARCH_OK and 'memchr/memcmp(零垃圾)'
    or 'string.find(回退)'))
load_cfg()
log(('cfg: enable=%d shell_speed=%.0f frag_speed=%.0f frag_life=%.2f scan_ms=%.1f frag_visible=%d')
    :format(state.enable, state.shell_speed, state.frag_speed, state.frag_life,
        state.scan_ms, state.frag_visible))
log(('cfg 文件: %s  (可写=%s)'):format(tostring(CFG_PATH), tostring(state.cfg_ok)))
if state.cache_block and state.cache_block > 65536 then
    state.use_cache = 1
    log(('缓存块: 0x%X (先按缓存试, 签名不符则丢弃并锚定)')
        :format(state.cache_block))
end

-- ============================================================================
-- tick
-- ============================================================================
local function tick()
    state.frame = state.frame + 1

    menu_step()

    if state.frame >= state.cfg_at + 240 then
        state.cfg_at = state.frame
        local prev_block = state.cache_block
        load_cfg()
        if state.cache_block ~= prev_block then state.use_cache = 1 end
    end

    if state.enable == 0 then
        if state.phase ~= 'off' then
            local n = restore()
            log(('已关闭, 还原 %d 处改动'):format(n))
            state.phase = 'off'
            state.applied = false
        end
        return
    end

    if state.phase == 'off' then
        hunt, flak_row, frag_row, blast_row = nil, nil, nil, nil
        victim = nil
        flak_found, frag_found, blast_found = false, false, false
        state.phase = 'idle'
        log('已重新打开 -> 重新锚定并应用')
    end

    -- 参数变了(菜单或 cfg): 已应用时只重写变了的那几项。
    -- 母弹速度也在这一路径 —— 否则拖了"高射炮弹速度"滑条要等重新锚定才生效。
    if state.applied and (state.frag_speed ~= state.applied_speed
        or state.frag_life ~= state.applied_life
        or state.shell_speed ~= state.applied_shell_speed) then
        local sb = frag_row and rd(frag_row, P_READ)
        if sb and victim then
            local frag_v = speed_snap(state.frag_speed, SPD.frag_default)
            local shell_v = speed_snap(state.shell_speed, SPD.shell_default)
            write_at(victim + P_SPEED, fbytes(frag_v), 'clone.speed(更新)')
            write_at(victim + P_LIFE, fbytes(state.frag_life), 'clone.life_time(更新)')
            if flak_row then
                write_at(flak_row + P_SPEED, fbytes(shell_v), 'shell.speed(更新)')
            end
            state.applied_speed = state.frag_speed
            state.applied_life = state.frag_life
            state.applied_shell_speed = state.shell_speed
            log(('参数已更新: 高射炮弹速度=%.0f  frag_speed=%.0f  frag_life=%.2f'):format(
                shell_v, frag_v, state.frag_life))
            log(('  speed 判定: %s'):format(speed_verdict(frag_v)))
        end
    end

    if not state.applied then
        -- 终态闸门: apply_failed 再试也是同样结果
        if state.phase == 'apply_failed' then return end
        if state.frame < state.retry_at then return end

        -- ① 缓存路径(零扫描)
        if state.use_cache == 1 then
            state.use_cache = 0
            if try_cache() then
                log('缓存命中 -> 跳过扫描')
            end
        end

        -- ② 锚定(分帧)
        if not (flak_found and frag_found and blast_found) then
            if not hunt then
                hunt = start_anchor(1)
                if not hunt then
                    once('noregions', '拿不到可读区域 -> 放弃')
                    state.phase = 'failed'
                    return
                end
            end
            local done, found = step_anchor()
            if found then
                state.cache_block = flak_row - OFF_SHELL
                save_cfg_all()
                log(('已缓存块基址 0x%X (下次启动可直接用)')
                    :format(state.cache_block))
            elseif done and not (flak_found and frag_found and blast_found) then
                -- 三轮都没找到 -> 指数退避(经验包 02 §5: 退避永不归零,
                -- 但要递增, 避免"扫描几十秒 + 退避 30 秒"打成 ~100% 占空比)
                state.fails = state.fails + 1
                local back = 1800 * math.min(state.fails, 4)
                state.retry_at = state.frame + back
                hunt, flak_row, frag_row, blast_row = nil, nil, nil, nil
                victim = nil
                flak_found, frag_found, blast_found = false, false, false
                log(('锚定失败(第 %d 次) -> 约 %.0f 秒后重试(退避递增)')
                    :format(state.fails, back / 60))
                return
            end
        end

        if flak_found and frag_found and blast_found then
            if apply() then
                state.applied = true
                state.phase = 'applied'
                state.applied_speed = state.frag_speed
                state.applied_life = state.frag_life
                log(('补丁已应用并读回校验通过; 进入零开销稳态(共写 %d 处, 记录 %d 处可还原)')
                    :format(state.writes, undo_n))
                log(('  读取计数: %d 次 / %.2f MB')
                    :format(rd_calls, rd_bytes / 1048576))
                write_status()
            else
                state.fails = state.fails + 1
                state.retry_at = state.frame + 120
                once('applyfail', ('应用未成功(见上方写入记录), 稍后重试; 已试 %d 次')
                    :format(state.fails))
                if state.fails >= 3 then
                    state.phase = 'apply_failed'
                    log('连续失败 3 次 -> 停止重试。')
                    return
                end
            end
        end
        return
    end

    -- 稳态: 每 60 帧一次存活检查(3 次小读)
    if state.phase == 'applied' and (state.frame % 60) == 0 then
        if not alive() then
            log('存活检查失败(设置表可能已重载) -> 重新锚定')
            hunt, flak_row, frag_row, blast_row = nil, nil, nil, nil
            victim = nil
            undo, undo_n = {}, 0
            flak_found, frag_found, blast_found = false, false, false
            state.applied = false
            state.phase = 'idle'
            state.use_cache = 1          -- 先试缓存(通常还是对的)
        end
        if (state.frame % 240) == 0 then write_status() end
    end
end

-- ============================================================================
-- 挂帧
-- ============================================================================
local original_update = rawget(_G, 'update')
local wrapped = function(...)
    local ok, err = pcall(tick)
    if not ok then once('tickerr', 'tick 出错: ' .. tostring(err)) end
    return original_update(...)
end
rawset(_G, 'update', wrapped)

local original_shutdown = rawget(_G, 'shutdown')
local function shutdown_wrapper(...)
    pcall(restore)
    if type(original_shutdown) == 'function' then return original_shutdown(...) end
end
rawset(_G, 'shutdown', shutdown_wrapper)

return { version = REVISION, name = NAME }
