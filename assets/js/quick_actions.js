const fold = text => text.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()

const platformKey = "grana:shortcut-platform"
const detectedPlatform = navigator.userAgentData?.platform || navigator.platform
let shortcutPlatform = /Mac|iPhone|iPad/i.test(detectedPlatform) ? "mac" : "other"

try {
  const savedPlatform = localStorage.getItem(platformKey)
  if (!detectedPlatform && ["mac", "other"].includes(savedPlatform)) shortcutPlatform = savedPlatform
  localStorage.setItem(platformKey, shortcutPlatform)
} catch {
  // A identificação continua funcionando quando o navegador bloqueia o armazenamento.
}

document.documentElement.dataset.shortcutPlatform = shortcutPlatform

const QuickActions = {
  mounted() {
    this.dialog = this.el.querySelector("dialog")
    this.input = this.el.querySelector("#quick-actions-query")
    this.trigger = this.el.querySelector("#quick-actions-open")
    this.saved = this.el.querySelector("#quick-actions-saved")
    this.status = this.el.querySelector("#quick-actions-status")
    this.loadId = 0
    this.options = []

    const shortcut = shortcutPlatform === "mac" ? "⌘ K" : "Ctrl K"
    this.trigger.title = `Busca rápida (${shortcut})`

    this.onKeydown = event => this.keydown(event)
    this.onInput = () => this.filter()
    this.onClick = event => this.click(event)
    this.onClose = () => this.finishClose()
    this.onCancel = event => { event.preventDefault(); this.close() }
    this.viewport = window.visualViewport
    this.onViewportChange = () => this.updateViewport()
    this.onPointerMove = event => {
      const option = event.target.closest("[data-quick-action]")
      const index = this.options.indexOf(option)
      if (index >= 0 && index !== this.activeIndex) this.select(index, false)
    }

    window.addEventListener("keydown", this.onKeydown, true)
    window.addEventListener("resize", this.onViewportChange)
    this.viewport?.addEventListener("resize", this.onViewportChange)
    this.viewport?.addEventListener("scroll", this.onViewportChange)
    this.el.addEventListener("click", this.onClick)
    this.input.addEventListener("input", this.onInput)
    this.dialog.addEventListener("close", this.onClose)
    this.dialog.addEventListener("cancel", this.onCancel)
    this.dialog.addEventListener("pointermove", this.onPointerMove)
  },

  destroyed() {
    this.close(false)
    this.finishClose()
    window.removeEventListener("keydown", this.onKeydown, true)
    window.removeEventListener("resize", this.onViewportChange)
    this.viewport?.removeEventListener("resize", this.onViewportChange)
    this.viewport?.removeEventListener("scroll", this.onViewportChange)
    this.el.removeEventListener("click", this.onClick)
    this.input.removeEventListener("input", this.onInput)
    this.dialog.removeEventListener("close", this.onClose)
    this.dialog.removeEventListener("cancel", this.onCancel)
    this.dialog.removeEventListener("pointermove", this.onPointerMove)
  },

  disconnected() {
    if (this.dialog.open) this.unavailable()
  },

  reconnected() {
    if (this.dialog.open) this.loadSearches()
  },

  open() {
    this.returnFocus = document.activeElement
    this.restoreFocus = true
    this.previousOverflow = document.documentElement.style.overflow
    this.wasOpen = true
    this.input.value = ""
    this.dialog.showModal()
    this.updateViewport()
    document.documentElement.style.overflow = "hidden"
    this.input.focus()
    this.loadSearches()
  },

  updateViewport() {
    if (!this.dialog.open) return
    this.dialog.style.setProperty("--quick-actions-viewport-height", `${this.viewport?.height || window.innerHeight}px`)
    this.dialog.style.setProperty("--quick-actions-viewport-top", `${this.viewport?.offsetTop || 0}px`)
  },

  close(restoreFocus = true) {
    this.restoreFocus = restoreFocus
    if (this.dialog.open) this.dialog.close()
    this.finishClose()
  },

  finishClose() {
    if (!this.wasOpen) return
    this.wasOpen = false
    this.loadId++
    clearTimeout(this.loadTimer)
    document.documentElement.style.overflow = this.previousOverflow
    this.input.setAttribute("aria-expanded", "false")
    this.input.removeAttribute("aria-activedescendant")
    if (this.restoreFocus && this.returnFocus?.isConnected) this.returnFocus.focus()
  },

  loadSearches() {
    const loadId = ++this.loadId
    clearTimeout(this.loadTimer)
    this.saved.querySelectorAll("[data-quick-action]").forEach(option => option.remove())
    this.status.textContent = "Carregando buscas salvas…"
    this.filter()
    this.loadTimer = setTimeout(() => {
      if (loadId === this.loadId) this.unavailable()
    }, 5000)

    this.pushEvent("quick_actions:load", {}, ({searches}) => {
      if (loadId !== this.loadId || !this.dialog.open) return
      clearTimeout(this.loadTimer)
      const template = this.el.querySelector("#quick-actions-saved-template")
      searches.forEach(search => {
        const option = template.content.firstElementChild.cloneNode(true)
        option.id = `quick-action-saved-${search.id}`
        option.href = search.path
        option.dataset.keywords = "busca salva pesquisa"
        option.querySelector("[data-quick-label]").textContent = search.name
        this.saved.appendChild(option)
      })
      this.status.textContent = ""
      this.filter()
    })
  },

  unavailable() {
    clearTimeout(this.loadTimer)
    this.loadId++
    this.status.textContent = "Buscas salvas indisponíveis. Feche e abra para tentar novamente."
  },

  filter() {
    const terms = fold(this.input.value.trim()).split(/\s+/).filter(Boolean)
    this.options = []
    this.el.querySelectorAll("[data-quick-action]").forEach(option => {
      const text = fold(`${option.querySelector("[data-quick-label]").textContent} ${option.dataset.keywords}`)
      const visible = terms.length ? terms.every(term => text.includes(term)) : option.dataset.suggested === "true"
      option.hidden = !visible
      option.setAttribute("aria-selected", "false")
      if (visible) this.options.push(option)
    })
    this.el.querySelectorAll("[data-quick-group]").forEach(group => {
      group.hidden = !group.querySelector("[data-quick-action]:not([hidden])")
    })
    this.el.querySelector("#quick-actions-empty").hidden = this.options.length > 0
    this.input.setAttribute("aria-expanded", String(this.options.length > 0))
    this.select(0, false)
  },

  select(index, scroll = true) {
    this.options.forEach(option => option.setAttribute("aria-selected", "false"))
    this.activeIndex = index
    const option = this.options[index]
    if (!option) {
      this.input.removeAttribute("aria-activedescendant")
      return
    }
    option.setAttribute("aria-selected", "true")
    this.input.setAttribute("aria-activedescendant", option.id)
    if (scroll) option.scrollIntoView({block: "nearest"})
  },

  keydown(event) {
    if (event.isComposing) return
    if ((event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === "k") {
      event.preventDefault()
      event.stopPropagation()
      if (event.repeat) return
      if (this.dialog.open) this.close()
      else this.open()
      return
    }
    if (!this.dialog.open) return
    if (event.key === "Escape") {
      event.preventDefault()
      event.stopPropagation()
      this.close()
    } else if (event.key === "Tab") {
      const closeButton = this.el.querySelector("#quick-actions-close")
      if (!event.shiftKey && event.target === this.input) {
        event.preventDefault()
        closeButton.focus()
      } else if (event.shiftKey && event.target === closeButton) {
        event.preventDefault()
        this.input.focus()
      }
    } else if (event.target === this.input) {
      this.inputKeydown(event)
    }
  },

  inputKeydown(event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      if (this.options.length) this.select((this.activeIndex + step + this.options.length) % this.options.length)
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.options[this.activeIndex]?.click()
    }
  },

  click(event) {
    if (event.target.closest("#quick-actions-open")) this.open()
    else if (event.target.closest("#quick-actions-close")) this.close()
    else if (event.target.closest("[data-quick-action]")) this.close(false)
    else if (event.target === this.dialog) {
      const rect = this.dialog.getBoundingClientRect()
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) this.close()
    }
  },
}

export default QuickActions
