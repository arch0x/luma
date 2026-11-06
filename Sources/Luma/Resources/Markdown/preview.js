/* Luma's offline Markdown surface. User content enters as data, never as script. */
(() => {
  'use strict';
  const root = document.getElementById('document');
  const MAX_HIGHLIGHT = 100000;
  const MAX_DIAGRAM = 50000;
  const MAX_DIAGRAMS = 40;
  const MAX_MATH = 500;
  const MAX_MATH_LENGTH = 10000;
  let generation = 0;
  let scrollTimer;
  let restoring = false;
  let headingElements = [];
  let headingMap = new Map();
  let headingOffsets = [];
  let activeHeading = null;
  let forcedHeading = null;
  let sectionTimer;
  let outlineFrame;

  function notify(body) {
    window.webkit?.messageHandlers?.luma?.postMessage(body);
  }
  const search = window.createLumaSearch(root, {
    publish: notify,
    didNavigate() {
      forcedHeading = null;
      updateActiveHeading();
      publishPosition();
    }
  });
  const reading = window.createLumaReading(root, {label: headingLabel, headings: () => headingElements});
  function publishPosition() {
    if (restoring) return;
    const location = reading.capture();
    notify({kind: 'position', offset: location.offset, location});
  }
  function applyWidth(width) {
    const value = Number(width);
    root.style.setProperty('--reading-width', Number.isFinite(value) && value > 0 ? `${Math.min(1600, Math.max(640, value))}px` : 'none');
  }
  const fontFamilies = Object.freeze({
    system: '-apple-system, BlinkMacSystemFont, sans-serif',
    songti: '"Songti SC", STSong, serif',
    monospaced: 'ui-monospace, "SFMono-Regular", Menlo, monospace'
  });
  function applyTypography(options = {}) {
    const font = Object.hasOwn(fontFamilies, options.font) ? options.font : 'system';
    const size = Number(options.fontSize), height = Number(options.lineHeight);
    root.style.setProperty('--reading-font', fontFamilies[font]);
    root.style.setProperty('--reading-size', `${Number.isFinite(size) && size >= 12 && size <= 28 ? size : 15}px`);
    root.style.setProperty('--reading-line-height', Number.isFinite(height) && height >= 1.3 && height <= 2.4 ? String(height) : '1.85');
  }
  function setReadingLayout(options = {}) {
    const location = reading.capture(true);
    restoring = true;
    search.hide();
    if (Object.hasOwn(options, 'width')) applyWidth(options.width);
    if (options.typography) applyTypography(options.typography);
    reading.restore(location);
    restoring = false; forcedHeading = null;
    refreshHeadingOffsets(); search.relayout(true); publishPosition();
    return reading.capture();
  }
  function setPreviewWidth(width) { return setReadingLayout({width}); }
  function restoreReadingPosition(location) {
    if (restoring) return false;
    reading.restore(location);
    forcedHeading = null;
    headingMap.get(location.headingID)?.focus({preventScroll: true});
    updateActiveHeading(); publishPosition();
    return true;
  }
  function escape(text) {
    return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
  }

  function headingLabel(heading) {
    const clone = heading.cloneNode(true);
    clone.querySelectorAll('.heading-anchor').forEach(node => node.remove());
    clone.querySelectorAll('.math-inline,.math-display').forEach(node => node.replaceWith(document.createTextNode(node.dataset.mathSource || node.textContent)));
    clone.querySelectorAll('.local-image').forEach(node => node.replaceWith(document.createTextNode(node.dataset.alt || '')));
    return clone.textContent.replace(/\s+/g, ' ').trim();
  }
  function buildOutline() {
    headingElements = [...root.querySelectorAll('h1,h2,h3,h4,h5,h6')];
    headingMap = new Map(); headingOffsets = []; activeHeading = null; forcedHeading = null;
    const headingSet = new Set(headingElements);
    const used = new Set([...root.querySelectorAll('[id]')].filter(node => !headingSet.has(node)).map(node => node.id));
    const nextSuffix = new Map();
    const outline = [];
    headingElements.forEach(heading => {
      const label = headingLabel(heading);
      const slug = label.normalize('NFC').toLowerCase().replace(/[^\p{L}\p{N}_\s-]/gu, '').trim().replace(/\s+/g, '-');
      const base = Array.from(slug).slice(0, 160).join('') || 'section';
      let id = base, suffix = nextSuffix.get(base) || 1;
      while (used.has(id)) id = `${base}-${suffix++}`;
      nextSuffix.set(base, suffix);
      used.add(id); heading.id = id; heading.tabIndex = -1;
      headingMap.set(id, heading);
      const title = Array.from(label).slice(0, 240).join('') || '无标题';
      const anchor = document.createElement('a'); anchor.className = 'heading-anchor';
      anchor.href = `#${encodeURIComponent(id)}`;
      anchor.setAttribute('aria-label', `定位标题：${title}`); anchor.title = '定位此标题';
      heading.prepend(anchor);
      if (outline.length < 2000) outline.push({id, title, level: Number(heading.tagName.slice(1))});
    });
    return outline;
  }
  function updateActiveHeading() {
    if (restoring) return;
    if (forcedHeading && Math.abs(window.scrollY - forcedHeading.offset) > 1) forcedHeading = null;
    let id = forcedHeading?.id || '';
    if (!id && headingOffsets.length) {
      let low = 0, high = headingOffsets.length - 1, selected = 0;
      const threshold = window.scrollY + 28;
      while (low <= high) {
        const middle = (low + high) >> 1;
        if (headingOffsets[middle] <= threshold) { selected = middle; low = middle + 1; }
        else { high = middle - 1; }
      }
      if (window.scrollY > 0 && window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2) selected = headingElements.length - 1;
      id = headingElements[selected].id;
    }
    if (id !== activeHeading) {
      activeHeading = id;
      notify({kind: 'section', id});
    }
  }
  function refreshHeadingOffsets() {
    headingOffsets = headingElements.map(heading => heading.getBoundingClientRect().top + window.scrollY);
    updateActiveHeading();
  }
  function navigateToHeading(id) {
    if (restoring) return false;
    const heading = id ? headingMap.get(id) : null;
    if (id && !heading) return false;
    const top = heading ? Math.max(0, heading.getBoundingClientRect().top + window.scrollY - 24) : 0;
    window.scrollTo({top, behavior: 'auto'});
    if (heading) {
      heading.focus({preventScroll: true});
      forcedHeading = {id, offset: window.scrollY};
    } else {
      forcedHeading = null;
      headingElements[0]?.focus({preventScroll: true});
    }
    updateActiveHeading();
    publishPosition();
    return true;
  }
  function highlight(code, language) {
    if (code.length > MAX_HIGHLIGHT || !language || !hljs.getLanguage(language)) return escape(code);
    try { return hljs.highlight(code, {language, ignoreIllegals: true}).value; }
    catch { return escape(code); }
  }
  function codeBlock(code, language) {
    const container = document.createElement('div');
    container.className = 'code-block';
    const toolbar = document.createElement('div');
    toolbar.className = 'code-toolbar';
    const label = document.createElement('span');
    label.className = 'code-language';
    label.textContent = language || '代码';
    const copy = document.createElement('button');
    copy.type = 'button'; copy.textContent = '复制代码';
    copy.addEventListener('click', () => { notify({kind: 'copy', text: code}); copy.textContent = '已复制'; });
    toolbar.append(label, copy);
    const pre = document.createElement('pre');
    const content = document.createElement('code');
    content.innerHTML = highlight(code, language);
    if (language && hljs.getLanguage(language) && code.length <= MAX_HIGHLIGHT) content.dataset.highlighted = 'true';
    pre.append(content); container.append(toolbar, pre);
    return container;
  }
  function syncJSONLineNumbers() {
    if (!root.hasAttribute('data-json-preview')) return;
    const lines = root.querySelectorAll('.json-code-line');
    const numbers = root.querySelectorAll('.json-line-number');
    const heights = Array.from(lines, line => line.getBoundingClientRect().height + 'px');
    numbers.forEach((number, index) => {
      if (number.style.height !== heights[index]) number.style.height = heights[index];
    });
  }
  function diagramBlock(code) {
    const figure = document.createElement('figure');
    figure.className = 'diagram';
    const toolbar = document.createElement('div');
    toolbar.className = 'diagram-toolbar'; toolbar.textContent = 'MERMAID';
    const canvas = document.createElement('div');
    canvas.className = 'diagram-canvas'; canvas.textContent = '正在绘制图表…';
    const details = document.createElement('details');
    details.className = 'diagram-source';
    const summary = document.createElement('summary'); summary.textContent = '查看图表源码';
    const source = document.createElement('pre'); source.textContent = code;
    const copy = document.createElement('button'); copy.textContent = '复制源码';
    copy.addEventListener('click', () => notify({kind: 'copy', text: code}));
    toolbar.append(copy); details.append(summary, source); figure.append(toolbar, canvas, details);
    return {figure, canvas, details, code};
  }

  function mathEnd(source, start, close, singleLine) {
    let depth = 0;
    for (let index = start; index < Math.min(source.length, start + MAX_MATH_LENGTH + close.length); index++) {
      if (singleLine && (source[index] === '\n' || source[index] === '`')) return -1;
      if (!depth && source.startsWith(close, index)) {
        if (close === '$' && (/\s/.test(source[index - 1] || '') || /[\d$]/.test(source[index + 1] || ''))) return -1;
        return index;
      }
      if (source[index] === '\\') { index++; continue; }
      if (source[index] === '{') depth++;
      else if (source[index] === '}') depth = Math.max(0, depth - 1);
    }
    return -1;
  }
  function mathExtensions(tokens) {
    let scans = 0;
    function findEnd(source, start, close, singleLine) {
      if (++scans > MAX_MATH * 4) return -1;
      return mathEnd(source, start, close, singleLine);
    }
    function renderer(token) {
      const index = tokens.push(token) - 1;
      const tag = token.display ? 'div' : 'span';
      return `<${tag} class="${token.display ? 'math-display' : 'math-inline'}" id="luma-math-${index}">${escape(token.raw)}</${tag}>`;
    }
    return [
      {
        name: 'lumaMathBlock', level: 'block',
        start(source) { return source.search(/(?:^|\n) {0,3}(?:\$\$|\\\[)/); },
        tokenizer(source) {
          const match = /^ {0,3}(\$\$|\\\[)/.exec(source);
          if (!match) return;
          const open = match[1], close = open === '$$' ? '$$' : '\\]';
          const end = findEnd(source, match[0].length, close, false);
          if (end < 0) return;
          const after = source.slice(end + close.length);
          const suffix = /^[ \t]*(?:\n|$)/.exec(after);
          if (!suffix) return;
          return {type: 'lumaMathBlock', raw: source.slice(0, end + close.length + suffix[0].length), text: source.slice(match[0].length, end).trim(), display: true};
        }, renderer
      },
      {
        name: 'lumaMathInline', level: 'inline',
        start(source) { return source.search(/\$|\\[([]/); },
        tokenizer(source) {
          const open = ['$$', '\\[', '\\(', '$'].find(value => source.startsWith(value));
          if (!open || (open === '$' && (!source[1] || /\s|\$/.test(source[1])))) return;
          const close = open === '\\[' ? '\\]' : open === '\\(' ? '\\)' : open;
          const end = findEnd(source, open.length, close, open === '$' || open === '\\(');
          if (end < 0 || end === open.length) return;
          return {type: 'lumaMathInline', raw: source.slice(0, end + close.length), text: source.slice(open.length, end), display: open === '$$' || open === '\\['};
        }, renderer
      }
    ];
  }

  function localImage(token, request, index) {
    const container = document.createElement('span'); container.className = 'local-image';
    container.dataset.alt = token.text || '';
    const image = document.createElement('img');
    image.alt = token.text || ''; image.decoding = 'async';
    if (token.title) image.title = token.title;
    const status = document.createElement('span'); status.className = 'image-status';
    status.textContent = `正在加载图片：${token.text || token.href}`;
    container.append(image, status);
    const ready = new Promise(resolve => {
      let finished = false;
      const finish = ok => {
        if (finished) return;
        finished = true; clearTimeout(timer);
        if (ok) { container.classList.add('image-loaded'); status.remove(); }
        else {
          image.remove(); container.classList.add('image-failed');
          status.textContent = `图片无法显示：${token.text || '未命名'}（${token.href}）。请检查图片路径、格式及工作区范围。`;
        }
        resolve(ok);
      };
      const timer = setTimeout(() => finish(false), 8000);
      image.onload = () => finish(image.naturalWidth > 0);
      image.onerror = () => finish(false);
      if (index >= 100) { finish(false); return; }
      // The native image handler resolves paths against this document's workspace.
      image.src = `luma-image://document/${request}/${index}?src=${encodeURIComponent(token.href)}`;
    });
    return {container, ready};
  }

  async function render(source, options = {}) {
    const request = ++generation;
    restoring = true;
    clearTimeout(scrollTimer);
    clearTimeout(sectionTimer); sectionTimer = null;
    document.documentElement.dataset.theme = options.dark ? 'dark' : 'light';
    applyWidth(options.width);
    applyTypography(options.typography);
    const parser = new marked.Marked({gfm: true, breaks: false});
    const math = [], images = [];
    // Math is tokenized before Markdown escapes, but after code spans/fences.
    parser.use({extensions: mathExtensions(math), renderer: {
      html({text}) { return `<pre class="raw-html">${escape(text)}</pre>`; },
      image(token) {
        const index = images.push(token) - 1;
        return `<span id="luma-image-${index}">[图片：${escape(token.text || '未命名')}]</span>`;
      }
    }});
    const codeLanguage = /^[a-z0-9-]+$/.test(options.codeLanguage || '') ? options.codeLanguage : '';
    const jsonPreview = codeLanguage === 'json';
    const displaySource = jsonPreview ? window.lumaFormatJSON(source) : source;
    // Code files are escaped directly; Markdown, HTML, images and formulas stay literal.
    const html = codeLanguage
      ? `<pre><code class="language-${codeLanguage}">${escape(displaySource)}\n</code></pre>`
      : parser.parse(source);
    root.toggleAttribute('data-code-preview', !!codeLanguage);
    root.toggleAttribute('data-json-preview', jsonPreview);
    root.setAttribute('aria-label', codeLanguage ? '代码预览' : 'Markdown 预览');
    search.reset();
    root.innerHTML = DOMPurify.sanitize(html, {
      USE_PROFILES: {html: true},
      FORBID_TAGS: ['style', 'script', 'iframe', 'form', 'input', 'button', 'img', 'video', 'audio', 'object', 'embed'],
      FORBID_ATTR: ['style', 'srcset'],
      ALLOW_DATA_ATTR: false
    });
    const imagePromises = [];
    images.forEach((token, index) => {
      const marker = document.getElementById(`luma-image-${index}`);
      if (!marker) return;
      const image = localImage(token, request, index);
      marker.replaceWith(image.container); imagePromises.push(image.ready);
    });
    let formulas = 0, mathFailures = 0;
    math.forEach((token, index) => {
      const marker = document.getElementById(`luma-math-${index}`);
      if (!marker) return;
      marker.dataset.mathSource = token.text;
      try {
        if (index >= MAX_MATH || token.text.length > MAX_MATH_LENGTH) throw new Error('公式超过预览限制。');
        const rendered = katex.renderToString(token.text, {
          displayMode: token.display, output: 'htmlAndMathml', throwOnError: true,
          trust: false, strict: 'warn', maxSize: 20, maxExpand: 1000, macros: {}
        });
        marker.innerHTML = DOMPurify.sanitize(rendered, {
          USE_PROFILES: {html: true, mathMl: true, svg: true},
          FORBID_TAGS: ['script', 'style', 'img', 'a', 'iframe']
        });
        marker.title = token.text;
        formulas++;
      } catch (error) {
        marker.classList.add('math-error'); marker.textContent = token.raw.trim();
        marker.title = `公式无法渲染，已保留源码：${String(error.message || error).slice(0, 400)}`;
        const note = document.createElement('span'); note.className = 'math-error-note'; note.textContent = '（公式无法渲染，已保留源码）';
        marker.append(note); mathFailures++;
      }
    });
    // The Markdown renderer's alignment attributes survive sanitization.
    root.querySelectorAll('table').forEach(table => {
      const wrapper = document.createElement('div'); wrapper.className = 'table-scroll';
      table.replaceWith(wrapper); wrapper.append(table);
    });
    const outline = buildOutline();
    const diagrams = [];
    root.querySelectorAll('pre > code').forEach(element => {
      const language = [...element.classList].find(name => name.startsWith('language-'))?.slice(9).toLowerCase() || '';
      const code = element.textContent.replace(/\n$/, '');
      if (language === 'mermaid') {
        const diagram = diagramBlock(code); element.parentNode.replaceWith(diagram.figure); diagrams.push(diagram);
      } else {
        const block = codeBlock(code, language);
        if (codeLanguage) block.querySelector('.code-language').textContent = options.codeTitle || language;
        if (jsonPreview) {
          block.querySelector('.code-toolbar').remove();
          const row = document.createElement('div');
          row.className = 'json-code-row';
          const content = block.querySelector('code');
          // Valid JSON tokens contain no literal newlines, so token spans stay within each line.
          const lines = content.innerHTML.split('\n');
          if (lines.length <= 20000) {
            row.classList.add('json-numbered');
            const gutter = document.createElement('div');
            gutter.className = 'json-line-numbers';
            gutter.setAttribute('aria-hidden', 'true');
            content.replaceChildren();
            lines.forEach((html, index) => {
              if (index) { gutter.append('\n'); content.append('\n'); }
              const number = document.createElement('span');
              number.className = 'json-line-number';
              number.textContent = index + 1;
              const line = document.createElement('span');
              line.className = 'json-code-line';
              line.innerHTML = html;
              gutter.append(number); content.append(line);
            });
            row.append(gutter);
          }
          row.append(block.querySelector('pre'));
          block.append(row);
        }
        element.parentNode.replaceWith(block);
      }
    });
    mermaid.initialize({
      startOnLoad: false, securityLevel: 'strict', suppressErrorRendering: true,
      theme: options.dark ? 'dark' : 'default', fontFamily: '-apple-system, sans-serif',
      htmlLabels: false, flowchart: {htmlLabels: false}, maxTextSize: MAX_DIAGRAM, maxEdges: 500,
      secure: ['secure', 'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges', 'suppressErrorRendering', 'htmlLabels', 'flowchart']
    });
    let rendered = 0, failed = 0;
    for (let index = 0; index < diagrams.length; index++) {
      if (request !== generation) return {cancelled: true};
      const diagram = diagrams[index];
      try {
        if (index >= MAX_DIAGRAMS) throw new Error('此文档最多预览 40 个图表，后续图表保留源码。');
        if (diagram.code.length > MAX_DIAGRAM) throw new Error('图表超过 50,000 字符，请精简后再试。');
        const {svg} = await mermaid.render(`luma-diagram-${request}-${index}`, diagram.code);
        if (request !== generation) return {cancelled: true};
        const clean = DOMPurify.sanitize(svg, {USE_PROFILES: {svg: true, svgFilters: true}, ADD_TAGS: ['style']});
        diagram.canvas.innerHTML = clean;
        if (!diagram.canvas.querySelector('svg')) throw new Error('没有生成可显示的图表。');
        rendered++;
      } catch (error) {
        if (request !== generation) return {cancelled: true};
        diagram.canvas.className = 'diagram-error';
        diagram.canvas.textContent = `图表无法渲染，已保留源码。\n${String(error.message || error).slice(0, 600)}`;
        diagram.details.open = true; failed++;
        document.getElementById(`dluma-diagram-${request}-${index}`)?.remove();
      }
    }
    if (request !== generation) return {cancelled: true};
    const imageResults = await Promise.all(imagePromises);
    await Promise.race([document.fonts.ready, new Promise(resolve => setTimeout(resolve, 2000))]);
    if (request !== generation) return {cancelled: true};
    await new Promise(resolve => { requestAnimationFrame(resolve); setTimeout(resolve, 100); });
    if (request !== generation) return {cancelled: true};
    syncJSONLineNumbers();
    reading.build();
    if (!codeLanguage && options.location && Number.isFinite(options.location.offset)) reading.restore(options.location);
    else window.scrollTo(0, Number(options.offset) || 0);
    restoring = false;
    notify({kind: 'outline', headings: outline, truncated: headingElements.length > outline.length});
    refreshHeadingOffsets();
    publishPosition();
    const stats = {ready: true, tables: root.querySelectorAll('table').length,
      highlighted: root.querySelectorAll('[data-highlighted]').length, diagrams: rendered, failures: failed,
      formulas, mathFailures, images: imageResults.filter(Boolean).length, imageFailures: imageResults.filter(value => !value).length,
      headings: headingElements.length};
    window.luma.lastResult = stats;
    notify({kind: 'ready', ...stats});
    return stats;
  }

  document.addEventListener('click', event => {
    const link = event.target.closest('a');
    if (!link) return;
    const href = link.getAttribute('href') || '';
    event.preventDefault();
    if (href.startsWith('#')) {
      try { navigateToHeading(decodeURIComponent(href.slice(1))); } catch {}
    } else if (href) { notify({kind: 'link', href}); }
  });
  document.addEventListener('copy', event => {
    if (!root.hasAttribute('data-json-preview') || !event.clipboardData) return;
    const selection = window.getSelection();
    const code = root.querySelector('pre code');
    if (!code || !selection?.rangeCount || selection.isCollapsed) return;
    const range = selection.getRangeAt(0).cloneRange();
    if (!range.intersectsNode(code)) return;
    // Serialize logical lines instead of layout line breaks introduced by wrapping.
    if (!code.contains(range.startContainer)) range.setStart(code, 0);
    if (!code.contains(range.endContainer)) range.setEnd(code, code.childNodes.length);
    event.clipboardData.setData('text/plain', range.cloneContents().textContent);
    event.preventDefault();
  });
  window.addEventListener('scroll', () => {
    if (restoring) return;
    if (!sectionTimer) sectionTimer = setTimeout(() => { sectionTimer = null; updateActiveHeading(); }, 50);
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(publishPosition, 80);
  }, {passive: true});
  const resizeObserver = new ResizeObserver(() => {
    clearTimeout(outlineFrame);
    outlineFrame = setTimeout(() => { syncJSONLineNumbers(); refreshHeadingOffsets(); reading.refresh(); search.relayout(); }, 60);
  });
  resizeObserver.observe(root);
  document.addEventListener('visibilitychange', () => { if (document.hidden) publishPosition(); });
  window.addEventListener('pagehide', publishPosition);
  window.luma = {render, navigateToHeading, findText: search.findText, moveSearch: search.move,
    getReadingPosition: () => reading.capture(true), restoreReadingPosition, setPreviewWidth, setReadingLayout, lastResult: null};
})();
