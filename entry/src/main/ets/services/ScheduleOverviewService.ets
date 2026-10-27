import { ScheduleEntry, SchedulePlatform, ScheduleResult } from '../models/ScheduleModels'
import { ScheduleService } from './ScheduleService'

// The reminder view includes both native proxy reminders and calendar alerts.
export class ScheduleOverviewService {
  static async list(tab: string, platform: SchedulePlatform, active: () => boolean): Promise<ScheduleResult> {
    const read = (name: string, args: string): Promise<ScheduleResult> => ScheduleService.execute(
      { id: 'schedule-overview', name: name, arguments: args }, platform, active, async () => false)
    if (tab === 'memos') return read('manage_memo', '{"action":"list"}')
    const start = new Date(); start.setHours(0, 0, 0, 0)
    const args = JSON.stringify({ start: start.toISOString(), end: new Date(start.getTime() + 31 * 86400000).toISOString() })
    if (tab === 'calendar') return read('query_calendar_events', args)
    const proxy = await read('list_system_reminders', '{}')
    if (!active()) return { ok: false, message: '操作已取消。' }
    const calendar = await read('query_calendar_events', args)
    if (!active()) return { ok: false, message: '操作已取消。' }
    const alerts: ScheduleEntry[] = (calendar.entries || []).filter((entry: ScheduleEntry) => !!entry.reminderMinutes?.length)
      .map((entry: ScheduleEntry): ScheduleEntry => ({ id: entry.id, kind: entry.kind, title: entry.title,
        detail: `日历提醒 · ${entry.detail}`, calendarId: entry.calendarId, eventId: entry.eventId,
        start: entry.start, end: entry.end, reminderMinutes: entry.reminderMinutes }))
    const entries = (proxy.entries || []).concat(alerts)
    return { ok: proxy.ok || calendar.ok, partial: !proxy.ok || !calendar.ok || calendar.partial,
      entries: entries, total: entries.length,
      message: `本应用代理提醒${proxy.ok ? (proxy.entries || []).length : '读取失败'}项；未来31天日历提醒${calendar.ok ? alerts.length : '读取失败'}项。` +
        '日历提醒在系统日历中管理，不属于Agent执行任务或时钟应用闹钟。' +
        (!proxy.ok ? `\n代理提醒：${proxy.message}` : '') + (!calendar.ok || calendar.partial ? `\n日历：${calendar.message}` : '') }
  }
}
