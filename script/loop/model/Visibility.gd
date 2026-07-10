class_name Visibility
extends RefCounted

## 事件可见性等级与私密事件的信任转述阈值。
## 对照设计文档：docs/design/loop-collapse-architecture.md §3.7 / §6.2

enum Level { PUBLIC, PRIVATE, SECRET }

## 私密事件能否被转述得知的信任阈值：必须是"目击者对听者的信任"严格大于该值
## （注意方向：不是听者对目击者的信任，见 PerceptionFilter 的方向性测试）。
const PRIVATE_TRUST_THRESHOLD := 40.0

static func level_name(level: Level) -> String:
	match level:
		Level.PUBLIC: return "公开"
		Level.PRIVATE: return "私密"
		Level.SECRET: return "秘密"
		_: return "未知"
