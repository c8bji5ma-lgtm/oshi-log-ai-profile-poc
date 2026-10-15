import { Controller } from "@hotwired/stimulus"
import { cropGeometry, clampCrop, defaultCrop } from "lib/crop_geometry"

// Image-type independent editor: the caller supplies an authorized source URL,
// frame dimensions and confirmed crop. Only confirm emits a new crop.
export default class extends Controller {
  static targets = ["viewport", "photo", "zoom", "scale", "error", "confirm"]

  disconnect() { this.cancel() }

  open(event) {
    this.cancel()
    const { src, crop, frameId, sourceId, width, height, opener } = event.detail
    this.editing = { frameId, sourceId, width, height, opener }
    this.draft = { ...crop }
    this.ready = false
    this.zoomTarget.disabled = true
    this.zoomTarget.value = crop.zoom
    this.scaleTarget.textContent = `${crop.zoom.toFixed(2)}倍`
    this.errorTarget.textContent = "画像を読み込んでいます。"
    this.confirmTarget.disabled = true
    this.viewportTarget.style.aspectRatio = `${width} / ${height}`
    this.photoTarget.src = src
    this.element.showModal()
    this.zoomTarget.focus()
  }

  loaded() {
    if (!this.editing || !this.element.open) return
    this.ready = true
    this.zoomTarget.disabled = false
    this.errorTarget.textContent = ""
    this.confirmTarget.disabled = false
    this.adjust()
  }

  failed() {
    if (!this.editing) return
    this.ready = false
    this.zoomTarget.disabled = true
    this.confirmTarget.disabled = true
    this.photoTarget.style.visibility = "hidden"
    this.errorTarget.textContent = "登録画像を読み取れません。画像未登録とは異なる状態です。画像を確認して、開き直してください。"
  }

  activity() {
    this.dispatch("activity")
    return Boolean(this.editing && this.element.open)
  }

  zoom() {
    if (!this.ready) return
    if (!this.activity()) return
    this.draft.zoom = Number(this.zoomTarget.value)
    this.adjust()
  }

  reset() {
    if (!this.ready) return
    if (!this.activity()) return
    this.draft = defaultCrop()
    this.adjust()
  }

  adjust() {
    const { width, height } = this.editing
    const iw = this.photoTarget.naturalWidth
    const ih = this.photoTarget.naturalHeight
    this.draft = clampCrop(iw, ih, width, height, this.draft)
    const geometry = cropGeometry(iw, ih, width, height, this.draft)
    const bounds = this.viewportTarget.getBoundingClientRect()
    const ratioX = bounds.width / width
    const ratioY = bounds.height / height
    Object.assign(this.photoTarget.style, {
      width: `${geometry.rw * ratioX}px`, height: `${geometry.rh * ratioY}px`,
      left: `${-geometry.left * ratioX}px`, top: `${-geometry.top * ratioY}px`, visibility: "visible"
    })
    this.zoomTarget.value = this.draft.zoom
    this.scaleTarget.textContent = `${this.draft.zoom.toFixed(2)}倍`
  }

  resized() { if (this.ready && this.element.open) this.adjust() }

  startDrag(event) {
    if (!this.ready || this.pointer || (event.pointerType === "mouse" && event.button !== 0)) return
    event.preventDefault()
    if (!this.activity()) return
    this.viewportTarget.focus()
    this.pointer = { id: event.pointerId, x: event.clientX, y: event.clientY }
    this.viewportTarget.setPointerCapture(event.pointerId)
  }

  drag(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return
    if (!this.activity()) return
    const { width, height } = this.editing
    const geometry = cropGeometry(this.photoTarget.naturalWidth, this.photoTarget.naturalHeight, width, height, this.draft)
    const bounds = this.viewportTarget.getBoundingClientRect()
    this.draft.x -= (event.clientX - this.pointer.x) / (geometry.rw * bounds.width / width)
    this.draft.y -= (event.clientY - this.pointer.y) / (geometry.rh * bounds.height / height)
    this.pointer.x = event.clientX
    this.pointer.y = event.clientY
    this.adjust()
  }

  stopDrag(event) {
    if (!this.pointer || (event?.pointerId !== undefined && event.pointerId !== this.pointer.id)) return
    const id = this.pointer.id
    this.pointer = null
    if (this.viewportTarget.hasPointerCapture(id)) this.viewportTarget.releasePointerCapture(id)
  }

  moveKey(event) {
    const directions = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }
    if (!directions[event.key] || !this.ready) return
    event.preventDefault()
    this.move(...directions[event.key])
  }

  moveButton(event) { this.move(Number(event.currentTarget.dataset.dx), Number(event.currentTarget.dataset.dy)) }

  move(dx, dy) {
    if (!this.ready) return
    if (!this.activity()) return
    // Arrow directions move the photograph, as dragging does.
    this.draft.x -= dx * 0.01
    this.draft.y -= dy * 0.01
    this.adjust()
  }

  confirm() {
    if (!this.ready || !this.editing) return
    if (!this.activity()) return
    this.dispatch("confirm", { detail: { ...this.editing, crop: { ...this.draft } } })
    this.cancel()
  }

  cancel(event) {
    event?.preventDefault()
    if (event && event.type !== "crop:cancel" && this.editing) this.dispatch("activity")
    this.stopDrag()
    const opener = this.editing?.opener
    this.editing = null
    this.draft = null
    this.ready = false
    if (this.element.open) this.element.close()
    this.photoTarget.removeAttribute("src")
    this.photoTarget.removeAttribute("style")
    this.viewportTarget.style.removeProperty("aspect-ratio")
    this.errorTarget.textContent = ""
    this.confirmTarget.disabled = true
    this.zoomTarget.value = "1"
    this.zoomTarget.disabled = true
    this.scaleTarget.textContent = "1.00倍"
    if (opener?.isConnected && !opener.disabled) opener.focus()
  }
}
