import { AgentToolCall, AgentToolDefinition } from '../models/WorkspaceModels'
import { ScheduleArgs, SchedulePlatform, ScheduleResult } from '../models/ScheduleModels'

interface ScheduleError extends Error { code?: number }

// Platform-free tool contracts and validation; the native adapter supplies real results.
export class ScheduleService {
  static tools(): AgentToolDefinition[] {
    return JSON.parse(`[
      {"type":"function","function":{"name":"get_system_time","description":"读取设备当前日期、时间、时区。安排今天/明天等相对日期前先调用。","parameters":{"type":"object","properties":{},"additionalProperties":false}}},
      {"type":"function","function":{"name":"query_calendar_events","description":"查询系统允许访问的日历事件实例并检查冲突；范围最多31天。结果可能不包含其他应用私有日历。时间均为带时区偏移的ISO8601，例如2026-10-28T09:00:00+08:00。","parameters":{"type":"object","properties":{"start":{"type":"string"},"end":{"type":"string"}},"required":["start","end"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"create_calendar_event","description":"将用户明确要安排的事项写入系统默认日历。需要开始和结束时间；先查询冲突。提醒提前分钟数0表示准时，空数组表示无提醒。写入前应用展示核对窗口。","parameters":{"type":"object","properties":{"title":{"type":"string"},"start":{"type":"string"},"end":{"type":"string"},"description":{"type":"string"},"location":{"type":"string"},"reminderMinutes":{"type":"array","items":{"type":"number"}},"allDay":{"type":"boolean"}},"required":["title","start","end"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"update_calendar_event","description":"修改刚查询到的指定系统日程。必须使用真实calendarId/eventId；未提供字段保持不变。重复日程请在系统日历修改。","parameters":{"type":"object","properties":{"calendarId":{"type":"number"},"eventId":{"type":"number"},"title":{"type":"string"},"start":{"type":"string"},"end":{"type":"string"},"description":{"type":"string"},"location":{"type":"string"},"reminderMinutes":{"type":"array","items":{"type":"number"}}},"required":["calendarId","eventId"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"delete_calendar_event","description":"根据用户删除要求移除刚查询到的指定系统日程。需真实calendarId/eventId，删除前展示日程详情核对。","parameters":{"type":"object","properties":{"calendarId":{"type":"number"},"eventId":{"type":"number"}},"required":["calendarId","eventId"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"create_system_reminder","description":"创建本应用的系统代理提醒：alarm为按设备本地小时/分钟响铃，可用weekdays指定周一1到周日7，空数组为下一次单次；calendar为指定未来日期at，精确到整分钟；timer为seconds秒后。不是系统时钟应用里的闹钟，受设备代理提醒权益限制。失败不得称已设置，不得静默换成别的提醒。","parameters":{"type":"object","properties":{"kind":{"type":"string","enum":["alarm","calendar","timer"]},"title":{"type":"string"},"content":{"type":"string"},"at":{"type":"string"},"hour":{"type":"number"},"minute":{"type":"number"},"weekdays":{"type":"array","items":{"type":"number"}},"seconds":{"type":"number"}},"required":["kind","title"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"list_system_reminders","description":"查询本应用已发布且有效的系统代理提醒及真实reminderId，不能读取系统时钟或其他应用的闹钟。","parameters":{"type":"object","properties":{},"additionalProperties":false}}},
      {"type":"function","function":{"name":"cancel_system_reminder","description":"按用户要求取消本应用刚查询到的单个系统代理提醒。","parameters":{"type":"object","properties":{"reminderId":{"type":"number"}},"required":["reminderId"],"additionalProperties":false}}},
      {"type":"function","function":{"name":"manage_memo","description":"管理跨会话、本地持久化的备忘录。list查询标题和正文预览，read按id读完整正文（修改前先读），save新建或按id修改，delete按id删除，share打开系统分享面板由用户选择备忘录等应用保存。share仅表示打开分享入口，不能宣称已写入系统备忘录；不能读取系统备忘录私有笔记。","parameters":{"type":"object","properties":{"action":{"type":"string","enum":["list","read","save","delete","share"]},"id":{"type":"string"},"title":{"type":"string"},"content":{"type":"string"}},"required":["action"],"additionalProperties":false}}}
    ]`) as AgentToolDefinition[]
  }

  static handles(name: string): boolean { return ScheduleService.tools().some((tool) => tool.function.name === name) }

  static localLabel(instant: number): string {
    const date = new Date(instant)
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ` +
      `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
  }

  static localInstant(value: string): string {
    if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value)) throw new Error('请按本地时间填写，例如2026-10-28 09:00。')
    const date = new Date(Number(value.slice(0, 4)), Number(value.slice(5, 7)) - 1, Number(value.slice(8, 10)),
      Number(value.slice(11, 13)), Number(value.slice(14, 16)))
    if (!Number.isFinite(date.getTime()) || ScheduleService.localLabel(date.getTime()) !== value) throw new Error('日期或时间无效，请检查月份、日期和时刻。')
    return date.toISOString().replace('.000', '')
  }

  static instant(value: string): number {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
      throw new Error('时间需为带时区的 ISO8601，例如 2026-10-28T09:00:00+08:00。')
    }
    const year = Number(value.slice(0, 4)), month = Number(value.slice(5, 7)), day = Number(value.slice(8, 10))
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate()
    const offset = value.endsWith('Z') ? '00:00' : value.slice(-5)
    const stamp = Date.parse(value)
    if (!Number.isFinite(stamp) || month < 1 || month > 12 || day < 1 || day > lastDay ||
      Number(value.slice(11, 13)) > 23 || Number(value.slice(14, 16)) > 59 ||
      (value.length > 22 && value[16] === ':' && Number(value.slice(17, 19)) > 59) ||
      Number(offset.slice(0, 2)) > 14 || Number(offset.slice(3)) > 59 ||
      (Number(offset.slice(0, 2)) === 14 && Number(offset.slice(3)) !== 0)) throw new Error('日期或时间超出有效范围。')
    return stamp
  }

  static validate(name: string, raw: string): ScheduleArgs {
    const tool = ScheduleService.tools().find((item) => item.function.name === name)
    if (tool === undefined || raw.length > 20000) throw new Error('未知系统工具或参数过长。')
    const args = JSON.parse(raw) as ScheduleArgs
    if (args === null || typeof args !== 'object' || Array.isArray(args)) throw new Error('系统工具参数必须为对象。')
    const schema = tool.function.parameters
    const record = args as Record<string, Object>
    Object.keys(record).forEach((key: string) => {
      const property = schema.properties?.[key]
      const value = record[key]
      if (property === undefined) throw new Error(`不支持的字段：${key}`)
      if (property.type === 'array') {
        if (!Array.isArray(value) || (value as number[]).some((item: number) => !Number.isInteger(item))) throw new Error(`${key}必须为整数数组。`)
      } else if (typeof value !== property.type) throw new Error(`${key}类型不正确。`)
      if (property.enum !== undefined && !property.enum.includes(value as string)) throw new Error(`${key}取值不正确。`)
      if (typeof value === 'string' && value.length > (key === 'content' || key === 'description' ? 8000 : 500)) throw new Error(`${key}内容过长。`)
    })
    schema.required?.forEach((key: string) => { if (record[key] === undefined) throw new Error(`缺少字段：${key}`) })
    ;['title', 'id'].forEach((key: string) => { if (typeof record[key] === 'string' && !(record[key] as string).trim()) throw new Error(`${key}不能为空。`) })
    ;['calendarId', 'eventId', 'reminderId'].forEach((key: string) => {
      if (record[key] !== undefined && (!Number.isSafeInteger(record[key]) || (record[key] as number) < 0)) throw new Error(`${key}无效。`)
    })
    if (args.start !== undefined) ScheduleService.instant(args.start)
    if (args.end !== undefined) ScheduleService.instant(args.end)
    if (args.start !== undefined && args.end !== undefined) ScheduleService.range(args.start, args.end)
    if (args.reminderMinutes !== undefined && (args.reminderMinutes.length > 5 || args.reminderMinutes.some((n: number) => n < 0 || n > 40320))) throw new Error('提醒提前时间范围为0到40320分钟，最多5个。')
    if (name === 'update_calendar_event' && Object.keys(args).length <= 2) throw new Error('请指定要修改的日程字段。')
    if (name === 'create_system_reminder') {
      if (args.kind === 'alarm') {
        if (!Number.isInteger(args.hour) || !Number.isInteger(args.minute) || args.hour! < 0 || args.hour! > 23 || args.minute! < 0 || args.minute! > 59) throw new Error('闹钟需明确0–23小时、0–59分钟。')
        if (args.at !== undefined || args.seconds !== undefined) throw new Error('按时刻闹钟请仅提供hour、minute及weekdays。')
        if (args.weekdays !== undefined && (args.weekdays.length > 7 || args.weekdays.some((n: number) => n < 1 || n > 7))) throw new Error('星期范围为周一1到周日7。')
      } else if (args.kind === 'calendar') {
        const time = ScheduleService.instant(args.at || '')
        if (time <= Date.now() || new Date(time).getSeconds() !== 0 || new Date(time).getMilliseconds() !== 0) throw new Error('日期提醒需为未来的整分钟。')
        if (args.hour !== undefined || args.minute !== undefined || args.seconds !== undefined || args.weekdays !== undefined) throw new Error('日期提醒只使用at指定日期时间。')
      } else if (!Number.isInteger(args.seconds) || args.seconds! < 1 || args.seconds! > 604800 || args.at !== undefined || args.hour !== undefined || args.minute !== undefined || args.weekdays !== undefined) throw new Error('倒计时需为1–604800秒，不混用其他时间字段。')
    }
    if (name === 'manage_memo') {
      if (args.action === 'save' && (!args.title?.trim() || !args.content?.trim())) throw new Error('保存备忘录需标题和正文。')
      if ((args.action === 'read' || args.action === 'delete' || args.action === 'share') && !args.id) throw new Error('先查询备忘录，再使用真实id。')
    }
    return args
  }

  static range(start: string, end: string): void {
    const duration = ScheduleService.instant(end) - ScheduleService.instant(start)
    if (duration <= 0 || duration > 31 * 86400000) throw new Error('结束时间应晚于开始时间，单次范围最多31天。')
  }

  static async execute(call: AgentToolCall, platform: SchedulePlatform, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<ScheduleResult> {
    try {
      const args = ScheduleService.validate(call.name, call.arguments)
      if (!active()) return { ok: false, status: 'cancelled', message: '操作已取消。' }
      return await platform.perform(call.name, args, active, confirm)
    } catch (error) {
      const code = (error as ScheduleError).code
      return { ok: false, status: !active() ? 'cancelled' : undefined, message: code === undefined ? (error as Error).message || '系统操作失败。'
        : `系统操作失败（${code}）。请检查日历/通知授权或设备是否支持该能力；没有完成本次操作。` }
    }
  }
}
