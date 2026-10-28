import { UiTheme } from '../config/UiTheme'

@Component
export struct ChatSendButton {
  @StorageLink('campusFontScale') fontScale: number = 0.9
  onSend: () => void = () => {}

  build() {
    Button({ type: ButtonType.Circle }) {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.ic_chat_send')).width(16 * this.fontScale).height(16 * this.fontScale)
          .objectFit(ImageFit.Contain).id('chat-send-icon')
      }.width('100%').height('100%')
    }.width(32 * this.fontScale).height(32 * this.fontScale).padding(0).backgroundColor(UiTheme.primary)
      .id('chat-send').accessibilityText('发送消息').hoverEffect(HoverEffect.Highlight).onClick(() => this.onSend())
  }
}
