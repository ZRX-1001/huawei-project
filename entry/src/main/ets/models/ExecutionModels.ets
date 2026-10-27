export interface ExecutionTarget {
  kind: string
  label: string
  action: string
  id?: string
}

export interface ExecutionRecord {
  id: string
  kind: string
  name: string
  title: string
  status: string
  startedAt: number
  finishedAt?: number
  input: string
  detail: string
  targets: ExecutionTarget[]
}
