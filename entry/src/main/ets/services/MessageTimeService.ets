import { AgentMessage } from '../models/AppModels'

export class MessageTimeService {
  static valid(value?: number): boolean {
    return typeof value === 'number' && Number.isFinite(value) && value > 0 && Number.isFinite(new Date(value).getTime())
  }

  static timestamp(message: AgentMessage): number | undefined {
    if (message.role === 'user') return MessageTimeService.valid(message.createdAt) ? message.createdAt : undefined
    if (MessageTimeService.valid(message.completedAt)) return message.completedAt
    if (MessageTimeService.valid(message.createdAt)) return message.createdAt
    // Older Agent replies may contain a real saved execution timestamp. Do not
    // substitute a conversation's date for an unknown individual message date.
    if (message.role === 'agent' && MessageTimeService.valid(message.thinkingStartedAt) &&
      MessageTimeService.valid(message.thinkingLastActiveAt)) return message.thinkingLastActiveAt
    return undefined
  }

  static completed(message: AgentMessage, status: string, now: number = Date.now()): number | undefined {
    if (MessageTimeService.valid(message.completedAt)) return message.completedAt
    if (['complete', 'error', 'stopped'].includes(status) && MessageTimeService.valid(message.createdAt) && MessageTimeService.valid(now)) return now
    return undefined
  }

  static full(timestamp?: number): string {
    if (!MessageTimeService.valid(timestamp)) return '时间未记录'
    const date = new Date(timestamp!)
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日${MessageTimeService.clock(date)}`
  }

  static format(timestamp?: number, now: number = Date.now()): string {
    if (!MessageTimeService.valid(timestamp) || !MessageTimeService.valid(now)) return '时间未记录'
    const date = new Date(timestamp!)
    const today = new Date(now)
    if (date.getFullYear() !== today.getFullYear()) return MessageTimeService.full(timestamp)
    const clock = MessageTimeService.clock(date)
    if (date.getMonth() === today.getMonth() && date.getDate() === today.getDate()) return clock
    const weekStart = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    weekStart.setDate(weekStart.getDate() - (weekStart.getDay() + 6) % 7)
    if (timestamp! >= weekStart.getTime() && timestamp! < now) return `星期${'日一二三四五六'.charAt(date.getDay())}${clock}`
    return `${date.getMonth() + 1}月${date.getDate()}日${clock}`
  }

  static label(message: AgentMessage, now: number = Date.now()): string {
    if (message.role === 'agent' && (message.status === 'loading' || message.status === 'streaming')) return '生成中'
    return MessageTimeService.format(MessageTimeService.timestamp(message), now)
  }

  private static clock(date: Date): string {
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`
  }
}
