import { MarkdownParser } from './MarkdownParser'
import { InteractionChange, InteractionContextRecord, InteractionContextValue, InteractionControl, InteractionLayout, InteractionRecord, InteractionValue, InteractionToken } from '../models/InteractionModels'

// User feedback stays separate from generated Markdown and model-owned tasks.
export class InteractionService {
  static readonly maxValueLength: number = 1000
  static readonly maxRecords: number = 120
  static readonly maxEntries: number = 480
  static readonly maxSize: number = 48000

  private static plain(text: string): string {
    return MarkdownParser.inline(text).map((run) => run.text).join('').replace(/\s+/g, ' ').trim()
  }

  private static hash(text: string): string {
    let result = 2166136261
    for (let i = 0; i < text.length; i++) result = Math.imul(result ^ text.charCodeAt(i), 16777619)
    return `${(result >>> 0).toString(36)}-${text.length}`
  }

  static signature(content: string): string { return InteractionService.hash(content.replace(/\r\n?/g, '\n').trim()) }

  static isPreviousVersion(record: InteractionRecord, content: string): boolean {
    return !!record.contentSignature && record.contentSignature !== InteractionService.signature(content)
  }

  static layout(content: string): InteractionLayout {
    const result: InteractionLayout = { lists: {}, cells: {}, controls: [], hasTables: false, inline: {} }
    const sections: string[] = []
    const occurrences: Record<string, number> = {}
    const unique = (prefix: string, text: string): string => {
      const key = `${prefix}-${InteractionService.hash(text)}`
      const count = occurrences[key] || 0
      occurrences[key] = count + 1
      return `${key}-${count}`
    }
    MarkdownParser.parse(content).forEach((block, blockIndex: number) => {
      if (block.kind === 'heading') {
        while (sections.length < block.level) sections.push('')
        sections[block.level - 1] = InteractionService.plain(block.text)
        sections.length = block.level
      }
      const section = sections.filter((part: string) => part.length > 0).join(' / ')
      if (block.kind === 'list' && (['☐', '☑'].includes(block.prefix) ||
        /清单|待办|任务|检查项/.test(section) && !/[□☐☑☒]/.test(block.text) &&
        !/^(如果|若|例如|比如)/.test(InteractionService.plain(block.text))) && result.controls.length < 158) {
        const label = InteractionService.plain(block.text)
        const control: InteractionControl = { id: unique('list', `${section}|${label}`), label: label.slice(0, 240),
          kind: 'check', initialValue: block.prefix === '☑' ? 'true' : 'false' }
        result.lists[`${blockIndex}`] = control
        result.controls.push(control)
      }
      if (['paragraph', 'list'].includes(block.kind)) {
        const tokens = InteractionService.formTokens(block.text, unique('inline', `${section}|${block.text}`), section)
        if (tokens.some((token: InteractionToken) => token.control !== undefined)) {
          result.inline![`${blockIndex}`] = tokens
          InteractionService.registerTokens(tokens, result)
        }
      }
      if (block.kind === 'table') {
        result.hasTables = true
        block.rows.slice(1).forEach((row, offset: number) => {
          const rowLabel = InteractionService.plain(row.cells[0] || `第${offset + 1}行`)
          const rowId = unique('row', `${section}|${rowLabel}`)
          row.cells.forEach((cell: string, column: number) => {
            if (result.controls.length >= 158) return
            const header = InteractionService.plain(block.rows[0].cells[column] || `第${column + 1}列`)
            const tokens = InteractionService.formTokens(cell, `${rowId}-field-${column}`, `${section} / ${rowLabel} / ${header}`)
            if (tokens.some((token: InteractionToken) => token.control !== undefined)) {
              result.inline![`${blockIndex}:${offset + 1}:${column}`] = tokens
              InteractionService.registerTokens(tokens, result)
              return
            }
            const control: InteractionControl = { id: `${rowId}-cell-${InteractionService.hash(header)}-${column}`,
              label: `${section ? `${section} / ` : ''}${rowLabel} / ${header}`.slice(0, 240), kind: 'text', initialValue: cell }
            result.cells[`${blockIndex}:${offset + 1}:${column}`] = control
            result.controls.push(control)
          })
        })
      }
    })
    result.controls.push({ id: 'decision', label: '内容确认', kind: 'decision', initialValue: 'none' })
    result.controls.push({ id: 'notes', label: '补充说明或修改要求', kind: 'text', initialValue: '' })
    return result
  }

  // Parse blanks before Markdown emphasis. Inline code and escaped markers stay literal.
  private static registerTokens(tokens: InteractionToken[], layout: InteractionLayout): void {
    tokens.forEach((token: InteractionToken) => {
      if (token.control === undefined) return
      if (layout.controls.length < 158) layout.controls.push(token.control)
      else {
        token.text = token.kind === 'input' ? '____' : `□ ${token.text}`
        token.kind = 'text'
        token.control = undefined
      }
    })
  }

  static formTokens(text: string, identity: string, label: string): InteractionToken[] {
    const tokens: InteractionToken[] = []
    const pattern = /(`+)[\s\S]*?\1|\\[_□☐☑☒]|__[^_\n]+__|[_]{2,}|[＿﹍﹎]{1,}|[□☐☑☒]\s*[^□☐☑☒\n]*/g
    const single = /是否|单选|二选一|任选其一/.test(label + text) && !/多选|可同时/.test(label + text)
    let offset = 0
    let count = 0
    let match: RegExpExecArray | null = pattern.exec(text)
    while (match !== null) {
      if (match.index > offset) tokens.push({ kind: 'text', text: text.slice(offset, match.index) })
      const raw = match[0]
      if (raw.startsWith('`') || raw.startsWith('\\') || /^__[^_]+__$/.test(raw) || (/^_/.test(raw) &&
        ((match.index > 0 && /[A-Za-z0-9]/.test(text.charAt(match.index - 1))) || /[A-Za-z]/.test(text.charAt(match.index + raw.length))))) {
        tokens.push({ kind: 'text', text: raw })
      } else if (/^[□☐☑☒]/.test(raw)) {
        const option = raw.slice(1).trim()
        if (option) tokens.push({ kind: 'check', text: option, control: { id: `${identity}-option-${count++}`,
          label: `${label} / ${InteractionService.plain(option)}`.slice(0, 240), kind: 'check',
          initialValue: /^[☑☒]/.test(raw) ? 'true' : 'false', group: single ? identity : undefined } })
        else tokens.push({ kind: 'text', text: raw })
      } else {
        const before = InteractionService.plain(text.slice(0, match.index)).slice(-60)
        tokens.push({ kind: 'input', text: '', control: { id: `${identity}-blank-${count++}`,
          label: `${label} / ${before || '填写信息'}`.slice(0, 240), kind: 'text', initialValue: '' } })
      }
      offset = match.index + raw.length
      match = pattern.exec(text)
    }
    if (offset < text.length) tokens.push({ kind: 'text', text: text.slice(offset) })
    return tokens
  }

  static inlineTokens(layout: InteractionLayout, key: string): InteractionToken[] { return layout.inline?.[key] || [] }

  static formPreview(tokens: InteractionToken[], record: InteractionRecord): string {
    return tokens.map((token: InteractionToken): string => token.control === undefined ? token.text : token.kind === 'input'
      ? InteractionService.inputValue(record, token.control) || '____'
      : `${InteractionService.controlValue(record, token.control) === 'true' ? '☑' : '□'} ${token.text}`).join('')
  }

  static isPlaceholder(text: string): boolean {
    return /^(待填写|待补充|未填写|未提供|待确认|[-_—]{2,})$/.test(text.trim())
  }

  static empty(id: string = ''): InteractionRecord { return { id: id, source: '', title: '', values: [], updatedAt: 0 } }

  static record(records: InteractionRecord[] | undefined, id: string): InteractionRecord {
    return records?.find((item: InteractionRecord) => item.id === id) || InteractionService.empty(id)
  }

  static value(record: InteractionRecord, id: string, fallback: string = ''): string {
    return record.values.find((item: InteractionValue) => item.id === id)?.value ?? fallback
  }

  static controlValue(record: InteractionRecord, control: InteractionControl): string {
    return InteractionService.value(record, control.id, control.initialValue)
  }

  static inputValue(record: InteractionRecord, control: InteractionControl): string {
    const stored = record.values.find((item: InteractionValue) => item.id === control.id)
    if (stored !== undefined) return stored.value
    const initial = InteractionService.plain(control.initialValue)
    return /^(?:待填写|待补充|未填写|未提供|待确认|[-_—]{2,})$/.test(initial) ? '' : initial
  }

  static preview(content: string, record: InteractionRecord): string {
    const layout = InteractionService.layout(content)
    return MarkdownParser.parse(content).map((block, index: number): string => {
      const list = layout.lists[`${index}`]
      const inline = InteractionService.inlineTokens(layout, `${index}`)
      const body = inline.length > 0 ? InteractionService.formPreview(inline, record) : InteractionService.plain(block.text)
      if (list !== undefined) return `${InteractionService.controlValue(record, list) === 'true' ? '✓' : '○'} ${body}`
      if (block.kind === 'table') {
        return block.rows.map((row, rowIndex: number): string => row.cells.map((cell: string, column: number): string => {
          const control = layout.cells[`${index}:${rowIndex}:${column}`]
          const tokens = InteractionService.inlineTokens(layout, `${index}:${rowIndex}:${column}`)
          if (tokens.length > 0) return InteractionService.formPreview(tokens, record)
          return control === undefined ? cell : InteractionService.controlValue(record, control)
        }).join(' · ')).join('\n')
      }
      return body
    }).filter((line: string) => line.length > 0).join('\n').slice(0, 160)
  }

  static elementId(documentId: string, controlId: string): string {
    return `interaction-${documentId}-${controlId}`.replace(/[^A-Za-z0-9_-]/g, '-')
  }

  private static validValue(kind: string, value: string): boolean {
    return typeof value === 'string' && value.length <= InteractionService.maxValueLength &&
      (kind === 'text' || (kind === 'check' && ['true', 'false'].includes(value)) ||
        (kind === 'decision' && ['none', 'confirmed', 'needs_changes'].includes(value)))
  }

  static restore(records?: InteractionRecord[]): InteractionRecord[] {
    if (!Array.isArray(records)) return []
    const result: InteractionRecord[] = []
    const seen = new Set<string>()
    let entries = 0
    for (const record of records) {
      if (record === null || typeof record !== 'object' || typeof record.id !== 'string' || !record.id || record.id.length > 160 ||
        seen.has(record.id) || !['message', 'artifact', 'memory'].includes(record.source) || typeof record.title !== 'string' ||
        record.title.length > 160 || !Array.isArray(record.values)) continue
      const ids = new Set<string>()
      const values = record.values.filter((value: InteractionValue) => {
        if (value === null || typeof value !== 'object' || typeof value.id !== 'string' || !value.id || value.id.length > 100 ||
          ids.has(value.id) || typeof value.label !== 'string' || value.label.length > 240 || !InteractionService.validValue(value.kind, value.value)) return false
        ids.add(value.id)
        return true
      }).slice(0, 160)
      if (result.length >= InteractionService.maxRecords || entries + values.length > InteractionService.maxEntries) break
      const next: InteractionRecord = { id: record.id, source: record.source, title: record.title,
        values: values.map((value: InteractionValue): InteractionValue => ({ id: value.id, kind: value.kind, label: value.label, value: value.value })),
        updatedAt: Number.isFinite(record.updatedAt) ? record.updatedAt : 0,
        resetAt: typeof record.resetAt === 'number' && Number.isFinite(record.resetAt) ? record.resetAt : undefined,
        contentSignature: typeof record.contentSignature === 'string' && record.contentSignature.length <= 80 ? record.contentSignature : undefined }
      if (JSON.stringify(result.concat([next])).length > InteractionService.maxSize) break
      result.push(next)
      entries += values.length
      seen.add(record.id)
    }
    return result
  }

  static update(records: InteractionRecord[] | undefined, id: string, source: string, title: string,
    content: string, change: InteractionChange): InteractionRecord[] {
    if (!id || id.length > 160 || !['message', 'artifact', 'memory'].includes(source)) throw new Error('交互来源无效。')
    const next = InteractionService.restore(records)
    let record = next.find((item: InteractionRecord) => item.id === id)
    if (record === undefined) {
      record = { id: id, source: source, title: title.slice(0, 160), values: [], updatedAt: 0 }
      next.push(record)
    }
    if (InteractionService.isPreviousVersion(record, content)) record.values = record.values.filter((item: InteractionValue) => item.id !== 'decision')
    if (change.reset === true) {
      record.values = []
      record.resetAt = Date.now()
    } else {
      const controls = InteractionService.layout(content).controls
      const control = controls.find((item: InteractionControl) => item.id === change.controlId)
      if (control === undefined || !InteractionService.validValue(control.kind, change.value)) throw new Error('交互项已变化或内容超过1000字，请重试。')
      if (control.group && change.value === 'true') {
        controls.filter((item: InteractionControl) => item.group === control.group && item.id !== control.id).forEach((item: InteractionControl) => {
          record!.values = record!.values.filter((value: InteractionValue) => value.id !== item.id)
          record!.values.push({ id: item.id, label: item.label, kind: 'check', value: 'false' })
        })
      }
      const value: InteractionValue = { id: control.id, label: control.label, kind: control.kind, value: change.value }
      const existing = record.values.findIndex((item: InteractionValue) => item.id === control.id)
      if (existing < 0) record.values.push(value)
      else record.values[existing] = value
    }
    record.title = title.slice(0, 160)
    record.contentSignature = InteractionService.signature(content)
    record.updatedAt = Date.now()
    if (next.length > InteractionService.maxRecords || next.reduce((sum: number, item: InteractionRecord) => sum + item.values.length, 0) > InteractionService.maxEntries ||
      JSON.stringify(next).length > InteractionService.maxSize) throw new Error('本会话反馈较多，请重置不再需要的内容反馈后重试。')
    return next
  }

  static snapshotRecords(records?: InteractionRecord[], sources?: Record<string, string>): InteractionContextRecord[] {
    return InteractionService.restore(records).map((record: InteractionRecord): InteractionContextRecord => {
      const content = sources === undefined ? undefined : sources[record.id]
      const controls = content === undefined ? undefined : InteractionService.layout(content).controls
      const values = record.values.map((value: InteractionValue): InteractionContextValue => ({ id: value.id, label: value.label,
        kind: value.kind, value: value.value, active: controls === undefined ? undefined : controls.some((control: InteractionControl) => control.id === value.id) }))
      return { id: record.id, source: record.source, title: record.title, values: values, updatedAt: record.updatedAt,
        resetAt: record.resetAt, contentSignature: record.contentSignature,
        versionStatus: content === undefined || !record.contentSignature ? 'unknown' : InteractionService.isPreviousVersion(record, content) ? 'previous' : 'current' }
    }).sort((a: InteractionContextRecord, b: InteractionContextRecord) => b.updatedAt - a.updatedAt)
  }

  static context(records?: InteractionRecord[], sources?: Record<string, string>): string {
    const valid = InteractionService.snapshotRecords(records, sources)
    return valid.length === 0 ? '' : JSON.stringify(valid)
  }
}
