import { UiTheme } from '../config/UiTheme'
import { MarkdownParser, MarkdownBlock, MarkdownRun, MarkdownRow } from '../services/MarkdownParser'

@Component
struct MarkdownInline {
  @Prop text: string = ''
  @Prop textSize: number = 15
  @Prop strong: boolean = false
  @Prop color: string = UiTheme.text

  build() {
    Text() {
      ForEach(MarkdownParser.inline(this.text), (run: MarkdownRun) => {
        Span(run.text).fontSize(this.textSize).fontWeight(run.bold || this.strong ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(run.code ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(run.link ? UiTheme.primary : run.code ? '#666666' : this.color)
          .decoration({ type: run.strike ? TextDecorationType.LineThrough : run.link ? TextDecorationType.Underline : TextDecorationType.None })
      }, (run: MarkdownRun, index: number) => `${index}-${JSON.stringify(run)}`)
    }.fontSize(this.textSize).lineHeight(this.textSize * 1.65).copyOption(CopyOptions.InApp).width('100%')
      .textAlign(TextAlign.Start)
  }
}

@Component
export struct MarkdownContent {
  @Prop content: string = ''

  build() {
    Column({ space: 10 }) {
      ForEach(MarkdownParser.parse(this.content), (block: MarkdownBlock) => {
        if (block.kind === 'heading') {
          MarkdownInline({ text: block.text, textSize: block.level === 1 ? 23 : block.level === 2 ? 20 : block.level === 3 ? 17 : 15, strong: true })
            .margin({ top: 7, bottom: 2 })
        } else if (block.kind === 'divider') {
          Divider().color(UiTheme.border).strokeWidth(1).margin({ top: 5, bottom: 5 })
        } else if (block.kind === 'list') {
          Row({ space: 8 }) {
            Text(block.prefix).fontSize(15).fontColor(UiTheme.primary).lineHeight(25).constraintSize({ minWidth: 16 })
            MarkdownInline({ text: block.text }).layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top).padding({ left: block.level * 14 })
        } else if (block.kind === 'code') {
          Column({ space: 6 }) {
            if (block.language.length > 0) { Text(block.language).fontSize(11).fontColor('#777777') }
            Scroll() {
              Text(block.text || ' ').fontSize(13).fontFamily('monospace').fontColor('#404040')
                .lineHeight(21).copyOption(CopyOptions.InApp).constraintSize({ minWidth: '100%' })
            }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Auto)
          }.alignItems(HorizontalAlign.Start).width('100%').padding(12).backgroundColor(UiTheme.raised).borderRadius(8)
        } else if (block.kind === 'quote') {
          Row({ space: 10 }) {
            MarkdownInline({ text: block.text, color: '#777777' })
          }.width('100%').padding({ left: 12, top: 6, bottom: 6, right: 8 })
            .border({ width: { left: 3 }, color: '#AAAAAA' }).backgroundColor(UiTheme.raised)
        } else if (block.kind === 'table') {
          Scroll() {
            Column() {
              ForEach(block.rows, (row: MarkdownRow, rowIndex: number) => {
                Row() {
                  ForEach(row.cells, (cell: string) => {
                    MarkdownInline({ text: cell, textSize: 13, strong: rowIndex === 0 }).width(156).padding(10)
                  }, (cell: string, index: number) => `${index}-${cell}`)
                }.alignItems(VerticalAlign.Top).width(block.rows[0].cells.length * 156)
                  .backgroundColor(rowIndex === 0 ? UiTheme.raised : rowIndex % 2 === 0 ? UiTheme.raised : UiTheme.surface)
                  .border({ width: { bottom: 1 }, color: UiTheme.border })
              }, (row: MarkdownRow, index: number) => `${index}-${JSON.stringify(row)}`)
            }.border({ width: 1, color: UiTheme.border }).borderRadius(6)
          }.scrollable(ScrollDirection.Horizontal).width('100%').scrollBar(BarState.Auto)
        } else {
          MarkdownInline({ text: block.text })
        }
      }, (block: MarkdownBlock, index: number) => `${index}-${JSON.stringify(block)}`)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
