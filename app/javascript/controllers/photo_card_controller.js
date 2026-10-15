import { Controller } from "@hotwired/stimulus"
import { defaultCrop } from "lib/crop_geometry"

export default class extends Controller {
  static targets = ["form", "status", "error", "preview", "image", "generateButton", "downloadButton", "oshi", "frames", "frameTemplate", "template", "panel", "settingsForm", "cropDialog"]
  static values = { createUrl: String, downloadUrl: String, layouts: Object }

  connect() {
    this.sequence = (this.sequence || 0) + 1
    this.disposed = false
    this.lastAction = Date.now()
    this.template = "photo"
    this.settingsFormTargets.forEach(form => {
      form.reset()
      form.querySelectorAll("input, select").forEach(input => { input.disabled = false })
    })
    this.selectedIds = this.oshiTargets.filter(input => input.checked).map(input => input.value)
    this.imageSources = new Map(this.selectedIds.map(id => [id, id]))
    this.crops = new Map()
    this.renderFrames()
    this.renderPanels()
    this.timer = setInterval(() => this.checkExpiry(), 1000)
  }

  disconnect() { this.dispose() }

  switchTemplate(event) {
    if (this.disposed || !this.checkExpiry()) return
    this.lastAction = Date.now()
    this.closeCrop()
    this.template = event.target.value
    this.invalidate()
    this.renderPanels()
    this.errorTarget.textContent = ""
    this.statusTarget.textContent = this.template === "photo"
      ? "ビジュアル重視に切り替えました。プレビューを作成してください。"
      : "テンプレートを切り替えました。このテンプレートのPNG生成は未実装です。"
  }

  renderPanels() {
    this.panelTargets.forEach(panel => { panel.hidden = panel.dataset.template !== this.template })
  }

  get canGenerate() { return !this.disposed && this.template === "photo" && this.selectedIds?.length > 0 }

  cropActivity() {
    if (!this.disposed && this.checkExpiry()) this.lastAction = Date.now()
  }

  closeCrop() { this.cropDialogTarget.dispatchEvent(new Event("crop:cancel")) }

  editCrop(event) {
    if (this.disposed || !this.checkExpiry() || this.template !== "photo") return
    this.lastAction = Date.now()
    const frameId = event.currentTarget.dataset.cropFor
    const sourceId = this.imageSources.get(frameId)
    const source = this.oshiTargets.find(input => input.value === sourceId)
    if (!source?.dataset.imageUrl) return
    this.cropDialogTarget.dispatchEvent(new CustomEvent("crop:open", { detail: {
      frameId, sourceId, src: source.dataset.imageUrl, opener: event.currentTarget,
      crop: this.crops.get(frameId) || defaultCrop(), ...this.layoutsValue[this.selectedIds.length]
    } }))
  }

  confirmCrop(event) {
    if (this.disposed || !this.checkExpiry() || this.template !== "photo") return
    const { frameId, sourceId, crop } = event.detail
    if (!this.selectedIds.includes(frameId) || this.imageSources.get(frameId) !== sourceId) return
    const old = this.crops.get(frameId) || defaultCrop()
    if (["x", "y", "zoom"].every(key => Math.abs(old[key] - crop[key]) <= 1e-9)) return
    this.crops.set(frameId, crop)
    this.invalidate()
    this.statusTarget.textContent = "画像の調整範囲を変更しました。プレビューを作成してください。"
  }

  selectOshi(event) {
    if (this.disposed || !this.checkExpiry()) return
    this.closeCrop()
    const input = event.target
    this.lastAction = Date.now()
    if (input.checked) {
      if (this.selectedIds.length >= 4) {
        input.checked = false
        event.stopPropagation()
        this.errorTarget.textContent = "推しは4人まで選択できます。"
        return
      }
      this.selectedIds.push(input.value)
      this.imageSources.set(input.value, input.value)
    } else {
      this.selectedIds = this.selectedIds.filter(id => id !== input.value)
      this.imageSources.delete(input.value)
      this.crops.delete(input.value)
      for (const id of this.selectedIds) {
        const source = this.imageSources.get(id)
        if (source && !this.selectedIds.includes(source)) {
          this.imageSources.set(id, id)
          this.crops.delete(id)
        }
      }
    }
    this.renderFrames()
  }

  renderFrames() {
    const names = new Map(this.oshiTargets.map(input => [input.value, input.dataset.name]))
    const rows = this.selectedIds.map((id, index) => {
      const row = this.frameTemplateTarget.content.firstElementChild.cloneNode(true)
      const label = row.querySelector("[data-frame-label]")
      const source = row.querySelector("[data-frame-source]")
      source.id = `card-image-source-${id}`
      source.dataset.imageFor = id
      label.htmlFor = source.id
      label.textContent = `${index + 1}. ${names.get(id)}の画像`
      source.add(new Option("画像を表示しない", ""))
      for (const candidate of this.selectedIds) source.add(new Option(`${names.get(candidate)}の代表画像`, candidate))
      source.value = this.imageSources.get(id) || ""
      const adjust = row.querySelector("[data-crop-for]")
      adjust.dataset.cropFor = id
      adjust.setAttribute("aria-label", `${index + 1}. ${names.get(id)}の画像を調整`)
      const imageOwner = this.oshiTargets.find(input => input.value === this.imageSources.get(id))
      adjust.disabled = !imageOwner?.dataset.imageUrl
      return row
    })
    this.framesTarget.replaceChildren(...rows)
    this.generateButtonTarget.disabled = !this.canGenerate
  }

  changed(event) {
    if (this.disposed || !this.checkExpiry()) return
    this.lastAction = Date.now()
    const id = event.target.dataset.imageFor
    if (id) {
      this.closeCrop()
      this.imageSources.set(id, event.target.value)
      this.crops.delete(id)
      const owner = this.oshiTargets.find(input => input.value === event.target.value)
      event.target.closest(".form-field").querySelector("[data-crop-for]").disabled = !owner?.dataset.imageUrl
    }
    this.invalidate()
    this.errorTarget.textContent = ""
    this.statusTarget.textContent = this.template === "photo"
      ? "設定を変更しました。プレビューを作成してください。"
      : "設定を変更しました。このテンプレートのPNG生成は未実装です。"
  }

  async generate(event) {
    event.preventDefault()
    if (this.disposed || !this.checkExpiry()) return
    if (!this.canGenerate) return
    this.lastAction = Date.now()
    this.invalidate()
    const sequence = this.sequence
    const operation = new AbortController()
    this.operation = operation
    this.errorTarget.textContent = ""
    this.statusTarget.textContent = "カードを作成しています。"
    this.generateButtonTarget.disabled = true
    try {
      const form = this.formTarget.elements
      const response = await fetch(this.createUrlValue, {
        method: "POST", credentials: "same-origin", signal: operation.signal,
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken },
        body: JSON.stringify({ card: {
          template: "photo",
          user_oshi_ids: this.selectedIds,
          image_user_oshi_ids: this.selectedIds.map(id => this.imageSources.get(id)),
          crops: this.selectedIds.map(id => this.crops.get(id) || defaultCrop()),
          show_introduction: form.show_introduction.checked
        } })
      })
      if (!response.ok) throw new Error(await this.errorMessage(response))
      const blob = await response.blob()
      const digest = await this.sha256(blob)
      if (!this.current(sequence)) return
      const expiresAt = Number(response.headers.get("X-Card-Expires-At")) * 1000
      if (blob.type !== "image/png" || digest !== response.headers.get("X-PNG-SHA256") || expiresAt <= Date.now()) {
        throw new Error("完成画像を確認できません。再生成してください。")
      }
      this.result = { blob, digest, expiresAt, receipt: response.headers.get("X-Card-Receipt") }
      this.url = URL.createObjectURL(blob)
      this.imageTarget.src = this.url
      this.previewTarget.hidden = false
      this.downloadButtonTarget.disabled = false
      this.statusTarget.textContent = "完成プレビューを確認してから保存してください。"
    } catch (error) {
      if (this.current(sequence) && error.name !== "AbortError") {
        this.errorTarget.textContent = error.message
        this.statusTarget.textContent = ""
      }
    } finally {
      if (this.current(sequence)) this.generateButtonTarget.disabled = !this.canGenerate
    }
  }

  async download() {
    if (this.disposed || !this.checkExpiry() || this.template !== "photo" || !this.result) return
    this.lastAction = Date.now()
    const result = this.result
    const sequence = this.sequence
    const operation = new AbortController()
    this.operation = operation
    this.downloadButtonTarget.disabled = true
    this.errorTarget.textContent = ""
    this.statusTarget.textContent = "保存前の確認をしています。"
    try {
      const response = await fetch(this.downloadUrlValue, {
        method: "POST", credentials: "same-origin", signal: operation.signal,
        headers: { "Content-Type": "image/png", "X-CSRF-Token": this.csrfToken, "X-Card-Receipt": result.receipt },
        body: result.blob
      })
      if (!response.ok) {
        const message = await this.errorMessage(response)
        if (!this.current(sequence)) return
        if ([401, 403, 409, 410, 422].includes(response.status)) {
          this.invalidate()
          this.errorTarget.textContent = message
          return
        }
        throw new Error(message)
      }
      const blob = await response.blob()
      const digest = await this.sha256(blob)
      if (!this.checkExpiry() || !this.current(sequence) || this.result !== result) return
      if (digest !== result.digest || blob.size !== result.blob.size) throw new Error("確認したPNGと一致しません。")
      const url = URL.createObjectURL(blob)
      const link = document.createElement("a")
      link.href = url
      link.download = "oshilog-card.png"
      document.body.append(link)
      link.click()
      link.remove()
      // Give the browser time to take ownership of the explicit download.
      setTimeout(() => URL.revokeObjectURL(url), 1000)
      this.statusTarget.textContent = "ダウンロードを開始しました。保存先をブラウザーで確認してください。"
    } catch (error) {
      if (this.current(sequence) && error.name !== "AbortError") this.errorTarget.textContent = error.message
    } finally {
      if (this.current(sequence) && this.result) this.downloadButtonTarget.disabled = false
    }
  }

  checkExpiry() {
    if (Date.now() - this.lastAction >= 30 * 60 * 1000) {
      this.dispose()
      this.statusTarget.textContent = "30分間操作がなかったため破棄しました。ページを開き直してください。"
      return false
    }
    if (this.result && Date.now() >= this.result.expiresAt) {
      this.invalidate()
      this.statusTarget.textContent = "プレビューの期限が切れました。再生成してください。"
    }
    return true
  }

  invalidate() {
    this.sequence += 1
    this.operation?.abort()
    if (this.url) URL.revokeObjectURL(this.url)
    this.url = null
    this.result = null
    this.imageTarget.removeAttribute("src")
    this.previewTarget.hidden = true
    this.generateButtonTarget.disabled = !this.canGenerate
    this.downloadButtonTarget.disabled = true
  }

  dispose() {
    this.disposed = true
    clearInterval(this.timer)
    this.closeCrop()
    this.invalidate()
    this.settingsFormTargets.forEach(form => {
      form.reset()
      for (const input of form.elements) input.disabled = true
    })
    this.template = "photo"
    this.renderPanels()
    this.selectedIds = []
    this.imageSources?.clear()
    this.crops?.clear()
    this.framesTarget.replaceChildren()
    this.generateButtonTarget.disabled = true
  }

  current(sequence) { return !this.disposed && this.sequence === sequence }
  get csrfToken() { return document.querySelector('meta[name="csrf-token"]').content }

  async sha256(blob) {
    if (!crypto.subtle) throw new Error("HTTPSまたはlocalhostで開いてください。")
    const digest = await crypto.subtle.digest("SHA-256", await blob.arrayBuffer())
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("")
  }

  async errorMessage(response) {
    try { return (await response.json()).error || "処理に失敗しました。" }
    catch { return "通信に失敗しました。もう一度操作してください。" }
  }
}
