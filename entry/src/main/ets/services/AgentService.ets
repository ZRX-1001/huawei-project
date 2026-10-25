import { AgentMessage, FeatureDefinition } from '../models/AppModels'
import { WorkspaceConfig } from '../config/WorkspaceConfig'

export class AgentService {
  static greeting(featureId: string, features: FeatureDefinition[] = []): AgentMessage[] {
    const profile = WorkspaceConfig.profile(featureId, features)
    return [{ role: 'agent', content: profile.greeting, meta: `${profile.name} · ${profile.role}` }]
  }

}
