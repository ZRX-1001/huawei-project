export interface AgentTaskRun {
  id: string
  startedAt: number
  finishedAt: number
  status: string
  output: string
}
export interface AgentTask extends AgentTaskDraft {
  id: string
  title: string
  prompt: string
  mode: string
  firstRunAt: number
  intervalMinutes: number
  weekdays: number[]
  enabled: boolean
  nextRunAt: number
  updatedAt: number
  runId: string
  runningSince: number
  runs: AgentTaskRun[]
}
export interface AgentTaskDraft {
  title: string
  prompt: string
  mode: string
  firstRunAt: number
  intervalMinutes: number
  weekdays: number[]
}
export interface AgentTaskArchive { version: number; tasks: AgentTask[] }
