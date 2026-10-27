import { fileIo as fs } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import { LocalMemo } from '../models/ScheduleModels'

export class MemoStore {
  private path: string
  private memos: LocalMemo[] = []
  private blocked: boolean = false

  constructor(filesDir: string) {
    this.path = `${filesDir}/local_memos.json`
    let existed = false
    for (const path of [this.path, `${this.path}.bak`]) {
      try {
        if (!fs.accessSync(path)) continue
        existed = true
        const values = JSON.parse(fs.readTextSync(path)) as LocalMemo[]
        if (!Array.isArray(values) || values.length > 100 || values.some((item: LocalMemo) =>
          !item || typeof item.id !== 'string' || typeof item.title !== 'string' || typeof item.content !== 'string' ||
          item.title.length > 500 || item.content.length > 8000 || !Number.isFinite(item.createdAt) || !Number.isFinite(item.updatedAt)) ||
          new Set(values.map((item: LocalMemo) => item.id)).size !== values.length) throw new Error('Invalid memo archive')
        this.memos = values
        return
      } catch (_error) { existed = true }
    }
    this.blocked = existed
  }

  list(): LocalMemo[] {
    if (this.blocked) throw new Error('本地备忘录读取失败，原文件已保留，请检查存储。')
    return this.memos.map((item: LocalMemo): LocalMemo => ({ id: item.id, title: item.title, content: item.content,
      createdAt: item.createdAt, updatedAt: item.updatedAt })).sort((a: LocalMemo, b: LocalMemo) => b.updatedAt - a.updatedAt)
  }

  get(id: string): LocalMemo {
    const memo = this.list().find((item: LocalMemo) => item.id === id)
    if (memo === undefined) throw new Error('备忘录不存在，请重新查询。')
    return memo
  }

  save(title: string, content: string, id?: string): LocalMemo {
    const next = this.list()
    const previous = id ? this.get(id) : undefined
    const memo: LocalMemo = { id: previous?.id || util.generateRandomUUID(), title: title.trim(), content: content,
      createdAt: previous?.createdAt || Date.now(), updatedAt: Date.now() }
    if (!memo.title || memo.title.length > 500 || !memo.content.trim() || memo.content.length > 8000) throw new Error('备忘录内容无效或过长。')
    const index = next.findIndex((item: LocalMemo) => item.id === memo.id)
    if (index < 0) { if (next.length >= 100) throw new Error('最多保存100条备忘录，请先整理。'); next.push(memo) }
    else next[index] = memo
    this.write(next)
    return memo
  }

  delete(id: string): void { this.get(id); this.write(this.list().filter((item: LocalMemo) => item.id !== id)) }

  private write(next: LocalMemo[]): void {
    const temporary = `${this.path}.tmp`
    let file: fs.File | undefined = undefined
    try {
      file = fs.openSync(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, JSON.stringify(next))
      fs.fsyncSync(file.fd)
      fs.closeSync(file); file = undefined
      // Both snapshots hold the new valid state, so deleted notes cannot reappear on recovery.
      fs.copyFileSync(temporary, `${this.path}.bak`)
      fs.renameSync(temporary, this.path)
      this.memos = next
    } catch (_error) {
      if (file !== undefined) { try { fs.closeSync(file) } catch (_closeError) {} }
      throw new Error('备忘录保存失败，请检查设备存储。')
    }
  }
}
