---
name: overtype
description: Use when working with OverType markdown editors - covers API, config options, DOM structure, view modes, and known workarounds
---

# OverType Markdown Editor

Loaded via CDN: `https://unpkg.com/overtype/dist/overtype.min.js`

Source: https://github.com/panphora/overtype

A transparent textarea over a rendered preview div. Monospace font required.
Markdown syntax stays visible in edit mode. ~95KB, zero dependencies.

## Constructor

```javascript
const [editor] = new OverType(target, options)
```

Always returns an array of instances, even for a single element.
`target` accepts a selector string, Element, NodeList, or array.

## Config Options

```javascript
{
  // Content
  value: "",
  placeholder: "Start typing...",

  // Typography
  fontSize: "14px",
  lineHeight: 1.6,
  fontFamily: "monospace",
  padding: "16px",

  // Theme: "solar", "cave", or custom object
  theme: "solar",
  colors: { h1: "#e63946", ... },

  // Auto-resize
  autoResize: false,
  minHeight: "100px",   // parsed with parseInt()
  maxHeight: null,

  // Behavior
  autofocus: false,
  smartLists: true,     // auto-continue lists on Enter
  toolbar: false,
  toolbarButtons: [],
  showStats: false,

  // Form integration
  textareaProps: { name: "content", required: true, maxLength: 500 },

  // Mobile (applied at <= 640px)
  mobile: { fontSize: "16px", padding: "12px", lineHeight: 1.5 },

  // Callbacks
  onChange: (value, instance) => {},
  onKeydown: (event, instance) => {},

  // Syntax highlighting
  codeHighlighter: (code, lang) => html,
}
```

## Instance Methods

```javascript
editor.getValue()                           // Get markdown string
editor.setValue(markdown)                    // Set content
editor.getCleanHTML()                       // HTML without OverType markup
editor.getRenderedHTML()                    // HTML with syntax markers
editor.getRenderedHTML({ cleanHTML: true }) // Same as getCleanHTML()
editor.getPreviewHTML()                     // Actual DOM from preview layer

editor.showNormalEditMode()   // Default WYSIWYG editing
editor.showPlainTextarea()    // Raw markdown, no preview
editor.showPreviewMode()      // Read-only preview, clickable links

editor.setTheme("cave")
editor.focus()
editor.blur()
editor.showStats(true)
editor.isInitialized()
editor.reinit(options)
editor.destroy()
```

## Static Methods

```javascript
OverType.init(target, options)        // Same as constructor
OverType.initFromData(".editor", {})  // Config via data-ot-* attributes
OverType.getInstance(element)
OverType.destroyAll()
OverType.setTheme("cave")
OverType.setCodeHighlighter(fn)
OverType.setCustomSyntax(fn)          // Must maintain 1:1 char alignment

// Standalone markdown parser (no editor instance needed)
OverType.MarkdownParser.parse(text)   // Returns rendered HTML
```

## DOM Structure

```
target (your element)
  .overtype-container
    .overtype-wrapper          ← position: relative
      .overtype-input          ← textarea, position: absolute, transparent
      .overtype-preview        ← rendered HTML, position: absolute
    .overtype-toolbar          ← if toolbar: true
    .overtype-stats            ← if showStats: true
```

## Internal CSS (relevant to sizing)

```css
.overtype-wrapper {
  min-height: 60px !important;   /* hardcoded default */
}
.overtype-input, .overtype-preview {
  height: 100% !important;
  position: absolute !important;
}
/* With autoResize: */
.overtype-container.overtype-auto-resize .overtype-wrapper {
  min-height: 60px !important;   /* still 60px */
}
```

Auto-resize measures `textarea.scrollHeight`, applies `Math.max(scrollHeight,
parseInt(minHeight))`, and sets `height` with `!important` on the wrapper,
textarea, and preview.

## Known Issues in This Project

### Wrapper min-height inflates small editors

The wrapper's `min-height: 60px !important` makes single-line editors too tall.
The `minHeight` config only floors the auto-resize calculation; it does not
override the CSS min-height.

Fix: override via inline style after init (inline `!important` beats stylesheet
`!important`), then re-measure scrollHeight.

### Global textarea styles inflate scrollHeight

The app's global `textarea { padding; border }` applies to OverType's internal
textarea, inflating the `scrollHeight` that auto-resize measures. Override with
inline styles on the textarea, then re-trigger sizing.

### Auto-resize re-inflates on input

OverType's auto-resize fires on every keystroke, undoing any height corrections.
Listen for `input` on the textarea and re-apply the fix each time.

### Pattern for compact OverType editors

```javascript
const [editor] = new OverType(el, {
  value: text,
  autoResize: true,
  minHeight: 14,
  fontSize: "11px",
  padding: "0 4px",
})

const wrapper = el.querySelector(".overtype-wrapper")
const textarea = el.querySelector("textarea")
const preview = el.querySelector(".overtype-preview")
if (wrapper && textarea) {
  wrapper.style.setProperty("min-height", "0", "important")
  textarea.style.setProperty("padding", "0 4px", "important")
  textarea.style.setProperty("border", "none", "important")
  const resize = () => {
    textarea.style.setProperty("height", "0", "important")
    const h = textarea.scrollHeight + "px"
    textarea.style.setProperty("height", h, "important")
    wrapper.style.setProperty("height", h, "important")
    if (preview) preview.style.setProperty("height", h, "important")
  }
  requestAnimationFrame(resize)
  textarea.addEventListener("input", () => requestAnimationFrame(resize))
}
```

## View Modes

`editor.showPreviewMode()` renders content read-only with clickable links.
`editor.showNormalEditMode()` returns to editing. However, preview mode uses
absolute positioning internally and does not auto-size to content.

For read-only markdown rendering without layout issues, use the standalone parser:

```javascript
el.innerHTML = OverType.MarkdownParser.parse(markdown)
```

## Limitations

- Images not supported (variable height breaks alignment)
- Monospace font required (variable-width breaks cursor alignment)
- Fixed font size across all content (no larger headers)
- Markdown syntax always visible in edit mode
- Links require Cmd/Ctrl+Click (direct click positions cursor)
