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
    taskName: "",
    taskNote: "",
    taskInterval: "",
    taskDueDate: "",
    taskUrgency: "",
    taskOverdue: false,
    completedTasks: [],
    addingNoteId: null,

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
      this.taskName = el.dataset.taskName
      this.taskNote = el.dataset.taskNote
      this.taskInterval = el.dataset.taskInterval
      this.taskDueDate = el.dataset.taskDueDate
      this.taskUrgency = el.dataset.taskUrgency
      this.taskOverdue = el.dataset.taskOverdue === "true"
      this.completedTasks = []
      this.addingNoteId = null
      this.mode = "task"

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

      // OverType's wrapper has min-height: 60px !important and its auto-resize
      // runs during init — before we can intervene — locking in an inflated
      // height. The global textarea styles (padding, border) also inflate
      // scrollHeight. Fix: override those styles, then re-measure in the next
      // frame once the overrides have taken effect.
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
        // OverType's auto-resize also fires on input, re-inflating the height.
        textarea.addEventListener("input", () => requestAnimationFrame(resize))
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
