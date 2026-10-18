extends RefCounted

## 中英文字符串表。
##
## 用法：GameSettings 启动时把它注册成一条 "zh" 的 Translation，
## 之后 English 就是 key —— 界面里直接写英文，切到中文时自动查表。
## 代码里动态拼的字符串用 tr("KEY") % [...] 取。
##
## 注意：key 必须和场景里 / 脚本里写的英文完全一致（大小写、空格都算）。

const ZH := {
	# ---------------- main menu ----------------
	"start game": "开始游戏",
	"options": "设置",
	"quit": "退出游戏",

	# ---------------- settings / pause ----------------
	"SETTINGS": "设置",
	"LANGUAGE": "语言",
	"VOLUME": "音量",
	"MUSIC": "背景音乐",
	"SFX": "界面音效",
	"FULLSCREEN": "全屏",
	"RESOLUTION": "分辨率",
	"BACK": "返回",
	"CONTINUE": "继续游戏",
	"MAIN MENU  ( NO SAVE )": "回主菜单（不保存）",
	"AUDIO & VIDEO": "声音与画面",
	"GENERAL": "常规",
	"ESC : BACK": "Esc : 返回",

	# ---------------- level hud ----------------
	"WASD MOVE    SHIFT SPRINT    E AIM + LMB BITE    SPACE STATUS    ESC PAUSE":
		"WASD 移动    左Shift 冲刺    E 瞄准 + 左键咬击    空格 状态    Esc 暂停",
	# 开场黑屏正中的那句话。
	"KILL EVERYTHING BUT YOU": "杀掉除你以外的所有东西。",
	# 第二关（玩家是蜈蚣）的开场语、死亡与 HUD。
	"KILL THEM BEFORE THEY KILL YOU": "在它们杀死你之前，杀了它们。",
	"YOU DIED": "你死了",
	# 第四关（玩家是单臂人偶）的开场黑屏标题与副标题。
	"人蛊": "人蛊",
	"活下去": "活下去",
	"HUMAN": "人",
	# 第四关：人的饥饿条与抓取吃掉的反馈。
	"HUNGER": "饥饿",
	"ATE A PREY  +%d": "吃掉了猎物  +%d",
	# 人被动获得特性：被蛇/蜈蚣/蟾蜍攻击后永久习得对应能力。
	"GAINED TRAIT": "获得特性",
	"HUMAN TRAIT VENOM": "蛇毒（挥砍附带毒素）",
	"HUMAN TRAIT CENTIPEDE_VENOM": "蜈蚣毒（毒素更烈）",
	"HUMAN TRAIT TOAD_SKIN": "蟾蜍皮（挥砍带毒）",
	"GAINED ENDURANCE": "获得韧性",
	"HUMAN TRAIT ENDURANCE": "耐饿（受到伤害降低）",
	"WASD MOVE    SHIFT SPRINT    LMB / J BITE":
		"WASD 移动    左Shift 冲刺    左键 / J 咬击",
	"LEFT": "剩余",
	# 蛇头旁边的手绘 UI（_draw 里画的，不走场景文本）。
	"HUNT": "捕猎",
	"DIGEST": "消化",
	"HUNT MODE": "捕猎模式",
	# 咬击层的提示。
	"NO TARGET": "没有目标",
	# 左侧气泡的击杀播报（Toast.kill）。
	"KILLED": "击杀",
	"ALL CLEAR": "清场完毕",
	"%d LEFT": "剩余 %d",
	"ANT": "蚂蚁",
	"SOLDIER ANT": "兵蚁",
	"QUEEN ANT": "蚁后",
	"MALE ANT": "雄蚁",
	"CENTIPEDE": "蜈蚣",
	"TOAD": "蟾蜍",
	# 通关 CG 顶部那句招呼。
	"COME OVER": "过来",
	# 通关黑屏收尾字幕。
	"THERE IS GU IN THE SOUTH.": "南疆有练蛊术。",
	# 最后一关打完、进度绕回第一关时的提示。
	"ALL CLEAR - BACK TO LEVEL 1": "全部通关，回到第一关。",
	# 第二关：蛇的饥饿值过半、开始捕食时的提示。
	"THE SNAKE IS HUNGRY": "蛇饿了，它开始捕食。",
	# 第二关：追三秒追不到、掉头去追别的猎物。
	"THE SNAKE GAVE UP ON YOU": "蛇放弃了你，转去咬别的猎物。",
	# 第二关：蜈蚣的毒咬（E）与毒液。
	"WASD MOVE    SHIFT SPRINT    LMB / J BITE    E VENOM BITE    ESC PAUSE":
		"WASD 移动    左Shift 冲刺    左键 / J 咬击    E 毒咬    Esc 暂停",
	"VENOM BITE ON": "毒咬模式：开",
	"VENOM BITE OFF": "毒咬模式：关",
	"NO VENOM LEFT": "毒液不足",
	# 第二关通关 CG 两张图的独白。
	"I cultivated gu within my own body.": "我逐渐在我身体里练蛊。",
	"Back then I never doubted anything, proud of the status and honor my power had earned.":
		"那时的我不曾怀疑什么，自豪于因为我的能力带来的地位与荣誉。",
	# 第一关通关 CG 第二段（立绘）上的那句独白。
	"This is how everyone expected me to be — the gifted child who would inherit this craft.":
		"我是这样被所有人期待着的，能继承这项技术的天才之子",

	# ---------------- 第三关：地穴（玩家是蚁后） ----------------
	"CLEAR THE NEST OF ALL INTRUDERS": "把地穴里的入侵者清光。",
	"THREATS LEFT": "剩余威胁",
	"THE COLONY STANDS ALONE": "蚁群独存——场上只剩蚂蚁。",
	"YOU TOOK OVER A NEW ANT": "你接管了另一只蚂蚁。",
	"WASD MOVE    SPACE THE NEST    ESC PAUSE":
		"WASD 移动    空格 回地穴    Esc 暂停",
	"SPACE : LEAVE THE NEST    1-9 SEND / CALL    F DEFEND    ESC PAUSE":
		"空格 出地穴    1-9 派遣 / 召回    F 派兵迎战    Esc 暂停",
	"THE NEST": "地穴",
	"FOOD": "食物",
	"WORKERS": "工蚁",
	"SOLDIERS": "兵蚁",
	"MALES": "雄蚁",
	"COLONY": "蚁群",
	"FORAGERS": "觅食的工蚁",
	"1-9 / CLICK : SEND OUT OR CALL BACK": "1-9 / 点击：派出去或叫回来",
	"WORKER": "工蚁",
	"IN THE NEST": "在地穴",
	"OUT %ds": "在外 %d 秒",
	"+%d FOOD": "+%d 食物",
	"RISK %.1f%%/s": "风险 %.1f%%/秒",
	"RETURNING": "返巢中",
	"SEND ALL": "全部派出",
	"CALL ALL": "全部召回",
	"BREEDING": "产卵",
	"FOOD PER EGG  %d": "每枚卵 %d 食物",
	"QUEEN + %d MALES": "蚁后 + %d 只雄蚁",
	"NO MALE - SLOW EGGS": "没有雄蚁，产卵变慢",
	"WAITING FOR FOOD": "食物不足，等着",
	"%.1fs": "%.1f秒",
	"DEFENSE": "防御",
	"NO THREAT": "暂无威胁",
	"INVASION  x%d": "外敌入侵  ×%d",
	"SEND %d SOLDIERS  [F]": "派 %d 只兵蚁迎战  [F]",
	"SEND %d SOLDIER  [F]": "派 %d 只兵蚁迎战  [F]",
	"NOT ENOUGH SOLDIERS": "兵蚁不够",
	"THE RAID IS DRIVEN OFF": "危机解除。",
	"THE NEST IS RAIDED": "地穴被洗劫了。",
	"A FORAGER IS LOST": "一只工蚁没有回来。",
	"FORAGE RETURN +%d": "带回 %d 食物",
	"A NEW %s IS BORN": "新生：%s",
	"ENTERED THE NEST": "回到地穴",
	"LEFT THE NEST": "离开地穴",
	"INVASION - SEND SOLDIERS": "外敌入侵，回地穴派兵蚁迎战。",
	"INVASION - SPACE TO THE NEST": "外敌入侵，按空格回地穴。",
	"The gu art gave me everything — yet I still find it too cruel.":
		"操蛊术使我获得一切。但我觉得它还是太残酷了。",
	"SNAKE": "蛇",
	"ATTACK TARGET": "攻击目标",
	"SOLDIERS ATTACK!": "兵蚁出击！",
	"KILLED! +%d FOOD": "击杀了！+%d 食物",
	"THE QUEEN AT THE NEST": "地穴里的蚁后",
	"THE QUEEN IS STARVING": "蚁后饿了，她在掉血。",
	"THE QUEEN IS DEAD": "蚁后饿死了。",
	"STARVING": "饥饿",
	"THE RAID COSTS %d WORKERS": "这一仗拿 %d 只工蚁去填。",
	"SEND %d + %d WORKERS  [F]": "派 %d 只兵蚁 + %d 只工蚁  [F]",
	"LONGER TRIPS  =  MORE FOOD,  MORE LOSSES": "在外越久 ＝ 食物越多，减员越多",
	"SURPLUS FOOD  =  FASTER EGGS": "存粮越多 ＝ 产卵越快",

	# ---------------- status page ----------------
	"SNAKE STATUS": "蛇 · 状态",
	"TRAITS": "特质",
	"BUFFS AND DEBUFFS CURRENTLY APPLIED": "当前生效的增益与减益",
	"VITALS": "体征",
	"HEALTH": "生命",
	"ATTACK": "攻击",
	"STAMINA": "体力",
	"SATIETY": "饱食度",
	"VENOM": "毒液",
	"SPEED": "速度",
	"CONTROL": "操控",
	"STATE": "状态",
	"CREATURES": "角色",
	"PLAYABLE SLOTS - MORE TO COME": "可操控槽位 · 后续解锁",
	"SPACE / ESC : CLOSE": "空格 / Esc : 关闭",
	"G / H / T : TEST DAMAGE, HEAL, TEMP BUFF": "G / H / T : 测试受伤、治疗、临时增益",

	"BASE %d  +  TRAITS %s%d": "基础 %d  +  特质 %s%d",
	"LIMB INTEGRITY   %5.1f%%": "肢体完整度   %5.1f%%",
	"%d / %d SEGMENTS INTACT      WOUNDED %d      EATEN %d":
		"%d / %d 节完整      受伤 %d      被吃 %d",

	"NORMAL": "正常",
	"WOUNDED": "受伤",
	"MAIMED": "残损",
	"CRITICAL": "濒危",
	"DEAD": "死亡",
	"EXHAUSTED": "力竭",
	"WEAK": "虚弱",
	"Starving": "饥饿",
	"Empty belly. Slow crawl and thin stamina, but a desperate burst when sprinting.":
		"空腹。爬得慢、体力上限下降，但冲刺时会拼出更快的爆发。",

	"WANDER": "游走",
	"MOUSE": "跟随鼠标",
	"KEYBOARD": "键盘",
	"EXTERNAL": "外部",
	"SPRINT": "冲刺",

	"NO ACTIVE TRAITS": "暂无特质",
	"BUFF": "增益",
	"DEBUFF": "减益",
	"PERM": "永久",
	"%ds": "%d秒",

	"SLOT %02d": "槽位 %02d",
	"ACTIVE": "操控中",
	"EMPTY": "空",
	"UNASSIGNED": "未分配",
	"RESERVED FOR THE NEXT PLAYABLE": "预留给下一个可操控角色",
	"HP %d / %d": "血量 %d / %d",
	"%d SEGMENTS": "%d 节",

	# ---------------- body map ----------------
	"NO SIGNAL": "无信号",
	"HEAD": "头",
	"TAIL": "尾",
	"DAMAGE REPORT": "损伤报告",
	"NO DAMAGE RECORDED": "暂无损伤记录",
	"SEG %02d": "第 %02d 节",
	"INTACT": "完好",
	"EATEN": "被吃",
	"+%d MORE": "还有 %d 项",

	"S-COILED BODY MAP": "S 形盘绕 · 身体图",
	"SHARP-NOSED VIPER": "尖吻蝮",

	# ---------------- traits ----------------
	"Venom Gland": "毒腺",
	"Fangs carry venom. +4 ATK.": "毒牙含毒。攻击 +4。",
	"Cold Blood": "冷血",
	"Sluggish in the cold. -12% speed.": "低温下行动迟缓。速度 -12%。",
	"Adrenaline": "肾上腺素",
	"Burst of speed from panic. +25% speed.": "应激爆发。速度 +25%。",
}
