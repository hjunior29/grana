import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/grana"
import topbar from "../vendor/topbar"

// --- Theme ---
const visualStyles = new Set(["default", "signal", "bossa"])

const setTheme = (theme) => {
  if (theme === "system") {
    localStorage.removeItem("phx:theme")
    document.documentElement.removeAttribute("data-theme")
  } else {
    localStorage.setItem("phx:theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
  }
}

const setVisualStyle = (style) => {
  const visualStyle = visualStyles.has(style) ? style : "default"

  if (visualStyle === "default") {
    localStorage.removeItem("phx:visual-style")
    document.documentElement.removeAttribute("data-visual-style")
  } else {
    localStorage.setItem("phx:visual-style", visualStyle)
    document.documentElement.setAttribute("data-visual-style", visualStyle)
  }
}

setTheme(localStorage.getItem("phx:theme") || "system")
setVisualStyle(localStorage.getItem("phx:visual-style") || "default")
window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"))
window.addEventListener("storage", (e) => e.key === "phx:visual-style" && setVisualStyle(e.newValue || "default"))
window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme))
window.addEventListener("phx:set-visual-style", (e) => setVisualStyle(e.target.dataset.phxVisualStyle))

// --- Tooltip Utility ---
const tooltipStyle = "position:absolute;z-index:50;padding:8px 12px;border-radius:8px;background:color-mix(in oklch, var(--color-base-300) 88%, transparent);backdrop-filter:blur(12px);color:var(--color-base-content);box-shadow:0 14px 36px color-mix(in oklch, var(--color-base-content) 20%, transparent);font-size:13px;pointer-events:none;white-space:nowrap;display:none;border:1px solid var(--grana-border)"

function showTooltip(container, event, html) {
  let tip = container.querySelector(".chart-tooltip")
  if (!tip) {
    tip = document.createElement("div")
    tip.className = "chart-tooltip"
    tip.setAttribute("style", tooltipStyle)
    container.style.position = "relative"
    container.appendChild(tip)
  }
  tip.innerHTML = html
  tip.style.display = "block"
  const rect = container.getBoundingClientRect()
  let left = event.clientX - rect.left + 12
  let top = event.clientY - rect.top - 10
  // Prevent overflow right
  if (left + tip.offsetWidth > rect.width - 8) {
    left = event.clientX - rect.left - tip.offsetWidth - 12
  }
  tip.style.left = left + "px"
  tip.style.top = top + "px"
}

function hideTooltip(container) {
  const tip = container.querySelector(".chart-tooltip")
  if (tip) tip.style.display = "none"
}

function fmtBRL(val) {
  return "R$ " + val.toLocaleString("pt-BR", {minimumFractionDigits: 2, maximumFractionDigits: 2})
}

function pct(val, total) {
  return total > 0 ? ((val / total) * 100).toFixed(1) : "0"
}

// Escapes a value for safe interpolation into HTML/SVG text and double-quoted
// attributes. Category names/colors are user-controlled, so any value coming
// from server data must pass through this before being put into innerHTML.
function escapeHtml(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}
window.escapeHtml = escapeHtml

// Expose tooltip utilities for inline scripts (landing page)
window.showTooltip = showTooltip
window.hideTooltip = hideTooltip
window.fmtBRL = fmtBRL

// --- Chart Hooks ---

const CategoryChart = {
  mounted() {
    this.renderChart()
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-cat-name]")
      if (!target) return hideTooltip(this.el)
      const name = target.dataset.catName
      const value = parseFloat(target.dataset.catValue)
      const total = parseFloat(target.dataset.catTotal)
      showTooltip(this.el, e, `<strong>${escapeHtml(name)}</strong><br>${fmtBRL(value)} · ${pct(value, total)}%`)
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
    this.el.addEventListener("click", (e) => {
      const target = e.target.closest("[data-cat-url]")
      if (target) this.pushEvent("chart-navigate", {url: target.dataset.catUrl})
    })
  },
  updated() { this.renderChart() },
  renderChart() {
    const data = JSON.parse(this.el.dataset.categories || "[]")
    if (!data.length) return

    const total = data.reduce((sum, d) => sum + d.value, 0)
    if (total === 0) return

    const size = 200
    const cx = size / 2
    const cy = size / 2
    const radius = 80
    const innerRadius = 55

    let svg = `<svg viewBox="0 0 ${size} ${size}" class="w-48 h-48 mx-auto mb-4">`
    let startAngle = -Math.PI / 2

    data.forEach(item => {
      const sliceAngle = Math.min((item.value / total) * 2 * Math.PI, 2 * Math.PI - 0.001)
      const endAngle = startAngle + sliceAngle
      const largeArc = sliceAngle > Math.PI ? 1 : 0

      const x1 = cx + radius * Math.cos(startAngle)
      const y1 = cy + radius * Math.sin(startAngle)
      const x2 = cx + radius * Math.cos(endAngle)
      const y2 = cy + radius * Math.sin(endAngle)
      const ix1 = cx + innerRadius * Math.cos(endAngle)
      const iy1 = cy + innerRadius * Math.sin(endAngle)
      const ix2 = cx + innerRadius * Math.cos(startAngle)
      const iy2 = cy + innerRadius * Math.sin(startAngle)

      const urlAttr = item.url ? ` data-cat-url="${escapeHtml(item.url)}"` : ""
      svg += `<path d="M ${x1} ${y1} A ${radius} ${radius} 0 ${largeArc} 1 ${x2} ${y2} L ${ix1} ${iy1} A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${ix2} ${iy2} Z" fill="${escapeHtml(item.color)}" opacity="0.85" class="transition-all hover:opacity-100 cursor-pointer" style="transform-origin:${cx}px ${cy}px" data-cat-name="${escapeHtml(item.name)}" data-cat-value="${item.value}" data-cat-total="${total}"${urlAttr}></path>`
      startAngle = endAngle
    })

    const formattedTotal = fmtBRL(total)
    svg += `<text x="${cx}" y="${cy - 6}" text-anchor="middle" class="fill-base-content text-xs opacity-50">Total</text>`
    svg += `<text x="${cx}" y="${cy + 12}" text-anchor="middle" class="fill-base-content text-sm font-semibold">${formattedTotal}</text>`
    svg += `</svg>`

    const existing = this.el.querySelector(".chart-svg")
    if (existing) {
      existing.innerHTML = svg
    } else {
      const div = document.createElement("div")
      div.className = "chart-svg"
      div.innerHTML = svg
      this.el.insertBefore(div, this.el.firstChild)
    }
  }
}

const DailyChart = {
  mounted() {
    this.renderChart()
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-day-date]")
      if (!target) return hideTooltip(this.el)
      showTooltip(this.el, e, `<strong>${escapeHtml(target.dataset.dayDate)}</strong><br>${fmtBRL(parseFloat(target.dataset.dayValue))}`)
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
    this.el.addEventListener("click", (e) => {
      const target = e.target.closest("[data-day-url]")
      if (target) this.pushEvent("chart-navigate", {url: target.dataset.dayUrl})
    })
  },
  updated() { this.renderChart() },
  renderChart() {
    const data = JSON.parse(this.el.dataset.daily || "[]")
    if (!data.length) return

    const maxVal = Math.max(...data.map(d => d.value))
    if (maxVal === 0) return

    const width = 500
    const height = 200
    const padding = {top: 20, right: 10, bottom: 30, left: 10}
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom
    const barWidth = Math.max(4, (chartWidth / data.length) - 2)

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-48 mb-4">`

    data.forEach((item, i) => {
      const barHeight = (item.value / maxVal) * chartHeight
      const x = padding.left + (i * (chartWidth / data.length)) + 1
      const y = padding.top + chartHeight - barHeight

      const urlAttr = item.url ? ` data-day-url="${escapeHtml(item.url)}"` : ""
      const barFill = this.el.dataset.barFill || "fill-primary"
      svg += `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" rx="2" class="${barFill} opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-day-date="${escapeHtml(item.date)}" data-day-value="${item.value}"${urlAttr}></rect>`

      if (data.length <= 15 || i % Math.ceil(data.length / 10) === 0) {
        svg += `<text x="${x + barWidth / 2}" y="${height - 5}" text-anchor="middle" class="fill-base-content text-[8px] opacity-40">${escapeHtml(item.date)}</text>`
      }
    })

    svg += `</svg>`

    const existing = this.el.querySelector(".chart-svg")
    if (existing) {
      existing.innerHTML = svg
    } else {
      const div = document.createElement("div")
      div.className = "chart-svg"
      div.innerHTML = svg
      this.el.insertBefore(div, this.el.firstChild)
    }
  }
}

const CalendarHeatmap = {
  mounted() {
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-calendar-month]")
      if (!target) return hideTooltip(this.el)

      const month = target.dataset.calendarMonth
      const uploads = target.dataset.calendarUploads
      const types = target.dataset.calendarTypes
      const count = parseInt(target.dataset.calendarCount || "0", 10)
      const uploadColor = count > 0
        ? `var(--grana-calendar-${Math.min(count, 3)})`
        : "color-mix(in oklch, var(--color-base-content) 58%, transparent)"

      showTooltip(
        this.el,
        e,
        `<div style="display:flex;flex-direction:column;gap:4px">
          <strong>${escapeHtml(month)}</strong>
          <span style="font-weight:700;color:${uploadColor}">${escapeHtml(uploads)}</span>
          <span style="opacity:.72">${escapeHtml(types)}</span>
        </div>`
      )
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
  }
}

const AutoDismiss = {
  mounted() {
    this.timer = setTimeout(() => {
      const kind = this.el.id.replace("flash-", "")
      this.pushEvent("lv:clear-flash", { key: kind })
      this.el.style.opacity = "0"
      this.el.style.transform = "translateX(100%)"
      setTimeout(() => this.el.remove(), 500)
    }, 5000)
  },
  destroyed() {
    clearTimeout(this.timer)
  }
}

const NotificationStack = {
  mounted() {
    this.handleEvent("notify", ({ kind, message }) => {
      this.addNotification(kind, message)
    })
  },
  addNotification(kind, message) {
    const id = `notif-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`
    const colorClass = kind === "error" ? "alert-error" : "alert-info"
    const iconSvg = kind === "error"
      ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5 shrink-0"><path fill-rule="evenodd" d="M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-8-5a.75.75 0 0 1 .75.75v4.5a.75.75 0 0 1-1.5 0v-4.5A.75.75 0 0 1 10 5Zm0 10a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" clip-rule="evenodd" /></svg>`
      : `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5 shrink-0"><path fill-rule="evenodd" d="M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-7-4a1 1 0 1 1-2 0 1 1 0 0 1 2 0ZM9 9a.75.75 0 0 0 0 1.5h.253a.25.25 0 0 1 .244.304l-.459 2.066A1.75 1.75 0 0 0 10.747 15H11a.75.75 0 0 0 0-1.5h-.253a.25.25 0 0 1-.244-.304l.459-2.066A1.75 1.75 0 0 0 9.253 9H9Z" clip-rule="evenodd" /></svg>`

    const el = document.createElement("div")
    el.id = id
    el.className = "pointer-events-auto transition-all duration-500"
    el.style.opacity = "0"
    el.style.transform = "translateX(100%)"
    el.innerHTML = `
      <div class="alert ${colorClass} w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap shadow-lg">
        ${iconSvg}
        <div><p>${this.escapeHtml(message)}</p></div>
        <div class="flex-1"></div>
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5 opacity-40 group-hover:opacity-70"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" /></svg>
        </button>
      </div>
    `

    el.querySelector("button").addEventListener("click", () => this.dismiss(el))
    this.el.appendChild(el)

    requestAnimationFrame(() => {
      el.style.opacity = "1"
      el.style.transform = "translateX(0)"
    })

    setTimeout(() => this.dismiss(el), 5000)
  },
  dismiss(el) {
    if (!el.parentNode) return
    el.style.opacity = "0"
    el.style.transform = "translateX(100%)"
    setTimeout(() => el.remove(), 500)
  },
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}

const IncomeExpensesChart = {
  mounted() {
    this.renderChart()
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-ie-label]")
      if (!target) return hideTooltip(this.el)
      const label = target.dataset.ieLabel
      const type = target.dataset.ieType
      const value = parseFloat(target.dataset.ieValue)
      const incomeLabel = this.el.dataset.incomeLabel || "Receitas"
      const expensesLabel = this.el.dataset.expensesLabel || "Despesas"
      const typeLabel = type === "income" ? incomeLabel : expensesLabel
      showTooltip(this.el, e, `<strong>${escapeHtml(label)}</strong><br>${escapeHtml(typeLabel)}: ${fmtBRL(value)}`)
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
    this.el.addEventListener("click", (e) => {
      const target = e.target.closest("[data-ie-url]")
      if (target) this.pushEvent("chart-navigate", {url: target.dataset.ieUrl})
    })
  },
  updated() { this.renderChart() },
  renderChart() {
    const data = JSON.parse(this.el.dataset.monthly || "[]")
    if (!data.length) return

    const maxVal = Math.max(...data.map(d => Math.max(d.income, d.expenses)))
    if (maxVal === 0) return

    const width = 1000
    const height = 350
    const padding = {top: 20, right: 10, bottom: 35, left: 10}
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom
    const groupWidth = chartWidth / data.length
    const barGap = 3
    const barWidth = Math.max(8, (groupWidth - barGap) * 0.42)

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-80 sm:h-96">`

    data.forEach((item, i) => {
      const groupX = padding.left + (i * groupWidth)
      const pairWidth = barWidth * 2 + barGap
      const x = groupX + (groupWidth - pairWidth) / 2
      const incomeH = (item.income / maxVal) * chartHeight
      const expenseH = (item.expenses / maxVal) * chartHeight

      const incUrl = item.income_url ? ` data-ie-url="${escapeHtml(item.income_url)}"` : ""
      const expUrl = item.expenses_url ? ` data-ie-url="${escapeHtml(item.expenses_url)}"` : ""

      const incFill = this.el.dataset.incomeFill || "fill-success"
      const expFill = this.el.dataset.expensesFill || "fill-error"
      const safeLabel = escapeHtml(item.label)
      svg += `<rect x="${x}" y="${padding.top + chartHeight - incomeH}" width="${barWidth}" height="${incomeH}" rx="2" class="${incFill} opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-ie-label="${safeLabel}" data-ie-type="income" data-ie-value="${item.income}"${incUrl}></rect>`
      svg += `<rect x="${x + barWidth + barGap}" y="${padding.top + chartHeight - expenseH}" width="${barWidth}" height="${expenseH}" rx="2" class="${expFill} opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-ie-label="${safeLabel}" data-ie-type="expenses" data-ie-value="${item.expenses}"${expUrl}></rect>`
      svg += `<text x="${groupX + groupWidth / 2}" y="${height - 8}" text-anchor="middle" class="fill-base-content text-[10px] opacity-50">${safeLabel}</text>`
    })

    svg += `</svg>`
    const incLabel = this.el.dataset.incomeLabel || "Receitas"
    const expLabel = this.el.dataset.expensesLabel || "Despesas"
    const incColor = this.el.dataset.incomeColor || "bg-success/70"
    const expColor = this.el.dataset.expensesColor || "bg-error/70"
    svg += `<div class="flex justify-center gap-6 text-xs opacity-60 mt-1"><span class="flex items-center gap-1"><span class="w-3 h-3 rounded-sm ${incColor}"></span> ${incLabel}</span><span class="flex items-center gap-1"><span class="w-3 h-3 rounded-sm ${expColor}"></span> ${expLabel}</span></div>`

    const existing = this.el.querySelector(".chart-svg")
    if (existing) {
      existing.innerHTML = svg
    } else {
      const div = document.createElement("div")
      div.className = "chart-svg"
      div.innerHTML = svg
      this.el.insertBefore(div, this.el.firstChild)
    }
  }
}

const ProjectionChart = {
  mounted() {
    this.renderChart()
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-proj-label]")
      if (!target) return hideTooltip(this.el)
      showTooltip(this.el, e, `<strong>${escapeHtml(target.dataset.projLabel)}</strong><br>${fmtBRL(parseFloat(target.dataset.projValue))}`)
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
  },
  updated() { this.renderChart() },
  renderChart() {
    const data = JSON.parse(this.el.dataset.projections || "[]")
    if (!data.length) return

    const maxVal = Math.max(...data.map(d => d.value))
    if (maxVal === 0) return

    const width = 700
    const height = 220
    const padding = {top: 20, right: 10, bottom: 35, left: 10}
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom
    const barWidth = Math.max(8, (chartWidth / data.length) - 4)

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-56">`

    data.forEach((item, i) => {
      const barHeight = (item.value / maxVal) * chartHeight
      const x = padding.left + (i * (chartWidth / data.length)) + 2
      const y = padding.top + chartHeight - barHeight

      const safeLabel = escapeHtml(item.label)
      svg += `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" rx="2" class="fill-warning opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-proj-label="${safeLabel}" data-proj-value="${item.value}"></rect>`
      svg += `<text x="${x + barWidth / 2}" y="${height - 8}" text-anchor="middle" class="fill-base-content text-[9px] opacity-50">${safeLabel}</text>`
    })

    svg += `</svg>`

    const existing = this.el.querySelector(".chart-svg")
    if (existing) {
      existing.innerHTML = svg
    } else {
      const div = document.createElement("div")
      div.className = "chart-svg"
      div.innerHTML = svg
      this.el.insertBefore(div, this.el.firstChild)
    }
  }
}

const ProgressBar = {
  mounted() {
    this.realProgress = parseFloat(this.el.dataset.progress) || 0
    this.displayed = 0
    this.isAI = this.el.dataset.ai === "true"
    this.bar = this.el.querySelector("progress")
    this.pctEl = this.el.querySelector("[data-pct]")
    this.tick()
  },
  updated() {
    const newTarget = parseFloat(this.el.dataset.progress) || 0
    const newAI = this.el.dataset.ai === "true"
    if (newTarget !== this.realProgress || newAI !== this.isAI) {
      this.realProgress = newTarget
      this.isAI = newAI
      this.tick()
    }
  },
  tick() {
    if (this.raf) cancelAnimationFrame(this.raf)
    const step = () => {
      const target = this.realProgress
      if (this.displayed < target) {
        const diff = target - this.displayed
        this.displayed += Math.max(0.5, diff * 0.15)
        if (this.displayed > target) this.displayed = target
        this.update()
        this.raf = requestAnimationFrame(step)
      } else if (this.isAI && target < 100) {
        const total = parseInt(this.el.dataset.total) || 1
        const slotSize = 100 / total
        const ceiling = target + slotSize * 0.92
        const remaining = ceiling - this.displayed
        if (remaining > 0.01) {
          this.displayed += Math.max(0.01, remaining * 0.007)
          this.update()
        }
        this.raf = requestAnimationFrame(step)
      } else if (this.displayed < 100) {
        this.raf = requestAnimationFrame(step)
      }
    }
    this.raf = requestAnimationFrame(step)
  },
  update() {
    this.bar.value = this.displayed
    if (this.pctEl) this.pctEl.textContent = Math.round(this.displayed) + "%"
  },
  destroyed() {
    if (this.raf) cancelAnimationFrame(this.raf)
  }
}

const DropZone = {
  mounted() {
    let counter = 0
    this.el.addEventListener("dragenter", (e) => {
      e.preventDefault()
      counter++
      this.el.classList.add("border-success", "bg-success/5", "scale-[1.01]")
      this.el.classList.remove("border-base-content/20")
    })
    this.el.addEventListener("dragover", (e) => e.preventDefault())
    this.el.addEventListener("dragleave", () => {
      counter--
      if (counter === 0) {
        this.el.classList.remove("border-success", "bg-success/5", "scale-[1.01]")
        this.el.classList.add("border-base-content/20")
      }
    })
    this.el.addEventListener("drop", () => {
      counter = 0
      this.el.classList.remove("border-success", "bg-success/5", "scale-[1.01]")
      this.el.classList.add("border-base-content/20")
    })
  }
}

const ActiveNav = {
  mounted() {
    this.highlight()
    this._onNav = () => requestAnimationFrame(() => this.highlight())
    window.addEventListener("phx:navigate", this._onNav)
  },
  destroyed() {
    window.removeEventListener("phx:navigate", this._onNav)
  },
  highlight() {
    const path = window.location.pathname
    this.el.querySelectorAll("a[href]").forEach(a => {
      const href = a.getAttribute("href")
      const active = path === href || (href !== "/" && path.startsWith(href))
      a.classList.toggle("menu-active", active)
    })
  }
}

const LandingAIDemo = {
  mounted() {
    this.textarea = this.el.querySelector("[data-ai-textarea]")
    this.button = this.el.querySelector("[data-ai-button]")
    this.inputPhase = this.el.querySelector("[data-ai-input]")
    this.loadingPhase = this.el.querySelector("[data-ai-loading]")
    this.resultPhase = this.el.querySelector("[data-ai-result]")
    this._destroyed = false
    this._running = false

    this.observer = new IntersectionObserver(([entry]) => {
      if (this._destroyed) return
      if (entry.isIntersecting && !this._running) {
        this._running = true
        this.runLoop()
      } else if (!entry.isIntersecting) {
        this._running = false
        this.reset()
      }
    }, { threshold: 0.2 })
    this.observer.observe(this.el)
  },

  destroyed() {
    this._destroyed = true
    this._running = false
    if (this.observer) this.observer.disconnect()
  },

  reset() {
    this.textarea.value = ""
    this.inputPhase.style.opacity = "1"
    this.inputPhase.style.transform = "translateY(0)"
    this.loadingPhase.style.opacity = "0"
    this.loadingPhase.style.transform = "translateY(6px)"
    this.resultPhase.style.opacity = "0"
    this.resultPhase.style.transform = "translateY(6px)"
  },

  async runLoop() {
    while (this._running && !this._destroyed) {
      await this.runSequence()
      if (!this._running || this._destroyed) break
      await this.sleep(1500)
    }
  },

  async runSequence() {
    const text = "Onde posso economizar nesse mês?"

    // Reset all phases
    this.reset()

    // Initial pause
    await this.sleep(800)
    if (!this._running) return

    // 1. Typing animation — character by character
    for (let i = 0; i < text.length; i++) {
      if (!this._running) return
      this.textarea.value = text.substring(0, i + 1)
      await this.sleep(50 + Math.random() * 50)
    }

    // Pause after typing
    await this.sleep(600)
    if (!this._running) return

    // 2. Button click simulation — press/release
    this.button.classList.add("btn-active")
    this.button.style.transform = "scale(0.95)"
    await this.sleep(150)
    this.button.classList.remove("btn-active")
    this.button.style.transform = ""

    // Short pause before fade
    await this.sleep(400)
    if (!this._running) return

    // 3. Fade out input card
    this.inputPhase.style.opacity = "0"
    this.inputPhase.style.transform = "translateY(-6px)"
    await this.sleep(500)
    if (!this._running) return

    // 4. Fade in loading skeleton
    this.loadingPhase.style.opacity = "1"
    this.loadingPhase.style.transform = "translateY(0)"
    await this.sleep(3000)
    if (!this._running) return

    // 5. Fade out loading
    this.loadingPhase.style.opacity = "0"
    this.loadingPhase.style.transform = "translateY(-6px)"
    await this.sleep(500)
    if (!this._running) return

    // 6. Fade in result
    this.resultPhase.style.opacity = "1"
    this.resultPhase.style.transform = "translateY(0)"
    await this.sleep(4000)
    if (!this._running) return

    // 7. Fade out result
    this.resultPhase.style.opacity = "0"
    this.resultPhase.style.transform = "translateY(-3px)"
    await this.sleep(600)
  },

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }
}

const CurrencyInput = {
  mounted() {
    this.hiddenInput = this.el.querySelector("input[type=hidden]")
    this.display = this.el.querySelector("input[data-currency-display]")

    // Initialize from existing value
    if (this.hiddenInput.value) {
      const cents = Math.round(parseFloat(this.hiddenInput.value) * 100)
      if (cents > 0) this.display.value = this.formatCents(cents)
    }

    this.display.addEventListener("input", (e) => {
      const digits = e.target.value.replace(/\D/g, "")
      const cents = parseInt(digits || "0", 10)
      if (cents === 0) {
        this.display.value = ""
        this.hiddenInput.value = ""
      } else {
        this.display.value = this.formatCents(cents)
        this.hiddenInput.value = (cents / 100).toFixed(2)
      }
    })

    this.display.addEventListener("keydown", (e) => {
      // Allow: backspace, delete, tab, escape, enter, arrows
      if ([8, 9, 13, 27, 46, 37, 39].includes(e.keyCode)) return
      // Block non-digit keys (allow numpad too)
      if ((e.keyCode < 48 || e.keyCode > 57) && (e.keyCode < 96 || e.keyCode > 105)) {
        e.preventDefault()
      }
    })
  },

  formatCents(cents) {
    const reais = Math.floor(cents / 100)
    const centavos = (cents % 100).toString().padStart(2, "0")
    const formatted = reais.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".")
    return formatted + "," + centavos
  }
}

const Hooks = {
  ...colocatedHooks,
  CategoryChart,
  DailyChart,
  CalendarHeatmap,
  IncomeExpensesChart,
  ProjectionChart,
  AutoDismiss,
  NotificationStack,
  DropZone,
  ProgressBar,
  ActiveNav,
  LandingAIDemo,
  CurrencyInput,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

topbar.config({barColors: {0: "oklch(68% 0.16 166)"}, shadowColor: "rgba(0, 0, 0, .18)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()

window.liveSocket = liveSocket

// Close <details> dropdowns when clicking outside or navigating
document.addEventListener("click", (e) => {
  document.querySelectorAll("details.dropdown[open]").forEach(details => {
    if (!details.contains(e.target)) {
      details.removeAttribute("open")
    }
  })
})
window.addEventListener("phx:navigate", () => {
  document.querySelectorAll("details.dropdown[open]").forEach(d => d.removeAttribute("open"))
})

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
