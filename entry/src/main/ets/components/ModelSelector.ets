import { AgentProfileSummary } from '../config/ApiConfig'
import { UiTheme } from '../config/UiTheme'
import { ApiProfileList } from './ApiProfileList'

@Component
export struct ModelSelector {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  @Prop profiles: AgentProfileSummary[] = []
  @Prop activeId: string = ''
  @Prop activeModel: string = ''
  @Prop loading: boolean = false
  @Prop busy: boolean = false
  @Prop viewportWidth: number = 360
  @Prop viewportHeight: number = 640
  onSelect: (id: string) => void = () => {}
  onManage: () => void = () => {}
  @State visible: boolean = false

  private label(): string { return this.loading ? '读取模型…' : this.activeModel || (this.profiles.length ? '选择模型' : '配置模型') }

  @Builder
  Picker() {
    Column({ space: 9 * this.fontScale }) {
      Text(`选择模型 · ${this.profiles.length}`).fontSize(12 * this.fontScale).fontWeight(FontWeight.Medium).fontColor(UiTheme.text).width('100%')
      ApiProfileList({ profiles: this.profiles, activeId: this.activeId, selectedId: this.activeId, prefix: 'model-option',
        maxHeight: Math.min(240 * this.fontScale, this.viewportHeight * 0.4),
        onSelect: (id: string) => { this.visible = false; this.onSelect(id) } })
      Divider().color(UiTheme.border)
      Button('管理模型 API…').fontSize(12 * this.fontScale).height(34 * this.fontScale).width('100%').borderRadius(6 * this.fontScale)
        .backgroundColor(UiTheme.raised).fontColor(UiTheme.primary).id('model-picker-manage')
        .onClick(() => { this.visible = false; this.onManage() })
    }.width('100%').padding(12 * this.fontScale).backgroundColor(UiTheme.surface).id('model-picker')
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 5 * this.fontScale }) {
        Text(this.label()).fontSize(11 * this.fontScale).fontColor(UiTheme.secondary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text(this.profiles.length ? '⌄' : '＋').fontSize(10 * this.fontScale).fontColor(UiTheme.muted)
      }.width('100%')
    }.hoverEffect(HoverEffect.Highlight).width('100%').height(32 * this.fontScale)
      .padding({ left: 8 * this.fontScale, right: 8 * this.fontScale }).borderRadius(6 * this.fontScale).backgroundColor(Color.Transparent)
      .id('api-settings-open').accessibilityText(`当前模型：${this.activeModel || '尚未配置'}，切换或管理模型 API`)
      .enabled(!this.busy && !this.loading).onClick(() => { if (this.profiles.length) this.visible = !this.visible; else this.onManage() })
      .bindPopup(this.visible, { builder: this.Picker(), width: Math.min(320 * this.fontScale, this.viewportWidth - 24),
        placement: Placement.Top, enableArrow: false, popupColor: UiTheme.surface, autoCancel: true,
        onStateChange: (event: PopupStateChangeParam) => { this.visible = event.isVisible } })
  }
}
