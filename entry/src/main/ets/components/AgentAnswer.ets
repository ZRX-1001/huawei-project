import { UiTheme } from '../config/UiTheme'
import { AgentMessage } from '../models/AppModels'
import { MarkdownParser } from '../services/MarkdownParser'
import { MarkdownContent } from './MarkdownContent'

@Component
export struct AgentAnswer {
  @Prop message: AgentMessage = { role: 'agent', content: '', meta: '' }
  @Prop expanded: boolean = false
  onToggle: () => void = () => {}
  @State elapsedSeconds: number = 0
  private timer: number = -1

  private generating(): boolean { return this.message.status === 'loading' || this.message.status === 'streaming' }

  aboutToAppear(): void {
    this.tick()
    if (this.generating()) this.timer = setInterval(() => this.tick(), 1000)
  }

  aboutToDisappear(): void { if (this.timer >= 0) clearInterval(this.timer) }

  private tick(): void {
    this.elapsedSeconds = Math.max(0, Math.floor((this.message.thinkingDurationMs !== undefined
      ? this.message.thinkingDurationMs : Date.now() - (this.message.thinkingStartedAt || Date.now())) / 1000))
  }

  private label(): string {
    if (this.message.status === 'error') return '生成未完成'
    if (this.message.status === 'stopped') return '已停止'
    if (!this.generating()) return '思路摘要'
    if (this.message.phase === 'retrieving') return '正在检索资料'
    if (this.message.phase === 'connecting') return '正在连接模型'
    if (this.message.phase === 'updating') return '正在操作工作区'
    if (this.message.phase === 'analyzing' || MarkdownParser.answer(this.message.content).summarizing) return '正在思考'
    return '正在生成回答'
  }

  build() {
    Column({ space: 12 }) {
      if (this.message.thinkingStartedAt !== undefined || MarkdownParser.answer(this.message.content).summary.length > 0) {
        Column({ space: 8 }) {
          Row({ space: 7 }) {
            if (this.generating()) { LoadingProgress().width(15).height(15).color('#777777') }
            else { Text(this.message.status === 'error' ? '!' : this.message.status === 'stopped' ? '◌' : '✓').fontSize(13).fontColor('#777777') }
            Text(this.label()).fontSize(12).fontColor(UiTheme.secondary)
            if (this.message.thinkingStartedAt !== undefined) { Text(`用时 ${this.elapsedSeconds} 秒`).fontSize(11).fontColor('#999999') }
            Blank()
            Text(this.expanded ? '⌃' : '⌄').fontSize(13).fontColor('#888888')
          }.width('100%').height(34).accessibilityText(`${this.label()}，${this.expanded ? '收起' : '展开'}思路摘要`)
            .hoverEffect(HoverEffect.Highlight)
            .stateStyles({ normal: { .opacity(1) }, pressed: { .opacity(0.65) } })
            .animation({ duration: 140, curve: Curve.EaseOut })
            .onClick(() => this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseInOut }, () => this.onToggle()))
          if (this.expanded) {
            if (MarkdownParser.answer(this.message.content).summary.length > 0) {
              MarkdownContent({ content: MarkdownParser.answer(this.message.content).summary })
            } else {
              Text(this.generating() ? '模型正在处理请求，返回思路摘要后将在这里显示。' : '本次回答未提供思路摘要。')
                .fontSize(12).fontColor('#888888').lineHeight(20)
            }
          }
        }.width('100%').padding({ left: 10, right: 10, bottom: this.expanded ? 10 : 0 })
          .backgroundColor(UiTheme.raised).borderRadius(8)
      }
      if (this.message.status !== 'loading' && MarkdownParser.answer(this.message.content).body.trim().length > 0) {
        MarkdownContent({ content: MarkdownParser.answer(this.message.content).body })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
