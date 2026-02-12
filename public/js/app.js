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
})
