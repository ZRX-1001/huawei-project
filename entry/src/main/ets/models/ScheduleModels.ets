export interface ScheduleArgs {
  title?: string
  start?: string
  end?: string
  description?: string
  location?: string
  reminderMinutes?: number[]
  allDay?: boolean
  calendarId?: number
  eventId?: number
  kind?: string
  at?: string
  hour?: number
  minute?: number
  weekdays?: number[]
  seconds?: number
  content?: string
  reminderId?: number
  action?: string
  id?: string
}

export interface ScheduleEntry {
  id: string
  kind: string
  title: string
  detail: string
  calendarId?: number
  eventId?: number
  reminderId?: number
  start?: string
  end?: string
  content?: string
  reminderMinutes?: number[]
}

export interface ScheduleResult {
  ok: boolean
  message: string
  entries?: ScheduleEntry[]
  partial?: boolean
  total?: number
  timestamp?: number
  localTime?: string
  timeZone?: string
  utcOffsetMinutes?: number
  status?: string
}

export interface LocalMemo {
  id: string
  title: string
  content: string
  createdAt: number
  updatedAt: number
}

export interface SchedulePlatform {
  perform(name: string, args: ScheduleArgs, active: () => boolean,
    confirm: (title: string, detail: string) => Promise<boolean>): Promise<ScheduleResult>
}
