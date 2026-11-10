/* Whitespace-only formatting: keep number lexemes, duplicate keys, escapes and comments. */
(() => {
  'use strict';
  const ui = window.lumaUI.text;
  const MAX_OUTPUT = 2 * 1024 * 1024;
  const whitespace = character => /[ \n\r\t]/.test(character);
  const punctuation = character => '{}[],:'.includes(character);

  function tokens(source, comments = false) {
    const result = [];
    let position = 0;
    while (position < source.length) {
      if (whitespace(source[position])) { position++; continue; }
      const start = position;
      let kind = 'value';
      if (source[position] === '"') {
        position++;
        let closed = false;
        while (position < source.length) {
          const character = source[position++];
          if (character === '\\') position++;
          else if (character === '"') { closed = true; break; }
        }
        if (!closed) throw new SyntaxError(ui('字符串尚未结束'));
      } else if (comments && source.startsWith('//', position)) {
        kind = 'lineComment'; position += 2;
        while (position < source.length && !/[\r\n]/.test(source[position])) position++;
      } else if (comments && source.startsWith('/*', position)) {
        kind = 'blockComment';
        const end = source.indexOf('*/', position + 2);
        if (end === -1) throw new SyntaxError(ui('块注释尚未结束'));
        position = end + 2;
      } else if (punctuation(source[position])) {
        position++;
      } else {
        position++;
        while (position < source.length && !whitespace(source[position]) && !punctuation(source[position]) &&
               !(comments && (source.startsWith('//', position) || source.startsWith('/*', position)))) position++;
      }
      result.push({kind, text: source.slice(start, position)});
      if (result.length > 250000) throw new RangeError(ui('格式化标记超过上限'));
    }
    return result;
  }

  function format(source, items) {
    const parts = [], indentation = [''];
    let depth = 0, size = 0, previous = '', lineStart = true;
    const append = text => {
      if (lineStart) {
        while (indentation.length <= depth) indentation.push(indentation.at(-1) + '  ');
        parts.push(indentation[depth]); size += indentation[depth].length; lineStart = false;
      }
      size += text.length;
      if (size > MAX_OUTPUT) throw new RangeError('Formatting limit');
      parts.push(text);
    };
    const newline = () => { if (!lineStart) { parts.push('\n'); size++; lineStart = true; } };
    for (let index = 0; index < items.length; index++) {
      const {kind, text} = items[index];
      if (kind === 'lineComment') {
        if (!lineStart) append(' ');
        append(text); newline();
      } else if (kind === 'blockComment') {
        const inline = !lineStart;
        if (inline) append(' ');
        append(text);
        if (inline && !/[\r\n]/.test(text)) append(' ');
        else newline();
      } else if (text === '{' || text === '[') {
        append(text);
        if (++depth > 128) throw new RangeError('Nesting limit');
        if (items[index + 1]?.text !== (text === '{' ? '}' : ']')) newline();
      } else if (text === '}' || text === ']') {
        if (--depth < 0) throw new RangeError('Unbalanced JSON');
        if (previous !== '{' && previous !== '[') newline();
        append(text);
      } else if (text === ',') { append(','); newline(); }
      else if (text === ':') append(': ');
      else append(text);
      previous = text;
    }
    if (lineStart && parts.at(-1) === '\n') parts.pop();
    return depth === 0 ? parts.join('') : source;
  }

  window.lumaFormatJSON = source => {
    try { return format(source, tokens(source)); }
    catch { return source; }
  };
  window.lumaFormatJSONC = source => {
    try {
      const items = tokens(source, true);
      const significant = items.filter(item => item.kind === 'value');
      const clean = significant.filter((item, index) => {
        // Remove only an actual trailing comma, never a missing first value or doubled comma.
        if (item.text !== ',' || !['}', ']'].includes(significant[index + 1]?.text)) return true;
        return !index || ['{', '[', ':', ','].includes(significant[index - 1].text);
      }).map(item => item.text).join(' ');
      JSON.parse(clean);
      try { return format(source, items); }
      catch (error) { if (error instanceof RangeError) return source; throw error; }
    } catch (error) {
      throw new Error(ui('JSONC 格式错误：{0}', String(error.message || error).slice(0, 240)));
    }
  };

  window.lumaJSONLines = source => {
    const records = [];
    let size = 0;
    const fallback = note => ({records: [], fallback: source, note});
    for (const [index, line] of source.split(/\r\n|\r|\n/).entries()) {
      if (!line.trim()) continue;
      if (records.length >= 10000) return fallback(ui('记录超过 10,000 条，已按原文显示。可以切换到源码继续编辑。'));
      let value = line, error = '';
      try { JSON.parse(line); value = window.lumaFormatJSON(line); }
      catch (failure) { error = ui('第 {0} 行不是有效 JSON：{1}', index + 1, String(failure.message || failure).slice(0, 200)); }
      size += value.length;
      if (size > MAX_OUTPUT) return fallback(ui('格式化后的内容超过预览上限，已按原文显示。'));
      records.push({sourceLine: index + 1, value, error});
    }
    return {records};
  };
})();
