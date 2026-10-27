import { util } from '@kit.ArkTS'
import { AgentTask, AgentTaskArchive, AgentTaskDraft, AgentTaskRun } from '../models/AgentTaskModels'
import { AgentTaskService } from './AgentTaskService'
import { LocalJsonStore } from './LocalJsonStore'

export class AgentTaskStore {
  private store: LocalJsonStore<AgentTaskArchive>
  constructor(filesDir: string) {
    this.store = new LocalJsonStore<AgentTaskArchive>(`${filesDir}/agent_tasks.json`,
      (): AgentTaskArchive => ({ version: 1, tasks: [] }), AgentTaskService.valid)
  }
  list(): AgentTask[] { return this.store.read().tasks.sort((a: AgentTask, b: AgentTask) => b.updatedAt - a.updatedAt) }
  save(draft: AgentTaskDraft, id?: string): void {
    AgentTaskService.validate(draft)
    if (draft.firstRunAt <= Date.now()) throw new Error('请选择未来的首次执行时间。')
    this.store.change((state: AgentTaskArchive): AgentTaskArchive => {
      const previous = state.tasks.find((task: AgentTask) => task.id === id)
      if (id && previous === undefined) throw new Error('任务已不存在。')
      if (previous?.runId) throw new Error('请先停止当前执行再编辑。')
      if (!previous && state.tasks.length >= 30) throw new Error('最多保存30个定时任务。')
      const task: AgentTask = { id: id || util.generateRandomUUID(), title: draft.title.trim(), prompt: draft.prompt.trim(), mode: draft.mode,
        firstRunAt: draft.firstRunAt, intervalMinutes: draft.intervalMinutes, weekdays: draft.weekdays, enabled: previous === undefined ? true : previous.enabled,
        nextRunAt: ['daily', 'weekly'].includes(draft.mode) ? AgentTaskService.next(draft, draft.firstRunAt - 1) : draft.firstRunAt,
        updatedAt: Date.now(), runId: '', runningSince: 0, runs: previous?.runs || [] }
      state.tasks = state.tasks.filter((item: AgentTask) => item.id !== id).concat(task)
      return state
    })
  }
  toggle(id: string): void {
    this.store.change((state: AgentTaskArchive): AgentTaskArchive => {
      const task = state.tasks.find((item: AgentTask) => item.id === id)
      if (task === undefined) throw new Error('任务不存在。')
      task.enabled = !task.enabled; task.updatedAt = Date.now()
      if (task.enabled && task.nextRunAt <= Date.now()) task.nextRunAt = task.mode === 'once' ? Date.now() + 1000 : AgentTaskService.next(task, Date.now())
      return state
    })
  }
  remove(id: string): void { this.store.change((state: AgentTaskArchive): AgentTaskArchive => { state.tasks = state.tasks.filter((task: AgentTask) => task.id !== id); return state }) }
  claim(id: string, manual: boolean = false): AgentTask | undefined {
    let claimed: AgentTask | undefined = undefined
    this.store.change((state: AgentTaskArchive): AgentTaskArchive => {
      const task = state.tasks.find((item: AgentTask) => item.id === id)
      if (task === undefined) return state
      if (task.runId && Date.now() - task.runningSince < 180000) return state
      if (task.runId) {
        task.runs = [{ id: task.runId, startedAt: task.runningSince, finishedAt: Date.now(), status: 'interrupted', output: '上次执行中断，未取得完整结果。' } as AgentTaskRun].concat(task.runs).slice(0, 5)
        task.runId = ''
      }
      if (!manual && (!task.enabled || task.nextRunAt > Date.now())) return state
      task.runId = util.generateRandomUUID(); task.runningSince = Date.now(); task.updatedAt = Date.now()
      if (!manual) {
        if (task.mode === 'once') task.enabled = false
        else task.nextRunAt = AgentTaskService.next(task, Date.now())
      }
      claimed = JSON.parse(JSON.stringify(task)) as AgentTask
      return state
    })
    return claimed
  }
  active(id: string, runId: string): boolean { return this.list().some((task: AgentTask) => task.id === id && task.runId === runId) }
  finish(task: AgentTask, status: string, output: string): void {
    this.store.change((state: AgentTaskArchive): AgentTaskArchive => {
      const current = state.tasks.find((item: AgentTask) => item.id === task.id && item.runId === task.runId)
      if (current === undefined) return state
      current.runs = [{ id: task.runId, startedAt: task.runningSince, finishedAt: Date.now(), status: status, output: output.slice(0, 16000) } as AgentTaskRun].concat(current.runs).slice(0, 5)
      current.runId = ''; current.runningSince = 0; current.updatedAt = Date.now()
      return state
    })
  }
}
