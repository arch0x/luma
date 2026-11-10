/* Semantic block anchors survive width changes and ordinary document insertions. */
(() => {
  'use strict';
  window.createLumaReading = (root, callbacks) => {
    let blocks = [], headings = [];
    const unit = value => Math.min(1, Math.max(0, Number(value) || 0));
    function signature(text) {
      let first = 2166136261, second = 5381;
      for (let index = 0; index < text.length; index++) {
        const code = text.charCodeAt(index);
        first = Math.imul(first ^ code, 16777619) >>> 0;
        second = (Math.imul(second, 33) ^ code) >>> 0;
      }
      return `${text.length}-${first.toString(36)}-${second.toString(36)}`;
    }
    function blockText(element) {
      if (element.dataset.mathSource) return element.dataset.mathSource;
      if (element.matches('.code-block')) return element.querySelector('pre')?.textContent || '';
      if (element.matches('.diagram')) return element.querySelector('.diagram-source pre')?.textContent || '';
      return callbacks.label(element);
    }
    function refresh() {
      blocks.forEach(block => { block.top = block.element.getBoundingClientRect().top + window.scrollY; });
      const end = root.getBoundingClientRect().bottom + window.scrollY;
      blocks.forEach((block, index) => { block.span = Math.max(1, (blocks[index + 1]?.top ?? end) - block.top); });
      headings = callbacks.headings().map(element => ({element, id: element.id, top: element.getBoundingClientRect().top + window.scrollY}));
      headings.forEach((heading, index) => { heading.span = Math.max(1, (headings[index + 1]?.top ?? end) - heading.top); });
    }
    function build() {
      const counts = new Map();
      let section = '';
      blocks = [...root.children].map(element => {
        if (/^H[1-6]$/.test(element.tagName)) section = element.id;
        const text = blockText(element).replace(/\s+/g, ' ').trim();
        const base = `${section}/${element.tagName}/${signature(text)}`;
        const occurrence = counts.get(base) || 0; counts.set(base, occurrence + 1);
        return {element, key: `${base}/${occurrence}`, label: Array.from(text).slice(0, 80).join(''), top: 0, span: 1};
      });
      refresh();
    }
    function at(items, position) {
      let low = 0, high = items.length - 1, selected = -1;
      while (low <= high) {
        const middle = (low + high) >> 1;
        if (items[middle].top <= position) { selected = middle; low = middle + 1; }
        else high = middle - 1;
      }
      return selected >= 0 ? items[selected] : null;
    }
    function capture(fresh = false) {
      if (fresh) refresh();
      const maximum = Math.max(0, root.getBoundingClientRect().bottom + window.scrollY - window.innerHeight);
      const offset = Math.min(maximum, Math.max(0, window.scrollY));
      const block = at(blocks, offset + 24) || blocks[0];
      const heading = at(headings, offset + 28);
      const headingTitle = heading ? callbacks.label(heading.element) : '';
      const title = block?.label && block.label !== headingTitle ? `${headingTitle ? headingTitle + ' · ' : ''}${block.label}` : headingTitle || window.lumaUI.text('阅读位置');
      return {offset, progress: maximum ? unit(offset / maximum) : 0,
        blockKey: block?.key || '', blockProgress: block ? unit((offset + 24 - block.top) / block.span) : 0,
        headingID: heading?.id || '', headingProgress: heading ? unit((offset + 24 - heading.top) / heading.span) : 0,
        title: Array.from(title).slice(0, 160).join('')};
    }
    function captureHeading(id) {
      refresh();
      const heading = headings.find(item => item.id === id);
      if (!heading) return null;
      const block = blocks.find(item => item.element === heading.element);
      const maximum = Math.max(0, root.getBoundingClientRect().bottom + window.scrollY - window.innerHeight);
      const offset = Math.max(0, heading.top - 24);
      return {offset, progress: maximum ? unit(offset / maximum) : 0,
        blockKey: block?.key || '', blockProgress: 0, headingID: id, headingProgress: 0,
        title: Array.from(callbacks.label(heading.element)).slice(0, 160).join('')};
    }
    function restore(location) {
      refresh();
      const maximum = Math.max(0, root.getBoundingClientRect().bottom + window.scrollY - window.innerHeight);
      let target = Math.max(0, Number(location.offset) || 0);
      if (!target && !Number(location.progress)) target = 0;
      else if (Number(location.progress) >= .9999) target = maximum;
      else {
        const block = blocks.find(item => item.key === location.blockKey);
        const heading = headings.find(item => item.id === location.headingID);
        if (block) target = block.top + unit(location.blockProgress) * block.span - 24;
        else if (heading) target = heading.top + unit(location.headingProgress) * heading.span - 24;
        else if (Number.isFinite(location.progress)) target = unit(location.progress) * maximum;
      }
      window.scrollTo({top: Math.min(maximum, Math.max(0, target)), behavior: 'auto'});
      return true;
    }
    return {build, refresh, capture, captureHeading, restore};
  };
})();
