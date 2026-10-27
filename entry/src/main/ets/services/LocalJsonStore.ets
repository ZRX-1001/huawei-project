import { fileIo as fs } from '@kit.CoreFileKit'

// Short synchronous transactions; a directory lock also coordinates extension processes.
export class LocalJsonStore<T> {
  private path: string
  private empty: () => T
  private validate: (value: T) => boolean
  constructor(path: string, empty: () => T, validate: (value: T) => boolean) { this.path = path; this.empty = empty; this.validate = validate }

  read(): T {
    let exists = false
    for (const path of [this.path, `${this.path}.bak`]) {
      try {
        if (!fs.accessSync(path)) continue
        exists = true
        const text = fs.readTextSync(path)
        if (text.length > 8000000) throw new Error('Archive too large')
        const value = JSON.parse(text) as T
        if (this.validate(value)) return value
      } catch (_error) { exists = true }
    }
    if (exists) throw new Error('本地数据读取失败，原文件已保留。')
    return this.empty()
  }

  change(update: (value: T) => T): T {
    const lock = `${this.path}.lock`
    try {
      if (fs.accessSync(lock) && Date.now() / 1000 - fs.statSync(lock).mtime > 30) fs.rmdirSync(lock)
      fs.mkdirSync(lock)
    } catch (_error) { throw new Error('数据正在保存，请稍后重试。') }
    let file: fs.File | undefined = undefined
    try {
      const next = update(this.read())
      if (!this.validate(next)) throw new Error('数据无效或超出保存范围。')
      const text = JSON.stringify(next)
      if (text.length > 8000000) throw new Error('本地数据量过大，请先整理。')
      file = fs.openSync(`${this.path}.tmp`, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
      fs.writeSync(file.fd, text); fs.fsyncSync(file.fd); fs.closeSync(file); file = undefined
      fs.copyFileSync(`${this.path}.tmp`, `${this.path}.bak.tmp`)
      fs.renameSync(`${this.path}.bak.tmp`, `${this.path}.bak`)
      fs.renameSync(`${this.path}.tmp`, this.path)
      return next
    } finally {
      if (file !== undefined) { try { fs.closeSync(file) } catch (_error) {} }
      try { fs.rmdirSync(lock) } catch (_error) {}
    }
  }
}
