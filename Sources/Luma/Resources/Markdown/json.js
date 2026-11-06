/* Whitespace-only formatting: keep number lexemes, duplicate keys and escapes intact. */
(() => {
  'use strict';
  window.lumaFormatJSON = source => {
    const parts = [];
    const indentation = [''];
    const maxOutput = 2 * 1024 * 1024;
    let position = 0, depth = 0, size = 0, previous = '';
    const whitespace = character => character === ' ' || character === '\n' || character === '\r' || character === '\t';
    const punctuation = character => '{}[],:'.includes(character);
    const append = text => {
      size += text.length;
      if (size > maxOutput) throw new RangeError('Formatting limit');
      parts.push(text);
    };
    const newline = () => {
      while (indentation.length <= depth) indentation.push(indentation.at(-1) + '  ');
      append('\n' + indentation[depth]);
    };
    try {
      while (position < source.length) {
        if (whitespace(source[position])) { position++; continue; }
        const start = position;
        let token = source[position++];
        if (token === '"') {
          while (position < source.length) {
            const character = source[position++];
            if (character === '\\') position++;
            else if (character === '"') break;
          }
          token = source.slice(start, position);
        } else if (!punctuation(token)) {
          while (position < source.length && !whitespace(source[position]) && !punctuation(source[position])) position++;
          token = source.slice(start, position);
        }
        if (token === '{' || token === '[') {
          append(token);
          if (++depth > 128) throw new RangeError('Nesting limit');
          let next = position;
          while (next < source.length && whitespace(source[next])) next++;
          if (source[next] !== (token === '{' ? '}' : ']')) newline();
        } else if (token === '}' || token === ']') {
          if (--depth < 0) throw new RangeError('Unbalanced JSON');
          if (previous !== '{' && previous !== '[') newline();
          append(token);
        } else if (token === ',') { append(','); newline(); }
        else if (token === ':') append(': ');
        else append(token);
        previous = token;
      }
      return depth === 0 ? parts.join('') : source;
    } catch { return source; }
  };
})();
