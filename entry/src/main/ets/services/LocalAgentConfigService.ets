import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { AgentApiSettings } from '../config/ApiConfig'
import { preferences } from '@kit.ArkData'

export class LocalAgentConfigService {
  static saveRuntime(context: common.Context, settings: AgentApiSettings): void {
    const store = preferences.getPreferencesSync(context, { name: 'agent_runtime' })
    store.putSync('settings', JSON.stringify(settings)); store.flushSync()
  }
  static async load(context: common.Context): Promise<AgentApiSettings | undefined> {
    try {
      const saved = preferences.getPreferencesSync(context, { name: 'agent_runtime' }).getSync('settings', '') as string
      if (saved) {
        const settings = JSON.parse(saved) as AgentApiSettings
        if (typeof settings.baseUrl === 'string' && typeof settings.model === 'string' && typeof settings.apiKey === 'string') return settings
      }
    } catch (_error) {}
    try {
      const rawFile: Uint8Array = await context.resourceManager.getRawFileContent('local_api.json')
      const text = util.TextDecoder.create().decodeToString(rawFile)
      const settings = JSON.parse(text) as AgentApiSettings
      if (typeof settings.baseUrl !== 'string' || typeof settings.model !== 'string' || typeof settings.apiKey !== 'string') {
        return undefined
      }
      if (settings.baseUrl.trim().length === 0 || settings.model.trim().length === 0) return undefined
      return settings
    } catch (error) {
      return undefined
    }
  }
}
