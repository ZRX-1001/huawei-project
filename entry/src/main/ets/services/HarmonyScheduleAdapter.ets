import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit'
import { calendarManager } from '@kit.CalendarKit'
import { reminderAgentManager } from '@kit.BackgroundTasksKit'
import { notificationManager } from '@kit.NotificationKit'
import { systemDateTime } from '@kit.BasicServicesKit'
import { systemShare } from '@kit.ShareKit'
import { LocalMemo, ScheduleArgs, ScheduleEntry, SchedulePlatform, ScheduleResult } from '../models/ScheduleModels'
import { ScheduleService } from './ScheduleService'
import { MemoStore } from './MemoStore'

interface NativeScheduleError extends Error { code?: number }

export class HarmonyScheduleAdapter implements SchedulePlatform {
  private context: common.Context
  private memos: MemoStore
  private allowPrompt: boolean
  constructor(context: common.Context, allowPrompt: boolean = true) { this.context = context; this.allowPrompt = allowPrompt; this.memos = new MemoStore(context.filesDir) }

  private ensureActive(active: () => boolean): void { if (!active()) throw new Error('操作已取消，未继续修改系统数据。') }

  private async permission(write: boolean, active: () => boolean): Promise<void> {
    const permissions: Permissions[] = write ? ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'] : ['ohos.permission.READ_CALENDAR']
    const manager = abilityAccessCtrl.createAtManager()
    if (!this.allowPrompt) {
      if (permissions.some((permission: Permissions) => manager.checkAccessTokenSync(this.context.applicationInfo.accessTokenId, permission) !== 0)) throw new Error('日历尚未授权，请先在日历页面允许访问。')
      this.ensureActive(active); return
    }
    const result = await manager.requestPermissionsFromUser(this.context as common.UIAbilityContext, permissions)
    this.ensureActive(active)
    if (result.authResults.length !== permissions.length || result.authResults.some((value: number) => value !== 0)) {
      throw new Error('日历权限未开启。请在系统设置中允许访问日历后重试。')
    }
  }

  private calendarManager(): calendarManager.CalendarManager { return calendarManager.getCalendarManager(this.context) }

  private repeating(event: calendarManager.Event): boolean {
    const frequency = event.recurrenceRule?.recurrenceFrequency
    return typeof frequency === 'number' && frequency >= 0 && frequency <= 3
  }

  private eventEntry(calendar: calendarManager.Calendar, event: calendarManager.Event): ScheduleEntry {
    const start = event.instanceStartTime === undefined ? event.startTime : event.instanceStartTime
    const end = event.instanceEndTime === undefined ? event.endTime : event.instanceEndTime
    return { id: `${calendar.id}:${event.id}:${start}`, kind: 'event', title: event.title || '未命名日程', calendarId: calendar.id, eventId: event.id,
      start: new Date(start).toISOString(), end: new Date(end).toISOString(), reminderMinutes: event.reminderTime || [],
      detail: `${ScheduleService.localLabel(start)} → ${ScheduleService.localLabel(end)}${event.isAllDay ? ' · 全天' : ''}` +
        `${event.location?.location ? `\n地点：${event.location.location}` : ''}${event.description ? `\n${event.description.slice(0, 1000)}` : ''}` +
        `\n提醒：${event.reminderTime?.length ? event.reminderTime.map((minute: number) => minute === 0 ? '准时' : `提前${minute}分钟`).join('、') : '无'}${this.repeating(event) ? ' · 重复日程' : ''}` }
  }

  private async query(args: ScheduleArgs, active: () => boolean): Promise<ScheduleResult> {
    await this.permission(false, active)
    const calendars = await this.calendarManager().getAllCalendars()
    const entries: ScheduleEntry[] = []
    let failed = 0
    for (const calendar of calendars) {
      this.ensureActive(active)
      try {
        // Instance queries omit reminderTime and recurrenceRule unless requested.
        const events = await calendar.queryEventInstances(ScheduleService.instant(args.start!), ScheduleService.instant(args.end!), undefined,
          ['id', 'title', 'startTime', 'endTime', 'instanceStartTime', 'instanceEndTime', 'isAllDay', 'description', 'location', 'reminderTime', 'recurrenceRule'])
        events.forEach((event: calendarManager.Event) => entries.push(this.eventEntry(calendar, event)))
      } catch (_error) { failed++ }
    }
    this.ensureActive(active)
    entries.sort((a: ScheduleEntry, b: ScheduleEntry) => Date.parse(a.start!) - Date.parse(b.start!))
    return { ok: failed < calendars.length || calendars.length === 0, entries: entries.slice(0, 100), total: entries.length,
      partial: failed > 0 || entries.length > 100,
      message: `已查询系统允许访问的日历，找到${entries.length}项，最多显示100项。` +
        (failed ? `${failed}个日历读取失败，不能据此认定没有冲突。` : '其他应用私有日历可能不在授权范围内。') }
  }

  private async calendarWrite(name: string, args: ScheduleArgs, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<ScheduleResult> {
    await this.permission(true, active)
    const manager = this.calendarManager()
    const calendar = name === 'create_calendar_event' ? await manager.getCalendar()
      : (await manager.getAllCalendars()).find((item: calendarManager.Calendar) => item.id === args.calendarId)
    if (calendar === undefined) throw new Error('该日历已不可访问，请重新查询。')
    this.ensureActive(active)
    let event: calendarManager.Event
    if (name === 'create_calendar_event') {
      event = { type: calendarManager.EventType.NORMAL, title: args.title!.trim(), startTime: ScheduleService.instant(args.start!),
        endTime: ScheduleService.instant(args.end!), description: args.description || '', isAllDay: args.allDay === true,
        reminderTime: args.reminderMinutes || [] }
      if (args.location !== undefined) event.location = { location: args.location }
      const duplicates = await calendar.getEvents(calendarManager.EventFilter.filterByTime(event.startTime, event.endTime))
      const duplicate = duplicates.find((item: calendarManager.Event) => item.title === event.title && item.startTime === event.startTime && item.endTime === event.endTime)
      if (duplicate !== undefined) return { ok: true, status: 'already_exists', message: '系统日历已有相同标题和起止时间的日程，未重复创建。', entries: [this.eventEntry(calendar, duplicate)] }
    } else {
      const events = await calendar.getEvents(calendarManager.EventFilter.filterById([args.eventId!]),
        ['id', 'type', 'title', 'startTime', 'endTime', 'isAllDay', 'description', 'timeZone', 'location', 'service', 'attendee', 'reminderTime', 'identifier', 'isLunar', 'recurrenceRule'])
      const existing = events.find((item: calendarManager.Event) => item.id === args.eventId)
      if (existing === undefined) throw new Error('该日程已不存在，请重新查询。')
      if (this.repeating(existing)) throw new Error('这是重复日程，请在系统日历选择修改或删除单次/整个系列。')
      event = JSON.parse(JSON.stringify(existing)) as calendarManager.Event
      event.recurrenceRule = undefined
      if (name === 'update_calendar_event') {
        if (args.title !== undefined) event.title = args.title.trim()
        if (args.start !== undefined) event.startTime = ScheduleService.instant(args.start)
        if (args.end !== undefined) event.endTime = ScheduleService.instant(args.end)
        if (args.description !== undefined) event.description = args.description
        if (args.location !== undefined) event.location = { location: args.location }
        if (args.reminderMinutes !== undefined) event.reminderTime = args.reminderMinutes
      }
    }
    if (event.endTime <= event.startTime) throw new Error('修改后的结束时间必须晚于开始时间。')
    const entry = this.eventEntry(calendar, event)
    const verb = name === 'delete_calendar_event' ? '删除' : name === 'update_calendar_event' ? '修改' : '创建'
    this.ensureActive(active)
    if (!await confirm(`${verb}系统日程`, `${entry.title}\n${entry.detail}`)) return { ok: false, status: 'cancelled', message: '你取消了本次日历操作，没有写入。' }
    this.ensureActive(active)
    if (name === 'delete_calendar_event') {
      await calendar.deleteEvent(args.eventId!)
      return { ok: true, message: `已从系统日历删除「${entry.title}」。`, entries: [entry] }
    }
    if (name === 'create_calendar_event') event.id = await calendar.addEvent(event)
    else await calendar.updateEvent(event)
    return { ok: true, message: `已${verb}系统日历日程。提醒是否响铃还取决于系统日历通知和设备设置。`, entries: [this.eventEntry(calendar, event)] }
  }

  private reminderEntry(info: reminderAgentManager.ReminderInfo): ScheduleEntry {
    const reminder = info.reminderReq
    let detail = reminder.content || ''
    if (reminder.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM) {
      const alarm = reminder as reminderAgentManager.ReminderRequestAlarm
      detail += `\n${alarm.hour.toString().padStart(2, '0')}:${alarm.minute.toString().padStart(2, '0')} · ${alarm.daysOfWeek?.length ? '每周' + alarm.daysOfWeek.join('、') : '下次单次'}（设备本地时间）`
    } else if (reminder.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      const date = (reminder as reminderAgentManager.ReminderRequestCalendar).dateTime
      detail += `\n${date.year}-${date.month}-${date.day} ${date.hour}:${date.minute}（设备本地时间）`
    } else detail += `\n倒计时 ${(reminder as reminderAgentManager.ReminderRequestTimer).triggerTimeInSeconds} 秒`
    return { id: `reminder-${info.reminderId}`, kind: 'reminder', title: reminder.title || '系统提醒', detail: detail.trim(), reminderId: info.reminderId }
  }

  private async reminders(name: string, args: ScheduleArgs, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<ScheduleResult> {
    if (name === 'list_system_reminders' || name === 'cancel_system_reminder') {
      const reminders = await reminderAgentManager.getAllValidReminders()
      this.ensureActive(active)
      if (name === 'list_system_reminders') return { ok: true, message: '仅包含 CampusPilot 发布的有效系统代理提醒，不含系统时钟或其他应用闹钟。', entries: reminders.map((item) => this.reminderEntry(item)) }
      const target = reminders.find((item) => item.reminderId === args.reminderId)
      if (target === undefined) throw new Error('提醒已失效或不属于本应用，请刷新列表。')
      const entry = this.reminderEntry(target)
      if (!await confirm('取消系统提醒', `${entry.title}\n${entry.detail}`)) return { ok: false, status: 'cancelled', message: '已保留该提醒。' }
      this.ensureActive(active)
      await reminderAgentManager.cancelReminder(args.reminderId!)
      return { ok: true, message: '已取消该系统代理提醒。', entries: [entry] }
    }
    let request: reminderAgentManager.ReminderRequest
    if (args.kind === 'alarm') {
      const alarm: reminderAgentManager.ReminderRequestAlarm = { reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
        hour: args.hour!, minute: args.minute!, daysOfWeek: args.weekdays || [] }
      request = alarm
    } else if (args.kind === 'timer') {
      const timer: reminderAgentManager.ReminderRequestTimer = { reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER, triggerTimeInSeconds: args.seconds! }
      request = timer
    } else {
      const date = new Date(ScheduleService.instant(args.at!))
      const dated: reminderAgentManager.ReminderRequestCalendar = { reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(), hour: date.getHours(), minute: date.getMinutes() } }
      request = dated
    }
    request.title = args.title!.trim(); request.content = args.content || args.title
    request.ringDuration = 60; request.snoozeTimes = 0
    request.slotType = notificationManager.SlotType.SOCIAL_COMMUNICATION
    request.wantAgent = { pkgName: this.context.applicationInfo.name, abilityName: 'EntryAbility' }
    const preview = this.reminderEntry({ reminderId: -1, reminderReq: request })
    if (!await confirm('设置系统代理提醒', `${preview.title}\n${preview.detail}\n由系统代为提醒，不会出现在时钟应用的闹钟列表。`)) return { ok: false, status: 'cancelled', message: '没有设置提醒。' }
    this.ensureActive(active)
    if (!await notificationManager.isNotificationEnabled()) {
      await notificationManager.requestEnableNotification(this.context as common.UIAbilityContext)
      this.ensureActive(active)
      if (!await notificationManager.isNotificationEnabled()) throw new Error('通知未授权，没有设置提醒。')
    }
    this.ensureActive(active)
    if (args.kind === 'calendar' && ScheduleService.instant(args.at!) <= Date.now()) throw new Error('提醒时间已过去，请选择新的时间。')
    await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
    this.ensureActive(active)
    try {
      const id = await reminderAgentManager.publishReminder(request)
      return { ok: true, message: '系统已接受代理提醒。实际铃声和显示受通知、静音/勿扰和设备设置影响。', entries: [this.reminderEntry({ reminderId: id, reminderReq: request })] }
    } catch (error) {
      const code = (error as NativeScheduleError).code
      let count: number | undefined = undefined
      if (code === 1700002) {
        try { count = (await reminderAgentManager.getAllValidReminders()).length } catch (_error) {}
      }
      const reason = code === 1700001 ? '系统通知未开启。' : code === 1700002 ?
        `系统返回提醒数量已达上限${count === undefined ? '' : `（本应用有效提醒${count}项）`}。未开通代理提醒使用权益时，上限也可能为0；不能据此认定是其他应用占满。需在AppGallery Connect申请并启用代理提醒能力，获批后重新生成Profile并使用对应签名。`
        : code === 201 ? '代理提醒权限或设备权益未开放。' : code === 401 ? '系统不接受该提醒参数。' : '请检查设备是否支持并开放代理提醒能力。'
      return { ok: false, status: code === 1700002 ? 'reminder_restricted' : 'reminder_failed',
        message: `系统未接受代理提醒${code === undefined ? '' : `（${code}）`}：${reason}本次没有设置成功。可另行确认改用系统日历提醒；创建后在“定时任务 → 日历 / 提醒”查看。` }
    }
  }

  private memoEntry(memo: LocalMemo): ScheduleEntry {
    return { id: memo.id, kind: 'memo', title: memo.title, content: memo.content, detail: `${memo.content}\n更新：${ScheduleService.localLabel(memo.updatedAt)}` }
  }

  private async memo(args: ScheduleArgs, active: () => boolean, confirm: (title: string, detail: string) => Promise<boolean>): Promise<ScheduleResult> {
    if (args.action === 'list') return { ok: true, status: 'preview', message: '本应用的本地备忘录，跨会话保存；列表显示正文预览，可查看完整内容。不包含系统备忘录私有内容。',
      entries: this.memos.list().map((memo: LocalMemo): ScheduleEntry => ({ id: memo.id, kind: 'memo', title: memo.title.slice(0, 120),
        detail: `${memo.content.slice(0, 400)}${memo.content.length > 400 ? '…' : ''}\n更新：${ScheduleService.localLabel(memo.updatedAt)}` })) }
    if (args.action === 'read') return { ok: true, message: '已读取本地备忘录全文。', entries: [this.memoEntry(this.memos.get(args.id!))] }
    if (args.action === 'save') {
      if (args.id) this.memos.get(args.id)
      if (!await confirm(args.id ? '修改本地备忘录' : '保存本地备忘录', `${args.title}\n${args.content}`)) return { ok: false, status: 'cancelled', message: '没有保存备忘录。' }
      this.ensureActive(active)
      const memo = this.memos.save(args.title!, args.content!, args.id)
      return { ok: true, message: '已保存到本应用本地备忘录，可继续设置提醒或通过系统分享发送到备忘录应用。', entries: [this.memoEntry(memo)] }
    }
    const memo = this.memos.get(args.id!)
    if (args.action === 'delete') {
      if (!await confirm('删除本地备忘录', `${memo.title}\n${memo.content}`)) return { ok: false, status: 'cancelled', message: '已保留备忘录。' }
      this.ensureActive(active); this.memos.delete(memo.id)
      return { ok: true, message: '已删除本地备忘录。' }
    }
    this.ensureActive(active)
    const data = new systemShare.SharedData({ utd: 'general.plain-text', content: `${memo.title}\n\n${memo.content}`, title: memo.title })
    const controller = new systemShare.ShareController(data)
    await controller.show(this.context as common.UIAbilityContext, { anchor: { windowOffset: { x: 80, y: 100 }, size: { width: 48, height: 48 } } })
    return { ok: true, status: 'share_opened', message: '已打开系统分享入口，请选择备忘录等目标应用并完成保存。未核实目标应用是否保存成功。' }
  }

  async perform(name: string, args: ScheduleArgs, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<ScheduleResult> {
    this.ensureActive(active)
    if (name === 'get_system_time') {
      const date = new Date()
      return { ok: true, message: '当前设备时间（模拟器中为模拟器时间）。', timestamp: date.getTime(), localTime: date.toString(),
        timeZone: systemDateTime.getTimezoneSync(), utcOffsetMinutes: -date.getTimezoneOffset() }
    }
    if (name === 'manage_memo') return this.memo(args, active, confirm)
    if (name === 'query_calendar_events') return this.query(args, active)
    if (name.endsWith('_calendar_event')) return this.calendarWrite(name, args, active, confirm)
    return this.reminders(name, args, active, confirm)
  }
}
