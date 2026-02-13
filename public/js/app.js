// OverType hardcodes `min-height: 60px !important` on `.overtype-wrapper`
// and runs auto-resize during construction — before callers can intervene —
// locking in an inflated height. The app's global textarea styles (padding,
// border) further inflate `scrollHeight`, which auto-resize reads.
//
// This function corrects both problems after `new OverType(el, ...)`:
//
//  1. Zeros the wrapper's min-height (inline `!important` beats the
//     stylesheet's `!important` at equal specificity).
//  2. Strips the textarea padding and border that inflate scrollHeight.
//  3. On the next frame — once the style overrides have taken effect —
//     collapses the textarea to height 0, reads scrollHeight for the true
//     content height, and sets that height on the wrapper, textarea, and
//     preview so all three layers agree.
//  4. Hooks the textarea's `input` event to repeat step 3, because
//     OverType's own auto-resize fires on every keystroke and re-inflates
//     the height.
//
// The element must be visible (participating in layout) by the time the
// next animation frame fires, or scrollHeight will read as 0. If the
// container is hidden at creation time — for example behind an Alpine
// x-show that hasn't toggled yet — defer the call with
// requestAnimationFrame so the browser lays it out first.
//
// Returns a resize function for manual re-measurement (e.g. after toggling
// readOnly or pointer-events), or null if the expected DOM isn't found.
function compactOverType(el) {
  const wrapper = el.querySelector(".overtype-wrapper")
  const textarea = el.querySelector("textarea")
  const preview = el.querySelector(".overtype-preview")
  if (!wrapper || !textarea) return null

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

  return resize
}

function saveSeriesField(seriesId, field, value) {
  return fetch(`/series/${seriesId}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `${encodeURIComponent(field)}=${encodeURIComponent(value)}`,
  })
}

document.addEventListener("alpine:init", () => {
  Alpine.data("sortable", () => ({
    sort: localStorage.getItem("sort") || "urgency",

    init() {
      this.$watch("sort", (value) => {
        localStorage.setItem("sort", value)
        this.reorder()
      })
      if (this.sort !== "urgency") {
        this.$nextTick(() => this.reorder())
      }
    },

    reorder() {
      const ul = this.$el.querySelector(".task-list")
      if (!ul) return

      const items = [...ul.querySelectorAll("li[data-urgency]")]
      if (this.sort === "urgency") {
        items.sort((a, b) => parseFloat(b.dataset.urgency) - parseFloat(a.dataset.urgency))
      } else {
        items.sort((a, b) => a.dataset.dueDate.localeCompare(b.dataset.dueDate))
      }
      items.forEach((li) => ul.appendChild(li))
    },
  }))

  Alpine.data("intervalEditor", (seriesId, initialCount, initialUnit) => ({
    count: initialCount,
    unit: initialUnit,

    save() {
      fetch(`/series/${seriesId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `interval_count=${encodeURIComponent(this.count)}&interval_unit=${encodeURIComponent(this.unit)}`,
      })
    },
  }))

  Alpine.data("dueDateEditor", (seriesId, initialDate) => ({
    dueDate: initialDate,

    save() {
      saveSeriesField(seriesId, "due_date", this.dueDate)
    },
  }))

  Alpine.data("historyNoteEditor", () => ({
    _editor: null,

    show(el) {
      el.style.display = ""
    },

    init() {
      const el = this.$el
      const taskId = el.dataset.taskId
      const initialNote = el.dataset.value || ""

      if (this._editor) return

      const [editor] = new OverType(el, {
        value: initialNote,
        placeholder: "Add a note...",
        autoResize: true,
        minHeight: 14,
        fontSize: "11px",
        padding: "0 4px",
      })

      this._editor = editor
      compactOverType(el)

      const textarea = el.querySelector("textarea")
      if (textarea) {
        if (!initialNote) textarea.focus()
        textarea.addEventListener("blur", () => {
          const note = editor.getValue().trim()
          if (note === (initialNote || "").trim()) return

          el.dataset.value = note
          fetch(`/tasks/${taskId}/note`, {
            method: "PATCH",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: `note=${encodeURIComponent(note)}`,
          })
        })
      }
    },
  }))

  // Series note detail editor — initialized when a series is selected
  const noteDetail = document.getElementById("series-note-detail")
  if (noteDetail) {
    const seriesId = noteDetail.dataset.seriesId
    const initialNote = noteDetail.dataset.value || ""

    const [editor] = new OverType(noteDetail, {
      value: initialNote,
      placeholder: "Series note...",
      autoResize: true,
      minHeight: 14,
      padding: "0 4px",
    })

    const resizeNote = compactOverType(noteDetail)

    const ta = noteDetail.querySelector("textarea")
    if (ta) {
      ta.style.pointerEvents = "none"
      ta.readOnly = true

      ta.addEventListener("blur", () => {
        const note = editor.getValue().trim()
        if (note === (initialNote || "").trim()) return
        saveSeriesField(seriesId, "note", note)
      })

      document.addEventListener("start-editing", () => {
        ta.style.pointerEvents = ""
        ta.readOnly = false
        ta.focus()
        if (resizeNote) requestAnimationFrame(resizeNote)
      })

      document.addEventListener("stop-editing", () => {
        const note = editor.getValue().trim()
        if (note !== (initialNote || "").trim()) {
          saveSeriesField(seriesId, "note", note)
        }
        ta.style.pointerEvents = "none"
        ta.readOnly = true
        if (resizeNote) requestAnimationFrame(resizeNote)
      })
    }
  }

  // New series form editor
  const newNoteEl = document.getElementById("series-note-editor")
  if (newNoteEl) {
    new OverType("#series-note-editor", {
      placeholder: "What needs doing...",
      textareaProps: { name: "note", required: true },
      autoResize: true,
    })
  }

  Alpine.data("upcoming", () => ({
    showEmpty: localStorage.getItem("upcoming-show-empty") !== "false",

    init() {
      this.$watch("showEmpty", (value) => {
        localStorage.setItem("upcoming-show-empty", value)
      })
    },
  }))
})
