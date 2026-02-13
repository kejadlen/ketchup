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

  // Theme: "solar", "cave", or custom { name, colors } object
  theme: "solar",
  // Per-instance color overrides (merged into active theme):
  colors: { text: "#1a1a1a" },

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
OverType.setTheme("cave")            // or custom { name, colors } object
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

### Theme text color

The default "solar" theme uses `#0d3b66` (dark blue) for text. This project
overrides it globally before any instances are created:

```javascript
OverType.setTheme({ name: "ketchup", colors: { text: "#1a1a1a" } })
```

`setTheme` accepts a string (built-in name) or an object with `name` and
`colors`. Partial `colors` objects merge into the base solar theme. The
per-instance `colors` config option does not work reliably.

### Sizing

Three OverType behaviors compound to inflate small editors:

1. The wrapper's `min-height: 60px !important` makes single-line editors too
   tall. The `minHeight` config only floors the auto-resize calculation; it
   does not override the CSS rule.
2. The app's global `textarea { padding; border }` applies to OverType's
   internal textarea, inflating the `scrollHeight` that auto-resize reads.
3. OverType's auto-resize fires on every keystroke, re-applying the inflated
   height and undoing any corrections.

### `compactOverType(el)` in `public/js/app.js`

A helper at the top of `app.js` fixes all three. Call it on the container
element after `new OverType(el, ...)`:

```javascript
const [editor] = new OverType(el, {
  value: text,
  autoResize: true,
  minHeight: 14,
  padding: "0 4px",
})
const resize = compactOverType(el)
```

It zeros the wrapper min-height, strips textarea padding and border, measures
true `scrollHeight` on the next frame, and hooks `input` to re-measure after
each keystroke. Returns a resize function for manual re-measurement (e.g.
after toggling `readOnly`), or `null` if the expected DOM nodes aren't found.

The element must be visible when the next animation frame fires, or
`scrollHeight` reads as 0. If the container is hidden behind an `x-show` that
hasn't toggled yet, defer the call:

```javascript
requestAnimationFrame(() => compactOverType(el))
```

Pass `padding: "0 4px"` in the OverType config to match the inline override on
the textarea — otherwise the preview layer keeps OverType's default padding
and the two layers render at different offsets.

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
