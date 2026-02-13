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

  Alpine.store("sidebar", {
    mode: "",
    taskId: null,
    seriesId: null,
    taskName: "",
    taskNote: "",
    taskInterval: "",
    intervalCount: 1,
    intervalUnit: "day",
    taskDueDate: "",
    taskUrgency: "",
    taskOverdue: false,
    completedTasks: [],
    editing: false,
    addingNoteId: null,
    _seriesNoteEditor: null,
    _resizeSeriesNote: null,
    _noteEditors: [],

    init() {
      const seriesId = sessionStorage.getItem("showSeries")
      if (seriesId) {
        sessionStorage.removeItem("showSeries")
        const el = document.querySelector(`[data-series-id="${seriesId}"]`)
        if (el) this.showTask(el)
      }
    },

    showTask(el) {
      this.taskId = el.dataset.taskId
      this.seriesId = el.dataset.seriesId
      this.taskName = el.dataset.taskName
      this.taskNote = el.dataset.taskNote
      this.taskInterval = el.dataset.taskInterval
      this.intervalCount = parseInt(el.dataset.intervalCount, 10) || 1
      this.intervalUnit = el.dataset.intervalUnit || "day"
      this.taskDueDate = el.dataset.taskDueDate
      this.taskUrgency = el.dataset.taskUrgency
      this.taskOverdue = el.dataset.taskOverdue === "true"
      this._noteEditors.forEach((e) => e.destroy())
      this._noteEditors = []
      this.completedTasks = []
      this.addingNoteId = null
      this.editing = false
      this.mode = "task"

      requestAnimationFrame(() => this._initSeriesNote())

      fetch(`/series/${el.dataset.seriesId}/completed`)
        .then((r) => r.json())
        .then((data) => (this.completedTasks = data))
    },

    showForm() {
      this.mode = "form"
      this.taskId = null
    },

    toggleForm() {
      if (this.mode === "form") {
        this.mode = ""
        this.taskId = null
      } else {
        this.showForm()
      }
    },

    startEditing() {
      this.editing = true
      const ta = document.querySelector("#series-note-detail textarea")
      if (ta) {
        ta.style.pointerEvents = ""
        ta.readOnly = false
        ta.focus()
      }
      if (this._resizeSeriesNote) requestAnimationFrame(this._resizeSeriesNote)
    },

    stopEditing() {
      this._saveSeriesNote()
      const ta = document.querySelector("#series-note-detail textarea")
      if (ta) {
        ta.style.pointerEvents = "none"
        ta.readOnly = true
      }
      this.editing = false
      if (this._resizeSeriesNote) requestAnimationFrame(this._resizeSeriesNote)
    },

    initNoteEditor(el, taskId, initialNote) {
      if (!el) return
      const [editor] = new OverType(el, {
        value: initialNote,
        placeholder: "Add a note...",
        autoResize: true,
        minHeight: 14,
        fontSize: "11px",
        padding: "0 4px",
      })

      this._noteEditors.push(editor)
      compactOverType(el)

      const textarea = el.querySelector("textarea")
      if (textarea) {
        if (this.addingNoteId === taskId) textarea.focus()
        textarea.addEventListener("blur", () => {
          const note = editor.getValue().trim()
          const ct = this.completedTasks.find((t) => t.id === taskId)
          if (this.addingNoteId === taskId) this.addingNoteId = null
          if (!ct || (note || null) === (ct.note || null)) return

          ct.note = note || null
          fetch(`/tasks/${taskId}/note`, {
            method: "PATCH",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: `note=${encodeURIComponent(note)}`,
          })
        })
      }
    },

    _initSeriesNote() {
      const el = document.getElementById("series-note-detail")
      if (!el) return

      if (this._seriesNoteEditor) {
        this._seriesNoteEditor.destroy()
        this._seriesNoteEditor = null
      }
      el.innerHTML = ""

      const [editor] = new OverType(el, {
        value: this.taskNote || "",
        placeholder: "Series note...",
        autoResize: true,
        minHeight: 14,
        padding: "0 4px",
      })
      this._seriesNoteEditor = editor

      // Store resize so startEditing/stopEditing can re-measure after
      // toggling pointer-events and readOnly.
      this._resizeSeriesNote = compactOverType(el)

      const ta = el.querySelector("textarea")
      if (ta) {
        ta.style.pointerEvents = "none"
        ta.readOnly = true
        ta.addEventListener("blur", () => this._saveSeriesNote())
      }
    },

    _saveSeriesNote() {
      if (!this._seriesNoteEditor) return
      const note = this._seriesNoteEditor.getValue().trim()
      if (note === (this.taskNote || "").trim()) return

      this.taskNote = note
      this.saveSeriesField("note", note)
      const card = document.querySelector(`[data-series-id="${this.seriesId}"]`)
      if (card) {
        card.dataset.taskNote = note
        card.dataset.taskName = note.split("\n")[0]?.trim() || note
        const nameEl = card.querySelector(".task-name")
        if (nameEl) nameEl.textContent = card.dataset.taskName
      }
    },

    saveSeriesField(field, value) {
      if (!this.seriesId) return
      fetch(`/series/${this.seriesId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `${encodeURIComponent(field)}=${encodeURIComponent(value)}`,
      })
    },

    saveInterval() {
      if (!this.seriesId) return
      const count = this.intervalCount
      const unit = this.intervalUnit
      fetch(`/series/${this.seriesId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `interval_count=${encodeURIComponent(count)}&interval_unit=${encodeURIComponent(unit)}`,
      }).then(() => {
        const label = `Every ${count} ${count === 1 ? unit : unit + "s"}`
        this.taskInterval = label
        const card = document.querySelector(`[data-series-id="${this.seriesId}"]`)
        if (card) {
          card.dataset.taskInterval = label
          card.dataset.intervalCount = count
          card.dataset.intervalUnit = unit
        }
      })
    },

    completeTask(taskId, seriesId) {
      fetch(`/tasks/${taskId}/complete`, { method: "POST" })
        .then((r) => {
          if (!r.ok) throw new Error()
          sessionStorage.setItem("showSeries", seriesId)
          window.location.reload()
        })
    },
  })

  new OverType("#series-note-editor", {
    placeholder: "What needs doing...",
    textareaProps: { name: "note", required: true },
    autoResize: true,
  })

  Alpine.data("upcoming", () => ({
    showEmpty: localStorage.getItem("upcoming-show-empty") !== "false",

    init() {
      this.$watch("showEmpty", (value) => {
        localStorage.setItem("upcoming-show-empty", value)
      })
    },
  }))
})
