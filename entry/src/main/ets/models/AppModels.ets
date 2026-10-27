import { SourceCitation } from './RagModels'
import { ChatAttachment } from './AttachmentModels'
import { ExecutionRecord } from './ExecutionModels'

export interface AgentMessage {
  role: string
  content: string
  meta: string
  sources?: SourceCitation[]
  status?: string
  renderRevision?: number
  thinkingStartedAt?: number
  thinkingDurationMs?: number
  phase?: string
  attachments?: ChatAttachment[]
  executionId?: string
  executions?: ExecutionRecord[]
  thinkingLastActiveAt?: number
}

export interface FeatureDefinition {
  id: string
  icon: string
  name: string
  description: string
  category: string
  prompt?: string
}

export interface ActionItem {
  title: string
  subtitle: string
  status: string
}
