import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/grana"
import topbar from "../vendor/topbar"
import {PluggyConnect} from "../vendor/pluggy-connect"

// --- Theme ---
const visualStyles = new Set(["default", "signal", "bossa", "papel", "caderneta", "planetario", "cyber"])
let cyberLightNoticeTimer
let cyberGlitchTimer

function showCyberLightNotice() {
  let notice = document.getElementById("cyber-light-notice")

  if (!notice) {
    notice = document.createElement("div")
    notice.id = "cyber-light-notice"
    notice.className = "cyber-light-notice"
    document.body.appendChild(notice)
  }

  notice.textContent = "Só permitimos o modo escuro, e sabe o por que? Porque a luz atrai bugs."
  notice.classList.add("is-visible")

  clearTimeout(cyberLightNoticeTimer)
  cyberLightNoticeTimer = setTimeout(() => {
    notice.classList.remove("is-visible")
  }, 4200)
}

function triggerCyberGlitch() {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return
  }

  let overlay = document.getElementById("cyber-glitch-overlay")

  if (!overlay) {
    overlay = document.createElement("div")
    overlay.id = "cyber-glitch-overlay"
    overlay.className = "cyber-glitch-overlay"
    document.body.appendChild(overlay)
  }

  document.documentElement.classList.remove("cyber-glitching")
  overlay.classList.remove("is-active")

  window.requestAnimationFrame(() => {
    document.documentElement.classList.add("cyber-glitching")
    overlay.classList.add("is-active")
  })

  clearTimeout(cyberGlitchTimer)
  cyberGlitchTimer = setTimeout(() => {
    document.documentElement.classList.remove("cyber-glitching")
    overlay.classList.remove("is-active")
  }, 780)
}

function cyberStyleActive() {
  return document.documentElement.dataset.visualStyle === "cyber"
}

function lightThemeActive() {
  return document.documentElement.dataset.theme === "light"
}

function activeThemeMode() {
  const theme = document.documentElement.dataset.theme

  if (theme) {
    return theme
  }

  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
}

function topbarPalette() {
  const style = document.documentElement.dataset.visualStyle || "default"
  const dark = activeThemeMode() === "dark"

  if (style === "signal") {
    return dark
      ? {
          barColors: {0: "#42ff75", ".45": "#17c8ff", "1.0": "#ffb84a"},
          shadowColor: "rgba(66, 255, 117, .35)",
        }
      : {
          barColors: {0: "#128a42", ".55": "#1d6f96", "1.0": "#a66b00"},
          shadowColor: "rgba(18, 138, 66, .24)",
        }
  }

  if (style === "bossa") {
    return dark
      ? {
          barColors: {0: "#ffd23f", ".45": "#35d98d", "1.0": "#ff6b57"},
          shadowColor: "rgba(239, 63, 47, .34)",
        }
      : {
          barColors: {0: "#2f65d9", ".5": "#35b779", "1.0": "#ef3f2f"},
          shadowColor: "rgba(32, 33, 36, .28)",
        }
  }

  if (style === "papel") {
    return dark
      ? {
          barColors: {0: "#ff5640", "1.0": "#f1efe4"},
          shadowColor: "rgba(0, 0, 0, .4)",
        }
      : {
          barColors: {0: "#e8311a", "1.0": "#0c0c0a"},
          shadowColor: "rgba(12, 12, 10, .2)",
        }
  }

  if (style === "caderneta") {
    return dark
      ? {
          barColors: {0: "#f07a33", ".5": "#ffc94d", "1.0": "#a8bf63"},
          shadowColor: "rgba(0, 0, 0, .4)",
        }
      : {
          barColors: {0: "#c24e12", ".5": "#a87b14", "1.0": "#5f7030"},
          shadowColor: "rgba(59, 42, 29, .26)",
        }
  }

  if (style === "planetario") {
    return dark
      ? {
          barColors: {0: "#8fd8ff", ".55": "#c9d6f2", "1.0": "#ffd98a"},
          shadowColor: "rgba(143, 216, 255, .34)",
        }
      : {
          barColors: {0: "#1f6fa8", ".55": "#51618f", "1.0": "#b07c1a"},
          shadowColor: "rgba(19, 28, 51, .22)",
        }
  }

  if (style === "cyber") {
    return {
      barColors: {0: "#ff0033", ".52": "#ff00cc", "1.0": "#d7ff00"},
      shadowColor: "rgba(255, 0, 51, .58)",
      barThickness: 4,
    }
  }

  return dark
    ? {
        barColors: {0: "oklch(58% 0.233 277.117)", ".55": "oklch(60% 0.25 292.717)", "1.0": "oklch(66% 0.179 58.318)"},
        shadowColor: "rgba(0, 0, 0, .32)",
      }
    : {
        barColors: {0: "oklch(70% 0.213 47.604)", ".55": "oklch(62% 0.214 259.815)", "1.0": "oklch(58% 0.253 17.585)"},
        shadowColor: "rgba(0, 0, 0, .18)",
      }
}

function updateTopbarConfig() {
  topbar.config({
    barThickness: 3,
    shadowBlur: 10,
    ...topbarPalette(),
  })
}

const setTheme = (theme, opts = {}) => {
  const notify = opts.notify !== false
  const requestedTheme = theme

  if (theme === "light" && cyberStyleActive()) {
    theme = "dark"
  }

  if (theme === "system") {
    localStorage.removeItem("phx:theme")
    document.documentElement.removeAttribute("data-theme")
  } else {
    localStorage.setItem("phx:theme", theme)
    document.documentElement.setAttribute("data-theme", theme)
  }

  updateTopbarConfig()

  if (notify && requestedTheme === "light" && cyberStyleActive()) {
    showCyberLightNotice()
  }
}

const setVisualStyle = (style, opts = {}) => {
  const notify = opts.notify !== false
  const visualStyle = visualStyles.has(style) ? style : "default"

  if (visualStyle === "default") {
    localStorage.removeItem("phx:visual-style")
    document.documentElement.removeAttribute("data-visual-style")
  } else {
    localStorage.setItem("phx:visual-style", visualStyle)
    document.documentElement.setAttribute("data-visual-style", visualStyle)
  }

  updateTopbarConfig()

  if (visualStyle === "cyber" && lightThemeActive()) {
    setTheme("dark", {notify: false})

    if (notify) {
      showCyberLightNotice()
    }
  }

  if (notify && visualStyle === "cyber") {
    triggerCyberGlitch()
  }
}

// Logado, a preferência do servidor (data-server-*) vence o localStorage.
const serverTheme = document.documentElement.dataset.serverTheme
const serverVisualStyle = document.documentElement.dataset.serverVisualStyle
setVisualStyle(serverVisualStyle || localStorage.getItem("phx:visual-style") || "default", {notify: false})
setTheme(serverTheme || localStorage.getItem("phx:theme") || "system", {notify: false})
window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system", {notify: false}))
window.addEventListener("storage", (e) => e.key === "phx:visual-style" && setVisualStyle(e.newValue || "default", {notify: false}))
window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme))
window.addEventListener("phx:set-visual-style", (e) => setVisualStyle(e.target.dataset.phxVisualStyle))
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
  if (!document.documentElement.dataset.theme) {
    updateTopbarConfig()
  }
})

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

// Valor do app (não da landing): fica coberto quando "Ocultar valores" está ligado.
function privateBRL(val) {
  return `<span class="ui-private">${fmtBRL(val)}</span>`
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
      showTooltip(this.el, e, `<strong>${escapeHtml(name)}</strong><br>${privateBRL(value)} · ${pct(value, total)}%`)
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
    svg += `<text x="${cx}" y="${cy + 12}" text-anchor="middle" class="ui-private fill-base-content text-sm font-semibold">${formattedTotal}</text>`
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
      showTooltip(this.el, e, `<strong>${escapeHtml(target.dataset.dayDate)}</strong><br>${privateBRL(parseFloat(target.dataset.dayValue))}`)
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
    const slot = chartWidth / data.length
    const barWidth = Math.min(40, Math.max(4, slot - 2))

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-48 mb-4">`

    data.forEach((item, i) => {
      const barHeight = (item.value / maxVal) * chartHeight
      const x = padding.left + i * slot + (slot - barWidth) / 2
      const y = padding.top + chartHeight - barHeight

      const urlAttr = item.url ? ` data-day-url="${escapeHtml(item.url)}"` : ""
      const barFill = this.el.dataset.barFill || "fill-(--ui-despesa)"
      svg += `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" rx="2" class="${barFill} hover:brightness-110 transition-opacity cursor-pointer" data-day-date="${escapeHtml(item.date)}" data-day-value="${item.value}"${urlAttr}></rect>`

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

// Calendário de gastos do painel: só o tooltip e o clique; a grade vem do servidor.
const SpendingCalendar = {
  mounted() {
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-day-date]")
      if (!target) return hideTooltip(this.el)
      const value = target.dataset.dayValue
      const amount = value ? privateBRL(parseFloat(value)) : "Sem gastos"
      showTooltip(this.el, e, `<strong>${escapeHtml(target.dataset.dayDate)}</strong><br>${amount}`)
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
    this.el.addEventListener("click", (e) => {
      const target = e.target.closest("[data-day-url]")
      if (target) this.pushEvent("chart-navigate", {url: target.dataset.dayUrl})
    })
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
      showTooltip(this.el, e, `<strong>${escapeHtml(label)}</strong><br>${escapeHtml(typeLabel)}: ${privateBRL(value)}`)
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
    const barWidth = Math.min(56, Math.max(8, (groupWidth - barGap) * 0.42))

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-80 sm:h-96">`

    data.forEach((item, i) => {
      const groupX = padding.left + (i * groupWidth)
      const pairWidth = barWidth * 2 + barGap
      const x = groupX + (groupWidth - pairWidth) / 2
      const incomeH = (item.income / maxVal) * chartHeight
      const expenseH = (item.expenses / maxVal) * chartHeight

      const incUrl = item.income_url ? ` data-ie-url="${escapeHtml(item.income_url)}"` : ""
      const expUrl = item.expenses_url ? ` data-ie-url="${escapeHtml(item.expenses_url)}"` : ""

      const incFill = this.el.dataset.incomeFill || "fill-(--ui-receita)"
      const expFill = this.el.dataset.expensesFill || "fill-(--ui-despesa)"
      const safeLabel = escapeHtml(item.label)
      svg += `<rect x="${x}" y="${padding.top + chartHeight - incomeH}" width="${barWidth}" height="${incomeH}" rx="2" class="${incFill} hover:brightness-110 transition-opacity cursor-pointer" data-ie-label="${safeLabel}" data-ie-type="income" data-ie-value="${item.income}"${incUrl}></rect>`
      svg += `<rect x="${x + barWidth + barGap}" y="${padding.top + chartHeight - expenseH}" width="${barWidth}" height="${expenseH}" rx="2" class="${expFill} hover:brightness-110 transition-opacity cursor-pointer" data-ie-label="${safeLabel}" data-ie-type="expenses" data-ie-value="${item.expenses}"${expUrl}></rect>`
      svg += `<text x="${groupX + groupWidth / 2}" y="${height - 8}" text-anchor="middle" class="fill-base-content text-[10px] opacity-50">${safeLabel}</text>`
    })

    svg += `</svg>`
    const incLabel = this.el.dataset.incomeLabel || "Receitas"
    const expLabel = this.el.dataset.expensesLabel || "Despesas"
    const incColor = this.el.dataset.incomeColor || "bg-(--ui-receita)"
    const expColor = this.el.dataset.expensesColor || "bg-(--ui-despesa)"
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

// Sankey do fluxo de caixa: fontes de receita à esquerda, o caixa do período no meio e,
// à direita, as categorias de despesa, os investimentos e a sobra.
const CashFlowChart = {
  mounted() {
    this.renderChart()
    this.el.addEventListener("mousemove", (e) => {
      const target = e.target.closest("[data-flow-name]")
      if (!target) return hideTooltip(this.el)
      const value = parseFloat(target.dataset.flowValue)
      const total = parseFloat(target.dataset.flowTotal)
      showTooltip(this.el, e, `<strong>${escapeHtml(target.dataset.flowName)}</strong><br>${privateBRL(value)} · ${pct(value, total)}%`)
    })
    this.el.addEventListener("mouseleave", () => hideTooltip(this.el))
    this.el.addEventListener("click", (e) => {
      const target = e.target.closest("[data-flow-url]")
      if (target) this.pushEvent("chart-navigate", {url: target.dataset.flowUrl})
    })
  },
  updated() { this.renderChart() },
  renderChart() {
    const data = JSON.parse(this.el.dataset.flow || "{}")
    const sources = data.sources || []
    const targets = data.targets || []
    const total = sources.reduce((sum, n) => sum + n.value, 0)
    if (!total || !targets.length) return

    const width = 1000
    const rows = Math.max(sources.length, targets.length)
    const height = Math.max(280, Math.min(560, rows * 44 + 40))
    const pad = {top: 16, bottom: 16}
    const nodeW = 12
    const gap = 10
    const leftX = 0
    const centerX = width / 2 - nodeW / 2
    const rightX = width - nodeW
    const usable = height - pad.top - pad.bottom

    const layout = (nodes) => {
      const free = usable - gap * Math.max(0, nodes.length - 1)
      let y = pad.top
      return nodes.map((n) => {
        const h = Math.max(2, (n.value / total) * free)
        const node = {...n, y, h}
        y += h + gap
        return node
      })
    }
    const left = layout(sources)
    const right = layout(targets)
    const center = {y: pad.top, h: usable}

    const uid = `cf${Math.random().toString(36).slice(2, 8)}`
    let defs = ""
    let links = ""
    let nodes = ""
    let labels = ""
    const ribbon = (x0, y0, h0, x1, y1, h1, id) => {
      const mid = (x0 + x1) / 2
      return `M ${x0} ${y0} C ${mid} ${y0}, ${mid} ${y1}, ${x1} ${y1} L ${x1} ${y1 + h1} C ${mid} ${y1 + h1}, ${mid} ${y0 + h0}, ${x0} ${y0 + h0} Z`
    }
    const attrs = (n) =>
      `data-flow-name="${escapeHtml(n.name)}" data-flow-value="${n.value}" data-flow-total="${total}"` +
      (n.url ? ` data-flow-url="${escapeHtml(n.url)}"` : "")

    // Ribbons keep the order of the nodes on each side of the cash node.
    let inY = center.y
    left.forEach((n, i) => {
      const h = (n.value / total) * center.h
      const id = `${uid}-in-${i}`
      defs += `<linearGradient id="${id}" x1="0" x2="1" y1="0" y2="0"><stop offset="0" stop-color="${escapeHtml(n.color)}"/><stop offset="1" stop-color="var(--color-primary)"/></linearGradient>`
      links += `<path d="${ribbon(leftX + nodeW, n.y, n.h, centerX, inY, h, id)}" fill="url(#${id})" class="cf-link${n.url ? " cursor-pointer" : ""}" ${attrs(n)}></path>`
      inY += h
    })
    let outY = center.y
    right.forEach((n, i) => {
      const h = (n.value / total) * center.h
      const id = `${uid}-out-${i}`
      defs += `<linearGradient id="${id}" x1="0" x2="1" y1="0" y2="0"><stop offset="0" stop-color="var(--color-primary)"/><stop offset="1" stop-color="${escapeHtml(n.color)}"/></linearGradient>`
      links += `<path d="${ribbon(centerX + nodeW, outY, h, rightX, n.y, n.h, id)}" fill="url(#${id})" class="cf-link${n.url ? " cursor-pointer" : ""}" ${attrs(n)}></path>`
      outY += h
    })

    // Labels follow their node but never overlap the previous one.
    let bottom = height
    const place = (list, x, anchor) => {
      let last = -Infinity
      list.forEach((n) => {
        const y = Math.max(n.y + n.h / 2, last + 30)
        last = y
        bottom = Math.max(bottom, y + 20)
        labels += `<text x="${x}" y="${y - 2}" text-anchor="${anchor}" class="cf-label">${escapeHtml(n.name)}</text>`
        labels += `<text x="${x}" y="${y + 12}" text-anchor="${anchor}" class="cf-value ui-private">${fmtBRL(n.value)}</text>`
      })
    }
    left.forEach((n) => {
      nodes += `<rect x="${leftX}" y="${n.y}" width="${nodeW}" height="${n.h}" rx="3" fill="${escapeHtml(n.color)}" class="cf-node${n.url ? " cursor-pointer" : ""}" ${attrs(n)}></rect>`
    })
    right.forEach((n) => {
      nodes += `<rect x="${rightX}" y="${n.y}" width="${nodeW}" height="${n.h}" rx="3" fill="${escapeHtml(n.color)}" class="cf-node${n.url ? " cursor-pointer" : ""}" ${attrs(n)}></rect>`
    })
    nodes += `<rect x="${centerX}" y="${center.y}" width="${nodeW}" height="${center.h}" rx="3" fill="var(--color-primary)" class="cf-node" data-flow-name="Caixa do período" data-flow-value="${total}" data-flow-total="${total}"></rect>`
    place(left, leftX + nodeW + 10, "start")
    place(right, rightX - 10, "end")
    labels += `<text x="${centerX + nodeW + 10}" y="${center.y + center.h / 2 - 2}" class="cf-label">Caixa do período</text>`
    labels += `<text x="${centerX + nodeW + 10}" y="${center.y + center.h / 2 + 12}" class="cf-value ui-private">${fmtBRL(total)}</text>`

    const svg = `<svg viewBox="0 0 ${width} ${bottom}" class="cf-chart w-full" preserveAspectRatio="xMidYMid meet"><defs>${defs}</defs>${links}${nodes}${labels}</svg>`
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
      showTooltip(this.el, e, `<strong>${escapeHtml(target.dataset.projLabel)}</strong><br>${privateBRL(parseFloat(target.dataset.projValue))}`)
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
    const slot = chartWidth / data.length
    const barWidth = Math.min(48, Math.max(8, slot - 4))

    let svg = `<svg viewBox="0 0 ${width} ${height}" class="w-full h-56">`

    data.forEach((item, i) => {
      const barHeight = (item.value / maxVal) * chartHeight
      const x = padding.left + i * slot + (slot - barWidth) / 2
      const y = padding.top + chartHeight - barHeight

      const safeLabel = escapeHtml(item.label)
      svg += `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" rx="2" class="fill-(--ui-despesa) hover:brightness-110 transition-opacity cursor-pointer" data-proj-label="${safeLabel}" data-proj-value="${item.value}"></rect>`
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

const DropZone = {
  mounted() {
    let counter = 0
    this.el.addEventListener("dragenter", (e) => {
      e.preventDefault()
      counter++
      this.el.classList.add("ui-dropzone-active")
    })
    this.el.addEventListener("dragover", (e) => e.preventDefault())
    this.el.addEventListener("dragleave", () => {
      counter--
      if (counter === 0) {
        this.el.classList.remove("ui-dropzone-active")
      }
    })
    this.el.addEventListener("drop", () => {
      counter = 0
      this.el.classList.remove("ui-dropzone-active")
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

    if (this.hiddenInput.value) {
      const [reais, centavos = ""] = parseFloat(this.hiddenInput.value).toFixed(2).split(".")
      if (parseFloat(this.hiddenInput.value) > 0) this.display.value = this.format(reais, centavos)
    }

    this.display.addEventListener("input", (e) => {
      const raw = e.target.value.replace(/[^\d,]/g, "")
      const [reais, ...rest] = raw.split(",")
      const hasComma = rest.length > 0
      const centavos = rest.join("").slice(0, 2)
      const intPart = reais.replace(/^0+(?=\d)/g, "")

      if (intPart === "" && !hasComma) {
        this.display.value = ""
        this.hiddenInput.value = ""
        return
      }

      this.display.value = this.format(intPart || "0", hasComma ? centavos : null)
      this.hiddenInput.value = `${intPart || "0"}.${centavos.padEnd(2, "0")}`
    })

    this.display.addEventListener("keydown", (e) => {
      if (e.ctrlKey || e.metaKey) return
      if (e.key.length > 1) return
      if (e.key === "." || e.key === ",") {
        e.preventDefault()
        if (!this.display.value.includes(",")) {
          this.display.value += ","
          this.display.dispatchEvent(new Event("input", {bubbles: true}))
        }
        return
      }
      if (!/\d/.test(e.key)) e.preventDefault()
    })
  },

  format(reais, centavos) {
    const formatted = reais.replace(/\B(?=(\d{3})+(?!\d))/g, ".")
    return centavos === null ? formatted : `${formatted},${centavos}`
  }
}

// --- Open Finance (Pluggy Connect) ---
// O servidor gera um connect token (30 min, escopo restrito) e o envia via
// push_event; o widget roda num iframe de connect.pluggy.ai. Devolvemos só o id do
// Item criado — o servidor confere esse id na API da Pluggy antes de gravar.
const PluggyConnectWidget = {
  mounted() {
    this.handleEvent("pluggy:open", ({connect_token, connector_id}) => {
      this.destroyWidget()

      this.widget = new PluggyConnect({
        connectToken: connect_token,
        connectorIds: [connector_id],
        selectedConnectorId: connector_id,
        language: "pt",
        theme: activeThemeMode() === "dark" ? "dark" : "light",
        onSuccess: ({item}) => this.pushEvent("pluggy_connected", {item_id: item.id}),
        onError: ({message}) => this.pushEvent("pluggy_error", {message}),
        onClose: () => this.pushEvent("pluggy_closed", {}),
      })

      this.widget.init().catch(error => {
        this.pushEvent("pluggy_error", {message: error && error.message})
      })
    })
  },

  destroyed() {
    this.destroyWidget()
  },

  destroyWidget() {
    if (this.widget) {
      this.widget.destroy().catch(() => {})
      this.widget = null
    }
  },
}

const Hooks = {
  ...colocatedHooks,
  CategoryChart,
  DailyChart,
  CalendarHeatmap,
  SpendingCalendar,
  IncomeExpensesChart,
  CashFlowChart,
  ProjectionChart,
  AutoDismiss,
  NotificationStack,
  DropZone,
  ActiveNav,
  LandingAIDemo,
  CurrencyInput,
  PluggyConnectWidget,
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
})

updateTopbarConfig()
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
