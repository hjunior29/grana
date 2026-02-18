import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/granai"
import topbar from "../vendor/topbar"

// --- Tooltip Utility ---
const tooltipStyle = "position:absolute;z-index:50;padding:8px 12px;border-radius:8px;background:oklch(var(--b3) / 0.85);backdrop-filter:blur(8px);color:oklch(var(--bc));box-shadow:0 4px 12px rgba(0,0,0,0.2);font-size:13px;pointer-events:none;white-space:nowrap;display:none"

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
      showTooltip(this.el, e, `<strong>${name}</strong><br>${fmtBRL(value)} · ${pct(value, total)}%`)
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

      const urlAttr = item.url ? ` data-cat-url="${item.url}"` : ""
      svg += `<path d="M ${x1} ${y1} A ${radius} ${radius} 0 ${largeArc} 1 ${x2} ${y2} L ${ix1} ${iy1} A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${ix2} ${iy2} Z" fill="${item.color}" opacity="0.85" class="transition-all hover:opacity-100 cursor-pointer" style="transform-origin:${cx}px ${cy}px" data-cat-name="${item.name}" data-cat-value="${item.value}" data-cat-total="${total}"${urlAttr}></path>`
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
      showTooltip(this.el, e, `<strong>${target.dataset.dayDate}</strong><br>${fmtBRL(parseFloat(target.dataset.dayValue))}`)
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

      const urlAttr = item.url ? ` data-day-url="${item.url}"` : ""
      svg += `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" rx="2" class="fill-primary opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-day-date="${item.date}" data-day-value="${item.value}"${urlAttr}></rect>`

      if (data.length <= 15 || i % Math.ceil(data.length / 10) === 0) {
        svg += `<text x="${x + barWidth / 2}" y="${height - 5}" text-anchor="middle" class="fill-base-content text-[8px] opacity-40">${item.date}</text>`
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

const AutoDismiss = {
  mounted() {
    this.timer = setTimeout(() => {
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
      const typeLabel = type === "income" ? "Receitas" : "Despesas"
      showTooltip(this.el, e, `<strong>${label}</strong><br>${typeLabel}: ${fmtBRL(value)}`)
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

    const width = 700
    const height = 220
    const padding = {top: 20, right: 10, bottom: 35, left: 10}
    const chartWidth = width - padding.left - padding.right
    const chartHeight = height - padding.top - padding.bottom
    const groupWidth = chartWidth / data.length
    const barWidth = Math.max(6, groupWidth * 0.35)

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-56">`

    data.forEach((item, i) => {
      const x = padding.left + (i * groupWidth) + groupWidth * 0.15
      const incomeH = (item.income / maxVal) * chartHeight
      const expenseH = (item.expenses / maxVal) * chartHeight

      const incUrl = item.income_url ? ` data-ie-url="${item.income_url}"` : ""
      const expUrl = item.expenses_url ? ` data-ie-url="${item.expenses_url}"` : ""

      svg += `<rect x="${x}" y="${padding.top + chartHeight - incomeH}" width="${barWidth}" height="${incomeH}" rx="2" class="fill-success opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-ie-label="${item.label}" data-ie-type="income" data-ie-value="${item.income}"${incUrl}></rect>`
      svg += `<rect x="${x + barWidth + 2}" y="${padding.top + chartHeight - expenseH}" width="${barWidth}" height="${expenseH}" rx="2" class="fill-error opacity-70 hover:opacity-100 transition-opacity cursor-pointer" data-ie-label="${item.label}" data-ie-type="expenses" data-ie-value="${item.expenses}"${expUrl}></rect>`
      svg += `<text x="${x + barWidth}" y="${height - 8}" text-anchor="middle" class="fill-base-content text-[10px] opacity-50">${item.label}</text>`
    })

    svg += `</svg>`
    svg += `<div class="flex justify-center gap-6 text-xs opacity-60 mt-1"><span class="flex items-center gap-1"><span class="w-3 h-3 rounded-sm bg-success/70"></span> Receitas</span><span class="flex items-center gap-1"><span class="w-3 h-3 rounded-sm bg-error/70"></span> Despesas</span></div>`

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
      showTooltip(this.el, e, `<strong>${target.dataset.projLabel}</strong><br>${fmtBRL(parseFloat(target.dataset.projValue))}`)
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

      svg += `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" rx="2" class="fill-warning opacity-70 hover:opacity-100 transition-opacity" data-proj-label="${item.label}" data-proj-value="${item.value}"></rect>`
      svg += `<text x="${x + barWidth / 2}" y="${height - 8}" text-anchor="middle" class="fill-base-content text-[9px] opacity-50">${item.label}</text>`
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

const Hooks = {
  ...colocatedHooks,
  CategoryChart,
  DailyChart,
  IncomeExpensesChart,
  ProjectionChart,
  AutoDismiss,
  NotificationStack,
  DropZone,
  ProgressBar,
  ActiveNav,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
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
