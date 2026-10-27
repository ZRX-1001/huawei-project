export interface InteractionControl {
  id: string
  label: string
  kind: string
  initialValue: string
  group?: string
}

export interface InteractionToken {
  kind: string
  text: string
  control?: InteractionControl
}

export interface InteractionValue {
  id: string
  label: string
  kind: string
  value: string
}

export interface InteractionRecord {
  id: string
  source: string
  title: string
  values: InteractionValue[]
  updatedAt: number
  resetAt?: number
  contentSignature?: string
}

export interface InteractionContextValue extends InteractionValue { active?: boolean }
export interface InteractionContextRecord extends InteractionRecord {
  versionStatus: string
  values: InteractionContextValue[]
}

export interface InteractionChange {
  controlId: string
  value: string
  reset?: boolean
  sessionId?: string
  documentId?: string
  submit?: boolean
}

export interface InteractionReviewField {
  id: string
  label: string
  kind: string
  value: string
  userEdited: boolean
  empty: boolean
  group?: string
}

export interface InteractionLayout {
  lists: Record<string, InteractionControl>
  cells: Record<string, InteractionControl>
  controls: InteractionControl[]
  hasTables: boolean
  inline?: Record<string, InteractionToken[]>
}
