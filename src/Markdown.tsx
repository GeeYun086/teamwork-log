import { createElement, useEffect, useState } from 'react'

export function MarkdownPreview({ text, className = '' }: { text: string; className?: string }) {
  const inline = (value: string) => {
    const parts = value.split(/(\[[^\]]+\]\(https?:\/\/[^\s)]+\)|\*\*[^*]+\*\*|__[^_]+__|~~[^~]+~~|`[^`]+`|\*[^*]+\*|_[^_]+_|https?:\/\/[^\s]+)/g).filter(Boolean)
    return parts.map((part, index) => {
      const link = part.match(/^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/)
      if (link) return <a key={index} href={link[2]} target="_blank" rel="noreferrer">{link[1]}</a>
      if (/^https?:\/\//.test(part)) return <a key={index} href={part} target="_blank" rel="noreferrer">{part}</a>
      if ((part.startsWith('**') && part.endsWith('**')) || (part.startsWith('__') && part.endsWith('__'))) return <strong key={index}>{part.slice(2, -2)}</strong>
      if (part.startsWith('~~') && part.endsWith('~~')) return <del key={index}>{part.slice(2, -2)}</del>
      if (part.startsWith('`') && part.endsWith('`')) return <code key={index}>{part.slice(1, -1)}</code>
      if ((part.startsWith('*') && part.endsWith('*')) || (part.startsWith('_') && part.endsWith('_'))) return <em key={index}>{part.slice(1, -1)}</em>
      return part
    })
  }
  const lines = text.replace(/\r/g, '').split('\n'), blocks: any[] = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i]
    if (!line.trim()) { i++; continue }
    if (/^```/.test(line)) {
      const lang = line.slice(3).trim(), code: string[] = []
      i++
      while (i < lines.length && !/^```/.test(lines[i])) code.push(lines[i++])
      if (i < lines.length) i++
      blocks.push(<pre key={blocks.length} data-language={lang || undefined}><code>{code.join('\n')}</code></pre>)
      continue
    }
    const heading = line.match(/^(#{1,6})\s+(.+)$/)
    if (heading) { blocks.push(createElement(`h${heading[1].length}`, { key: blocks.length }, inline(heading[2].replace(/\s+#+\s*$/, '')))); i++; continue }
    if (/^\s*(---+|\*\*\*+|___+)\s*$/.test(line)) { blocks.push(<hr key={blocks.length}/>); i++; continue }
    if (/^\s*>/.test(line)) {
      const quote: string[] = []
      while (i < lines.length && /^\s*>/.test(lines[i])) quote.push(lines[i++].replace(/^\s*>\s?/, ''))
      blocks.push(<blockquote key={blocks.length}>{quote.map((part, index) => <p key={index}>{inline(part)}</p>)}</blockquote>)
      continue
    }
    if (/^\s*\|?\s*:?-{3,}/.test(line) && i > 0 && lines[i - 1].includes('|')) { i++; continue }
    if (line.includes('|') && i + 1 < lines.length && /^\s*\|?\s*:?-{3,}/.test(lines[i + 1])) {
      const cells = (source: string) => source.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map(cell => cell.trim())
      const header = cells(line); i += 2; const rows: string[][] = []
      while (i < lines.length && lines[i].includes('|')) rows.push(cells(lines[i++]))
      blocks.push(<div className="markdown-table-wrap" key={blocks.length}><table><thead><tr>{header.map((cell, index) => <th key={index}>{inline(cell)}</th>)}</tr></thead><tbody>{rows.map((row, rowIndex) => <tr key={rowIndex}>{header.map((_, cellIndex) => <td key={cellIndex}>{inline(row[cellIndex] || '')}</td>)}</tr>)}</tbody></table></div>)
      continue
    }
    const unordered = line.match(/^\s*[-*+]\s+(.+)$/), ordered = line.match(/^\s*\d+[.)]\s+(.+)$/)
    if (unordered || ordered) {
      const isOrdered = !!ordered, items: any[] = []
      while (i < lines.length) {
        const match = lines[i].match(isOrdered ? /^\s*\d+[.)]\s+(.+)$/ : /^\s*[-*+]\s+(.+)$/)
        if (!match) break
        const task = match[1].match(/^\[([ xX])\]\s+(.*)$/)
        items.push(isOrdered ? <li key={items.length}>{inline(match[1])}</li> : <li key={items.length}>{task && <input type="checkbox" checked={task[1].toLowerCase() === 'x'} readOnly/>}{inline(task ? task[2] : match[1])}</li>)
        i++
      }
      const List = isOrdered ? 'ol' : 'ul'; blocks.push(<List key={blocks.length}>{items}</List>); continue
    }
    const para = [line]; i++
    while (i < lines.length && lines[i].trim() && !/^(#{1,6}\s|```|\s*>|\s*[-*+]\s|\s*\d+[.)]\s)/.test(lines[i])) para.push(lines[i++])
    blocks.push(<p key={blocks.length}>{inline(para.join(' '))}</p>)
  }
  return <div className={`markdown-preview ${className}`.trim()}>{blocks.length ? blocks : <p className="markdown-empty">내용이 없습니다.</p>}</div>
}

type MarkdownEditorProps = {
  name?: string
  value?: string
  defaultValue?: string
  onChange?: (value: string) => void
  rows?: number
  maxLength?: number
  placeholder?: string
  required?: boolean
  disabled?: boolean
  previewByDefault?: boolean
  className?: string
}

export function MarkdownEditor({ name, value, defaultValue = '', onChange, rows = 4, maxLength, placeholder, required, disabled, previewByDefault = true, className = '' }: MarkdownEditorProps) {
  const [internal, setInternal] = useState(value ?? defaultValue)
  const [preview, setPreview] = useState(previewByDefault)
  useEffect(() => { if (value !== undefined) setInternal(value) }, [value])
  const current = value ?? internal
  const update = (next: string) => { setInternal(next); onChange?.(next) }
  return <div className={`markdown-field ${className}`.trim()}>
    <div className="markdown-field-toolbar">
      <span>마크다운</span>
      <button type="button" className="markdown-preview-toggle" onClick={() => setPreview(current => !current)} disabled={disabled}>{preview ? '편집' : '미리보기'}</button>
    </div>
    {preview ? <><input type="hidden" name={name} value={current}/><MarkdownPreview text={current}/></> : <textarea name={name} value={current} onChange={event => update(event.target.value)} rows={rows} maxLength={maxLength} placeholder={placeholder} required={required} disabled={disabled}/>}
  </div>
}
