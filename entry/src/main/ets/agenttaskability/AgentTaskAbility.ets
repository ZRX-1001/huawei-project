import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit'
import { AgentTaskRuntime } from '../services/AgentTaskRuntime'

export default class AgentTaskAbility extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    AgentTaskRuntime.drain(this.context).finally(() => {
      try { workScheduler.stopWork(work, false) } catch (_error) {}
    }).catch(() => {})
  }
  onWorkStop(_work: workScheduler.WorkInfo): void { AgentTaskRuntime.cancel() }
}
