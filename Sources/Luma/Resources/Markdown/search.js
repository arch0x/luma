/* Text ranges + a pointer-transparent overlay keep code, SVG and math DOM intact. */
(() => {
  'use strict';
  window.createLumaSearch = (root, callbacks) => {
    const MAX_MATCHES = 5000;
    const layer = document.createElement('div');
    layer.className = 'luma-search-layer'; layer.setAttribute('aria-hidden', 'true');
    document.body.append(layer);
    let groups = null, matches = [], rectangles = [];
    let query = '', current = -1, truncated = false, request = 0, error = null;
    let paintTimer, measureTimer;

    function result() {
      const values = {count: matches.length, current: current < 0 ? 0 : current + 1, truncated, error};
      callbacks.publish({kind: 'find', query, request, ...values});
      return values;
    }
    function reset() {
      groups = null; matches = []; rectangles = []; query = ''; current = -1; truncated = false; error = null;
      clearTimeout(paintTimer); clearTimeout(measureTimer);
      paintTimer = measureTimer = null;
      layer.replaceChildren();
    }
    function buildIndex() {
      const indexed = [];
      const visibility = new WeakMap();
      function visible(element) {
        if (!element || element === root) return true;
        if (visibility.has(element)) return visibility.get(element);
        const style = getComputedStyle(element);
        const value = style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) !== 0 && visible(element.parentElement);
        visibility.set(element, value);
        return value;
      }
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
        acceptNode(node) {
          const parent = node.parentElement;
          if (!node.nodeValue || !parent || parent.closest('script,style,button,summary,.heading-anchor,.code-toolbar,.diagram-toolbar,.content-tools,.katex-mathml,[hidden],details:not([open])')) return NodeFilter.FILTER_REJECT;
          if (parent.closest('svg') && !parent.closest('text,tspan')) return NodeFilter.FILTER_REJECT;
          return visible(parent) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
        }
      });
      while (walker.nextNode()) {
        const node = walker.currentNode;
        const element = node.parentElement.closest('p,h1,h2,h3,h4,h5,h6,li,td,th,pre,blockquote,tspan,text,.math-display,.image-status') || root;
        let group = indexed[indexed.length - 1];
        if (!group || group.element !== element) {
          group = {element, text: '', segments: [], clips: []}; indexed.push(group);
          for (let ancestor = element; ancestor && ancestor !== root; ancestor = ancestor.parentElement) {
            if (ancestor.matches('pre,.table-scroll,.diagram-canvas,.math-display')) group.clips.push(ancestor);
          }
        }
        const start = group.text.length;
        group.text += node.nodeValue;
        group.segments.push({node, start, end: group.text.length});
      }
      return indexed;
    }
    function segmentAt(segments, offset, end) {
      let low = 0, high = segments.length - 1;
      while (low < high) {
        const middle = (low + high) >> 1;
        if (end ? segments[middle].end < offset : segments[middle].end <= offset) low = middle + 1;
        else high = middle;
      }
      return segments[low];
    }
    function paint() {
      paintTimer = null;
      const fragment = document.createDocumentFragment();
      const top = window.scrollY - 120, bottom = window.scrollY + window.innerHeight + 120;
      const left = window.scrollX, right = left + window.innerWidth;
      for (const rect of rectangles) {
        if (rect.bottom < top || rect.top > bottom || rect.right <= left || rect.left >= right) continue;
        const hit = document.createElement('div');
        hit.className = rect.index === current ? 'search-hit search-hit-current' : 'search-hit';
        hit.dataset.match = String(rect.index);
        const x = Math.max(left, rect.left), end = Math.min(right, rect.right);
        hit.style.cssText = `left:${x}px;top:${rect.top}px;width:${end - x}px;height:${rect.bottom - rect.top}px`;
        fragment.append(hit);
      }
      layer.replaceChildren(fragment);
    }
    function measure() {
      measureTimer = null; rectangles = [];
      const clipRects = new Map();
      matches.forEach((match, index) => {
        const seen = new Set();
        for (const bounds of match.range.getClientRects()) {
          let left = bounds.left, right = bounds.right, top = bounds.top, bottom = bounds.bottom;
          for (const clip of match.group.clips) {
            if (!clipRects.has(clip)) clipRects.set(clip, clip.getBoundingClientRect());
            const box = clipRects.get(clip);
            left = Math.max(left, box.left); right = Math.min(right, box.left + clip.clientWidth);
            top = Math.max(top, box.top); bottom = Math.min(bottom, box.top + clip.clientHeight);
          }
          if (right - left < .2 || bottom - top < .2) continue;
          const key = [left, top, right, bottom].map(value => Math.round(value * 2)).join(',');
          if (seen.has(key)) continue;
          seen.add(key);
          rectangles.push({left: left + window.scrollX, right: right + window.scrollX, top: top + window.scrollY, bottom: bottom + window.scrollY, index});
        }
      });
      paint();
    }
    function firstRect(range) { return [...range.getClientRects()].find(rect => rect.width > .2 && rect.height > .2); }
    function reveal(match) {
      let changed = false;
      for (const clip of match.group.clips) {
        const rect = firstRect(match.range), box = clip.getBoundingClientRect();
        if (!rect) continue;
        const previous = clip.scrollLeft;
        if (rect.left < box.left + 8) clip.scrollLeft += rect.left - box.left - 8;
        else if (rect.right > box.left + clip.clientWidth - 8) clip.scrollLeft += rect.right - box.left - clip.clientWidth + 8;
        changed ||= previous !== clip.scrollLeft;
      }
      const rect = firstRect(match.range);
      if (rect) window.scrollTo({top: Math.max(0, rect.top + window.scrollY - Math.max(30, (window.innerHeight - rect.height) / 2)), behavior: 'auto'});
      callbacks.didNavigate();
      return changed;
    }
    function activate(index, scroll) {
      current = matches.length ? ((index % matches.length) + matches.length) % matches.length : -1;
      if (current >= 0 && scroll && reveal(matches[current])) measure();
      else paint();
    }
    function findText(value, options = {}) {
      query = String(value); request = Number(options.request ?? request);
      matches = []; rectangles = []; current = -1; truncated = false; error = null;
      layer.replaceChildren();
      if (!query.trim()) return result();
      if (query.length > 1024) { error = window.lumaUI.text('搜索词过长，请缩短关键词。'); return result(); }
      if (!groups) groups = buildIndex();
      const escapeRegex = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const pattern = query.split(/(\s+)/).map(part => /^\s+$/.test(part) ? '\\s+' : escapeRegex(part)).join('');
      const regex = new RegExp(pattern, 'giu');
      scan: for (const group of groups) {
        regex.lastIndex = 0;
        let match;
        while ((match = regex.exec(group.text))) {
          if (matches.length >= MAX_MATCHES) { truncated = true; break scan; }
          const start = segmentAt(group.segments, match.index, false);
          const endOffset = match.index + match[0].length;
          const end = segmentAt(group.segments, endOffset, true);
          const range = document.createRange();
          range.setStart(start.node, match.index - start.start);
          range.setEnd(end.node, endOffset - end.start);
          matches.push({range, group});
        }
      }
      measure();
      activate(Number(options.index) || 0, options.scroll !== false);
      return result();
    }
    function move(direction, options = {}) {
      request = Number(options.request ?? request);
      activate(current + (direction < 0 ? -1 : 1), true);
      return result();
    }
    function relayout(immediate = false) {
      if (!matches.length) return;
      clearTimeout(measureTimer);
      if (immediate === true) measure();
      else measureTimer = setTimeout(measure, 40);
    }
    document.addEventListener('scroll', event => {
      if (!matches.length) return;
      if (event.target instanceof Element && root.contains(event.target)) relayout();
      else if (!paintTimer) paintTimer = setTimeout(paint, 30);
    }, true);
    window.addEventListener('resize', relayout);
    root.addEventListener('toggle', () => {
      groups = null;
      if (query) findText(query, {index: Math.max(0, current), scroll: false, request});
    }, true);
    return {findText, move, reset, relayout, hide: () => layer.replaceChildren()};
  };
})();
