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

    showTask(el) {
      this.taskId = el.dataset.taskId
      this.taskName = el.dataset.taskName
      this.taskNote = el.dataset.taskNote
      this.taskInterval = el.dataset.taskInterval
      this.taskDueDate = el.dataset.taskDueDate
      this.taskUrgency = el.dataset.taskUrgency
      this.taskOverdue = el.dataset.taskOverdue === "true"
      this.mode = "task"
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
