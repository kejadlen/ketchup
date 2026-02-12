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
    editingNoteId: null,
    editingNoteText: "",

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
      this.editingNoteId = null
      this.editingNoteText = ""
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

    editNote(taskId, currentNote) {
      if (this.editingNoteId === taskId) {
        this.editingNoteId = null
        this.editingNoteText = ""
        return
      }
      this.editingNoteId = taskId
      this.editingNoteText = currentNote
    },

    saveNote(taskId) {
      const note = this.editingNoteText.trim()
      fetch(`/tasks/${taskId}/note`, {
        method: "PATCH",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `note=${encodeURIComponent(note)}`,
      })
        .then((r) => r.json())
        .then(() => {
          const ct = this.completedTasks.find((t) => t.id === taskId)
          if (ct) ct.note = note || null
          this.editingNoteId = null
          this.editingNoteText = ""
        })
    },

    cancelNote() {
      this.editingNoteId = null
      this.editingNoteText = ""
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

  Alpine.data("upcoming", () => ({
    showEmpty: localStorage.getItem("upcoming-show-empty") !== "false",

    init() {
      this.$watch("showEmpty", (value) => {
        localStorage.setItem("upcoming-show-empty", value)
      })
    },
  }))
})
