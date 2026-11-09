/* Offline syntax extensions for Luma's document formats and component source. */
(() => {
  'use strict';
  hljs.registerLanguage('gitignore', h => ({
    name: '.gitignore',
    contains: [
      h.COMMENT(/^#/, /$/),
      {scope: 'literal', match: /\\[^\r\n]/},
      {scope: 'keyword', match: /^!/},
      {scope: 'symbol', match: /\*\*?|\?|\[(?:\\.|[^\]\\\r\n])+\]/},
      {scope: 'punctuation', match: /\//}
    ]
  }));
  hljs.registerLanguage('dotenv', h => ({
    name: '.env',
    contains: [
      h.COMMENT(/^\s*#/, /$/),
      {
        begin: /^\s*(?:export\s+)?[a-zA-Z_][\w.-]*\s*=/, returnBegin: true, end: /$/,
        contains: [
          {scope: 'keyword', match: /\bexport\b/},
          {scope: 'attr', match: /[a-zA-Z_][\w.-]*(?=\s*=)/},
          {begin: /=/, end: /$/, excludeBegin: true, contains: [
            h.COMMENT(/#/, /$/),
            {scope: 'string', begin: /"/, end: /"/, contains: [h.BACKSLASH_ESCAPE, {scope: 'variable', begin: /\$\{/, end: /\}/}]},
            {scope: 'string', begin: /'/, end: /'/},
            {scope: 'variable', match: /\$\{[^}\r\n]+\}|\$[a-zA-Z_]\w*/},
            {scope: 'literal', match: /\b(?:true|false)\b/},
            {scope: 'number', match: /\b\d+(?:\.\d+)?\b/},
            {scope: 'string', match: /[^\s#"'$]+/}
          ]}
        ]
      }
    ]
  }));
  hljs.registerLanguage('dockerignore', h => ({
    name: '.dockerignore',
    contains: [
      h.COMMENT(/^#/, /$/),
      {scope: 'keyword', match: /^!/},
      {scope: 'symbol', match: /\*\*?|\?|\[[^\]\r\n]+\]/},
      {scope: 'punctuation', match: /\//}
    ]
  }));
  hljs.registerLanguage('dockerfile', h => ({
    name: 'Dockerfile', aliases: ['docker'], case_insensitive: true,
    contains: [
      {scope: 'meta', begin: /^\s*#\s*(?:syntax|escape|check)\s*=/, end: /$/},
      h.COMMENT(/^\s*#/, /$/),
      {scope: 'keyword', match: /^\s*(?:ADD|ARG|CMD|COPY|ENTRYPOINT|ENV|EXPOSE|FROM|HEALTHCHECK|LABEL|MAINTAINER|ONBUILD|RUN|SHELL|STOPSIGNAL|USER|VOLUME|WORKDIR)\b/},
      {scope: 'keyword', match: /\bAS\b/},
      h.END_SAME_AS_BEGIN({scope: 'string', begin: /<<-?["']?(\w+)["']?/, end: /^\t*(\w+)[ \t]*$/}),
      {scope: 'variable', variants: [{begin: /\$\{[^}\n]+\}/}, {begin: /\$[a-zA-Z_][\w]*/}]},
      {scope: 'attr', match: /--[a-z][\w-]*(?==|\s|$)/},
      {scope: 'attr', match: /\b[a-z_][\w]*(?==)/},
      h.QUOTE_STRING_MODE, h.APOS_STRING_MODE,
      {scope: 'number', match: /\b\d+(?:\.\d+)*\b/}
    ]
  }));
  hljs.registerLanguage('jsonc', h => h.inherit(h.getLanguage('json'), {
    name: 'JSONC', aliases: [],
    contains: [h.C_LINE_COMMENT_MODE, h.C_BLOCK_COMMENT_MODE, ...h.getLanguage('json').contains]
  }));
  hljs.registerLanguage('jsonl', h => h.inherit(h.getLanguage('json'), {name: 'JSON Lines', aliases: ['ndjson']}));

  function component(h, svelte) {
    const quoted = [h.APOS_STRING_MODE, h.QUOTE_STRING_MODE, {begin: /`/, end: /`/, contains: [h.BACKSLASH_ESCAPE]}];
    const braces = {begin: /\{/, end: /\}/, contains: [...quoted, 'self'], subLanguage: 'javascript'};
    const script = (language, attribute) => ({
      begin: new RegExp('<script\\b(?=[\\s>])' + (attribute || '') + '[^>]*>', 'i'),
      end: /<\/script\s*>/i, excludeBegin: true, excludeEnd: true, subLanguage: language
    });
    const style = (language, attribute) => ({
      begin: new RegExp('<style\\b(?=[\\s>])' + (attribute || '') + '[^>]*>', 'i'),
      end: /<\/style\s*>/i, excludeBegin: true, excludeEnd: true, subLanguage: language
    });
    const lang = value => '(?=[^>]*\\blang\\s*=\\s*["\\\']' + value + '["\\\'])';
    const expression = {
      begin: svelte ? /\{/ : /\{\{/, end: svelte ? /\}/ : /\}\}/,
      excludeBegin: true, excludeEnd: true, subLanguage: 'javascript',
      contains: [
        ...quoted, h.C_LINE_COMMENT_MODE, h.C_BLOCK_COMMENT_MODE, braces,
        ...(svelte ? [{scope: 'meta', match: /[#:/@](?:if|else|each|await|then|catch|key|snippet|html|debug|const|render)\b/}] : [])
      ]
    };
    return {
      name: svelte ? 'Svelte' : 'Vue', subLanguage: 'xml',
      contains: [
        h.COMMENT(/<!--/, /-->/),
        script('typescript', lang('(?:ts|typescript|tsx)')), script('javascript'),
        style('less', lang('less')), style('scss', lang('scss')), style('css'), expression
      ]
    };
  }
  hljs.registerLanguage('vue', h => component(h, false));
  hljs.registerLanguage('svelte', h => component(h, true));
})();
