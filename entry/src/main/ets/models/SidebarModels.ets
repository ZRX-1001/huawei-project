import { FeatureDefinition } from './AppModels'
import { SessionSummary } from '../services/SessionService'

export interface SidebarPreferences {
  workspaceSectionExpanded: boolean
  recentSectionExpanded: boolean
  expandedWorkspaceIds: string[]
  expandedHistoryIds: string[]
  showAllRecent: boolean
  panelVisible: boolean
  leftWidth?: number
  rightWidth?: number
}

export interface SidebarWorkspaceGroup {
  feature: FeatureDefinition
  sessions: SessionSummary[]
  totalCount: number
  expanded: boolean
  showAll: boolean
}

export interface SidebarView {
  workspaces: SidebarWorkspaceGroup[]
  recent: SessionSummary[]
  recentCount: number
}
