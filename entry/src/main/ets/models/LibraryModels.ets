import { KnowledgeChunk } from './RagModels'

export interface LibraryDocument {
  id: string
  title: string
  course: string
  kind: string
  origin: string
  path: string
  mimeType: string
  size: number
  text: string
  truncated: boolean
  indexed: boolean
  createdAt: number
  chunks?: KnowledgeChunk[]
}

export interface LibraryArchive {
  version: number
  documents: LibraryDocument[]
  deletedIds: string[]
  disabledSources: string[]
}
