import { AgentTask, AgentTaskArchive, AgentTaskDraft, AgentTaskRun } from '../models/AgentTaskModels'
import { AgentToolDefinition } from '../models/WorkspaceModels'

export class AgentTaskService {
  static tools(): AgentToolDefinition[] {
    return JSON.parse(`[{"type":"function","function":{"name":"manage_agent_task","description":"管理用户要求Agent定时生成/整理内容的任务（不同于响铃提醒）。action=list/create/update/pause/resume/delete。先get_system_time确定设备日期；create必须明确标题、要执行的prompt、模式mode及带时区ISO时间firstRun。daily每天该时刻，weekly需weekdays（周一1至周日7），interval需intervalMinutes（至少15分钟）。任务仅能读取授权数据并生成结果，不能自动执行日历写入/付款/发消息等操作；后台由系统择机执行可能延迟，打开应用会补执行，不能保证后台准点。创建修改删除前应用会展示核对窗口。","parameters":{"type":"object","properties":{"action":{"type":"string","enum":["list","create","update","pause","resume","delete"]},"id":{"type":"string"},"title":{"type":"string"},"prompt":{"type":"string"},"mode":{"type":"string","enum":["once","daily","weekly","interval"]},"firstRun":{"type":"string"},"intervalMinutes":{"type":"number"},"weekdays":{"type":"array","items":{"type":"number"}}},"required":["action"],"additionalProperties":false}}}]`) as AgentToolDefinition[]
  }
  static validate(draft: AgentTaskDraft): void {
    if (!draft || typeof draft.title !== 'string' || !draft.title.trim() || draft.title.length > 120 ||
      typeof draft.prompt !== 'string' || !draft.prompt.trim() || draft.prompt.length > 4000) throw new Error('请填写任务名称和具体要求。')
    if (!['once', 'daily', 'weekly', 'interval'].includes(draft.mode) || !Number.isFinite(draft.firstRunAt) || !Number.isFinite(new Date(draft.firstRunAt).getTime()) ||
      !Number.isInteger(draft.intervalMinutes) || draft.intervalMinutes < 15 || draft.intervalMinutes > 10080 ||
      !Array.isArray(draft.weekdays) || draft.weekdays.some((day: number) => !Number.isInteger(day) || day < 1 || day > 7) ||
      (draft.mode === 'weekly' && draft.weekdays.length === 0)) throw new Error('执行时间或周期无效，间隔至少15分钟。')
  }
  static valid(value: AgentTaskArchive): boolean {
    if (!value || value.version !== 1 || !Array.isArray(value.tasks) || value.tasks.length > 30) return false
    try {
      return new Set(value.tasks.map((task: AgentTask) => task.id)).size === value.tasks.length && value.tasks.every((task: AgentTask) => {
        AgentTaskService.validate(task)
        return typeof task.id === 'string' && typeof task.enabled === 'boolean' && Number.isFinite(task.nextRunAt) &&
          typeof task.runId === 'string' && Number.isFinite(task.runningSince) && Array.isArray(task.runs) && task.runs.length <= 5 &&
          task.runs.every((run: AgentTaskRun) => typeof run.output === 'string' && run.output.length <= 16000 &&
            ['success', 'failed', 'interrupted'].includes(run.status) && Number.isFinite(run.startedAt) && Number.isFinite(run.finishedAt))
      })
    } catch (_error) { return false }
  }
  static next(task: AgentTaskDraft, now: number): number {
    if (task.mode === 'once') return task.firstRunAt
    if (task.mode === 'interval') return now + task.intervalMinutes * 60000
    const original = new Date(task.firstRunAt), next = new Date(now)
    next.setHours(original.getHours(), original.getMinutes(), 0, 0)
    for (let i = 0; i < 8; i++) {
      const day = next.getDay() || 7
      if (next.getTime() > now && (task.mode === 'daily' || task.weekdays.includes(day))) return next.getTime()
      next.setDate(next.getDate() + 1)
    }
    throw new Error('无法计算下一次执行时间。')
  }
  static describe(task: AgentTaskDraft): string {
    const time = new Date(task.firstRunAt)
    const clock = `${time.getHours().toString().padStart(2, '0')}:${time.getMinutes().toString().padStart(2, '0')}`
    return task.mode === 'once' ? '单次' : task.mode === 'daily' ? `每天 ${clock}` : task.mode === 'interval'
      ? `每${task.intervalMinutes}分钟` : `每周${task.weekdays.join('、')} ${clock}`
  }
}
