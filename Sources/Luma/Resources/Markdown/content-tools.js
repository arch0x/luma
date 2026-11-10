/* Reading controls operate on rendered content; the source is never rewritten. */
(() => {
  'use strict';
  const ui = window.lumaUI.text;
  window.createLumaContentTools = root => {
    let dialog = null;
    let cloneID = 0;
    function button(label, action, className = '') {
      const node = document.createElement('button');
      node.type = 'button'; node.textContent = label; node.className = className;
      node.addEventListener('click', action); return node;
    }
    function uniqueSVGIDs(element) {
      const prefix = `reading-${++cloneID}-`, ids = new Map();
      element.querySelectorAll('[id]').forEach(node => {
        ids.set(node.id, prefix + node.id); node.id = prefix + node.id;
      });
      const urls = value => value.replace(/url\(["']?#([^)'"\s]+)["']?\)/g, (match, id) => ids.has(id) ? `url(#${ids.get(id)})` : match);
      element.querySelectorAll('*').forEach(node => {
        for (const attr of [...node.attributes]) {
          let value = urls(attr.value);
          if ((attr.name === 'href' || attr.name === 'xlink:href') && value.startsWith('#') && ids.has(value.slice(1))) value = '#' + ids.get(value.slice(1));
          if (value !== attr.value) node.setAttribute(attr.name, value);
        }
        if (node.tagName.toLowerCase() === 'style') {
          node.textContent = urls(node.textContent).replace(/#[\w-]+/g, token => ids.has(token.slice(1)) ? '#' + ids.get(token.slice(1)) : token);
        }
      });
    }
    function close() { if (dialog) dialog.close(); }
    function expand(element, type) {
      close();
      const origin = document.activeElement;
      const label = ui({table: '表格', diagram: '图表', cell: '单元格'}[type]);
      const modal = document.createElement('dialog'); modal.className = 'reading-dialog';
      modal.setAttribute('aria-label', ui('{0}展开阅读', label));
      modal.dataset.contentType = type;
      const controls = document.createElement('div'); controls.className = 'reading-dialog-toolbar';
      const title = document.createElement('strong'); title.textContent = ui('{0} · 展开阅读', label);
      controls.append(title);
      const stage = document.createElement('div'); stage.className = 'reading-dialog-stage';
      const copy = element.cloneNode(true);
      copy.querySelectorAll('.code-toolbar,.diagram-toolbar,.content-tools,.diagram-source,.diagram-error').forEach(node => node.remove());
      uniqueSVGIDs(copy);
      stage.append(copy);
      let resize;
      if (type === 'diagram') {
        const svg = copy.querySelector('svg');
        if (svg) {
          const natural = svg.viewBox?.baseVal.width || parseFloat(svg.getAttribute('width')) || 800;
          let scale = 1, fitting = false;
          const label = document.createElement('span'); label.className = 'reading-scale';
          const apply = () => {
            svg.style.maxWidth = 'none'; svg.style.width = `${natural * scale}px`; svg.style.height = 'auto';
            label.textContent = `${Math.round(scale * 100)}%`;
          };
          const zoom = factor => { fitting = false; scale = Math.max(.25, Math.min(8, scale * factor)); apply(); };
          controls.append(button(ui('缩小'), () => zoom(1 / 1.25)), label, button(ui('放大'), () => zoom(1.25)),
            button(ui('适合窗口'), () => { fitting = true; resize(); }), button(ui('按文字大小'), () => { fitting = false; scale = 1; apply(); }));
          resize = () => { if (fitting) scale = Math.max(.05, Math.min(1, (stage.clientWidth - 48) / natural)); apply(); };
          window.addEventListener('resize', resize);
        }
      }
      controls.append(button(ui('关闭 · Esc'), () => modal.close(), 'reading-close'));
      modal.append(controls, stage); document.body.append(modal); dialog = modal;
      modal.addEventListener('close', () => {
        if (resize) window.removeEventListener('resize', resize);
        modal.remove(); if (dialog === modal) dialog = null;
        if (origin?.isConnected) origin.focus({preventScroll: true});
      }, {once: true});
      modal.showModal();
      if (resize) resize();
    }
    function install() {
      close();
      root.querySelectorAll('.table-scroll').forEach(wrapper => {
        const toolbar = document.createElement('div'); toolbar.className = 'content-tools';
        toolbar.append(button(ui('展开表格'), () => expand(wrapper, 'table'))); wrapper.prepend(toolbar);
        wrapper.querySelectorAll('td').forEach(cell => {
          cell.tabIndex = 0; cell.title = ui('双击或按 Return 查看完整单元格');
          const show = () => {
            const content = document.createElement('div');
            const text = document.createElement('pre'); text.className = 'full-cell'; text.textContent = cell.textContent;
            content.append(text); expand(content, 'cell');
          };
          cell.addEventListener('dblclick', show);
          cell.addEventListener('keydown', event => { if (event.key === 'Enter') { event.preventDefault(); show(); } });
        });
      });
      root.querySelectorAll('.diagram').forEach(figure => {
        const toolbar = figure.querySelector('.diagram-toolbar');
        if (figure.querySelector('svg')) toolbar.append(button(ui('展开图表'), () => expand(figure, 'diagram')));
      });
    }
    return {install, close};
  };
})();
