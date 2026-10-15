export const defaultCrop = () => ({ x: 0.5, y: 0.5, zoom: 1 })

// Mirror Cards::Crop using the dimensions after image orientation correction.
export function cropGeometry(iw, ih, width, height, crop) {
  const scale = Math.max(width / iw, height / ih) * crop.zoom
  const halfX = width / (2 * iw * scale)
  const halfY = height / (2 * ih * scale)
  const rw = Math.round(iw * scale)
  const rh = Math.round(ih * scale)
  return {
    halfX, halfY, rw, rh,
    left: Math.max(0, Math.min(rw - width, Math.floor(crop.x * rw - width / 2))),
    top: Math.max(0, Math.min(rh - height, Math.floor(crop.y * rh - height / 2)))
  }
}

export function clampCrop(iw, ih, width, height, crop) {
  const { halfX, halfY } = cropGeometry(iw, ih, width, height, crop)
  return { x: Math.max(halfX, Math.min(1 - halfX, crop.x)), y: Math.max(halfY, Math.min(1 - halfY, crop.y)), zoom: crop.zoom }
}
