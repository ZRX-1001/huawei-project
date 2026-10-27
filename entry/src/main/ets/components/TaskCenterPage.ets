import { UiTheme } from '../config/UiTheme'
import { AgentTaskPage } from './AgentTaskPage'
import { SystemSchedulePanel } from './SystemSchedulePanel'

@Component
export struct TaskCenterPage {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop initialTab: string = 'agent'
  @State tab: string = 'agent'
  aboutToAppear(): void { this.tab = this.initialTab }
  @Builder
  Tab(label: string, id: string) {
    Button(label).fontSize(13 * this.fontScale).height(34 * this.fontScale).borderRadius(8 * this.fontScale)
      .backgroundColor(this.tab === id ? UiTheme.primary : UiTheme.raised).fontColor(this.tab === id ? UiTheme.surface : UiTheme.text)
      .id(`task-center-${id}`).onClick(() => this.tab = id)
  }
  build() {
    Column() {
      Column({ space: 12 * this.fontScale }) {
        Text('定时任务').fontSize(25 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
        Row({ space: 9 * this.fontScale }) { this.Tab('Agent任务', 'agent'); this.Tab('日历', 'calendar'); this.Tab('提醒', 'reminders'); this.Tab('备忘录', 'memos') }.width('100%')
        Text(this.tab === 'agent' ? '这里是Agent到期执行的任务；已安排的日程和响铃提醒请在“日历 / 提醒”查看。'
          : this.tab === 'reminders' ? '同时显示本应用代理提醒与日历提醒，打开页面自动读取。' : this.tab === 'calendar' ? '显示系统授权范围内的日程，包含对话中创建的日历提醒。' : '本机保存的备忘录，可编辑并通过系统分享。')
          .fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).width('100%')
      }.width('100%').padding(22 * this.fontScale).border({ width: { bottom: 1 }, color: UiTheme.border })
      if (this.tab === 'agent') { AgentTaskPage().layoutWeight(1) }
      else {
        ForEach([this.tab], (tab: string) => { SystemSchedulePanel({ embedded: true, initialTab: tab }).layoutWeight(1) }, (tab: string) => tab)
      }
    }.width('100%').height('100%').backgroundColor(UiTheme.background).id('task-center-page')
  }
}
