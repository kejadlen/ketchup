---
name: alpine
description: Use when working with Alpine.js directives, components, reactivity, or client-side behavior in Phlex views or public/js/app.js
---

# Alpine.js

Lightweight reactive framework. Declares behavior inline via HTML directives.
No build step - loaded via CDN with SRI hashes in `views/layout.rb`.

Version: 3.15.8 (core), 3.15.0 (persist plugin).

Source: https://alpinejs.dev

## Directives

| Directive | Purpose |
|-----------|---------|
| `x-data` | Declares reactive scope. All other directives require a parent `x-data`. |
| `x-bind` (`:`) | Sets HTML attributes from expressions. Object syntax for class/style. |
| `x-on` (`@`) | Listens to DOM events. Supports modifiers. |
| `x-text` | Sets `textContent` from expression. |
| `x-html` | Sets `innerHTML`. Only use on trusted content (XSS risk). |
| `x-model` | Two-way binding for inputs. |
| `x-show` | Toggles visibility via CSS `display`. Works with `x-transition`. |
| `x-if` | Conditional rendering. Adds/removes from DOM. Must wrap in `<template>`. No transitions. |
| `x-for` | Loops. Must wrap in `<template>`. Single root element required. |
| `x-transition` | Animate show/hide. Apply to same element as `x-show`. |
| `x-effect` | Reactive side-effect. Re-runs when any referenced property changes. |
| `x-ref` | Names an element for `$refs` access. |
| `x-cloak` | Hides element until Alpine initializes. Requires CSS: `[x-cloak] { display: none !important; }` |
| `x-init` | Runs on initialization. Works outside `x-data`. |
| `x-modelable` | Exposes property as `x-model` target for parent-child binding. |
| `x-teleport` | Moves content to another DOM location. Takes CSS selector. |
| `x-ignore` | Prevents Alpine from processing subtree. |
| `x-id` | Scopes `$id()` generation. Takes array of names. |

## Magic Properties

| Property | Purpose |
|----------|---------|
| `$el` | Current DOM element. |
| `$refs` | Object of elements marked with `x-ref`. Static refs only in v3. |
| `$store` | Access global stores registered via `Alpine.store()`. |
| `$watch` | `$watch('prop', (val, old) => ...)`. Deep-watches objects. Avoid mutating watched prop in callback. |
| `$dispatch` | `$dispatch('name', detail)`. Fires `CustomEvent`. Bubbles up DOM. Use `.window` for siblings. |
| `$nextTick` | `$nextTick(() => ...)` or `await $nextTick()`. Runs after reactive DOM update. |
| `$root` | Closest ancestor with `x-data`. |
| `$data` | Current scope as object. Useful for passing to external functions. |
| `$id` | `$id('name')` generates unique ID. `$id('name', suffix)` for keyed IDs in loops. |
| `$event` | Native event object inside `x-on` handlers. |
| `$persist` | Persist plugin. Wraps initial value for localStorage persistence. |

## Globals

Register components and stores inside `alpine:init`:

```javascript
document.addEventListener("alpine:init", () => {
    Alpine.data("dropdown", () => ({
        open: false,
        toggle() { this.open = !this.open },
        init() { /* auto-called on mount */ },
        destroy() { /* auto-called on removal */ },
    }))

    Alpine.store("darkMode", {
        on: false,
        init() { /* runs after registration */ },
        toggle() { this.on = !this.on },
    })

    Alpine.bind("SomeButton", () => ({
        type: "button",
        ["@click"]() { this.doSomething() },
        [":disabled"]() { return this.shouldDisable },
    }))
})
```

`Alpine.data()` components accept parameters: `x-data="dropdown(true)"`.

Access magic properties via `this` inside `Alpine.data()`: `this.$watch(...)`,
`this.$refs`, etc.

Access stores outside Alpine: `Alpine.store("darkMode").toggle()`.

## x-data

Inline object or registered name. Methods, getters, `init()`, and `destroy()`
all supported. Inner `x-data` scopes shadow outer properties.

```html
<div x-data="{ open: false, toggle() { this.open = !this.open } }">
    <button @click="toggle">Toggle</button>
    <div x-show="open">Content</div>
</div>
```

Empty component: `x-data` or `x-data="{}"`.

## x-bind Class and Style

```html
<!-- Ternary -->
<div :class="open ? 'visible' : 'hidden'">

<!-- Object syntax (preserves original classes) -->
<div :class="{ 'hidden': !show, 'active': isActive }">

<!-- Short-circuit -->
<div :class="closed && 'hidden'">

<!-- Style object -->
<div :style="{ color: 'red', display: 'flex' }">
```

## x-on Modifiers

| Modifier | Effect |
|----------|--------|
| `.prevent` | `preventDefault()` |
| `.stop` | `stopPropagation()` |
| `.outside` | Fires only for clicks outside element. Only evaluates when visible. |
| `.window` | Listens on `window`. |
| `.document` | Listens on `document`. |
| `.once` | Handler fires once. |
| `.self` | Only if event originated on this element. |
| `.debounce` | Default 250ms. Custom: `.debounce.500ms`. |
| `.throttle` | Default 250ms. Custom: `.throttle.750ms`. |
| `.passive` | Passive listener for scroll/touch performance. |
| `.capture` | Capture phase. |
| `.camel` | Converts kebab event name to camelCase. |
| `.dot` | Converts dashes to dots in event name. |

Keyboard: `.enter`, `.escape`, `.space`, `.tab`, `.shift`, `.ctrl`, `.cmd`,
`.alt`, `.meta`, `.up`, `.down`, `.left`, `.right`. Other keys in kebab-case
(`.page-down`). Chainable: `@keyup.shift.enter`.

## x-model Modifiers

| Modifier | Effect |
|----------|--------|
| `.lazy` | Syncs on blur. |
| `.change` | Syncs on blur if value changed. |
| `.number` | Casts to number. |
| `.boolean` | Casts to boolean. |
| `.debounce` | Default 250ms. Custom: `.debounce.500ms`. |
| `.throttle` | Default 250ms. Custom: `.throttle.750ms`. |
| `.fill` | Populates property from input's `value` attribute. |

Combinable: `.blur.enter` syncs on both events.

Programmatic access: `el._x_model.get()` / `el._x_model.set(value)`.

## x-for

Must use `<template>`. Single root element inside.

```html
<template x-for="item in items" :key="item.id">
    <li x-text="item.name"></li>
</template>

<!-- With index -->
<template x-for="(item, index) in items">
    <li x-text="index + ': ' + item.name"></li>
</template>

<!-- Range -->
<template x-for="i in 10">
    <span x-text="i"></span>
</template>
```

## x-transition

Apply to same element as `x-show`.

```html
<!-- Default: fade + scale, 150ms enter, 75ms leave -->
<div x-show="open" x-transition>

<!-- Modifiers -->
<div x-show="open" x-transition.opacity.duration.300ms>
<div x-show="open" x-transition.scale.80.origin.top>

<!-- CSS classes for full control -->
<div x-show="open"
     x-transition:enter="transition ease-out duration-300"
     x-transition:enter-start="opacity-0 scale-90"
     x-transition:enter-end="opacity-100 scale-100"
     x-transition:leave="transition ease-in duration-150"
     x-transition:leave-start="opacity-100 scale-100"
     x-transition:leave-end="opacity-0 scale-90">
```

## Persist Plugin

Wraps values for automatic localStorage persistence across page reloads.

```javascript
// Basic
{ count: $persist(0) }

// Custom key
{ count: $persist(0).as("my-count") }

// Session storage (clears on tab close)
{ count: $persist(0).using(sessionStorage) }

// In Alpine.data(), use regular function for this.$persist
Alpine.data("dropdown", function () {
    return { open: this.$persist(false) }
})

// In stores
Alpine.store("darkMode", {
    on: Alpine.$persist(true).as("darkMode_on"),
})
```

## Patterns in This Project

### Phlex Keyword Arguments

Phlex views pass Alpine directives as Ruby keyword arguments with string keys:

```ruby
div("x-data": "{ editing: false }") do
  button("x-show": "!editing", "x-on:click": "editing = true")
  div("x-show": "editing", "x-cloak": true)
end
```

### Component Registration

All reusable components are registered in `public/js/app.js` inside the
`alpine:init` listener. Components used: `intervalEditor`, `dueDateEditor`,
`historyNote`, `completedDateEditor`.

### Object Spread for Multiple Components

Merge multiple registered components on one element:

```ruby
div("x-data": "{ ...historyNote(#{series_id}, #{task_id}, #{has_note}), ...completedDateEditor(#{series_id}, #{task_id}, '#{date}') }")
```

### x-show + x-cloak

Pair `x-cloak` with `x-show` on initially-hidden elements to prevent flash of
content before Alpine initializes.

### Custom Events

`$dispatch('start-editing')` / `$dispatch('stop-editing')` for communication
between the edit section scope and panel editors in `app.js`.

### init() Is a Lifecycle Hook

`init()` inside `x-data` or `Alpine.data()` auto-runs on mount. Do not use
`init` as a regular method name — it will fire unexpectedly.
