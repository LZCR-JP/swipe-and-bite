import { Controller } from "@hotwired/stimulus"

let mapsPromise
function loadMaps(key) {
  if (window.google?.maps?.Map) return Promise.resolve(window.google.maps)
  if (!mapsPromise) {
    mapsPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      window.swipeBiteMapsReady = () => resolve(window.google.maps)
      script.src = `https://maps.googleapis.com/maps/api/js?${new URLSearchParams({ key, loading: "async", callback: "swipeBiteMapsReady", v: "weekly" })}`
      script.async = true
      script.onerror = () => { script.remove(); mapsPromise = null; reject(new Error("Map unavailable")) }
      document.head.appendChild(script)
    })
  }
  return mapsPromise
}

export default class extends Controller {
  static targets = ["map", "pin", "area", "latitude", "longitude", "status", "people"]
  static values = { key: String }

  async connect() {
    this.active = true
    this.revision = 0
    this.saved = this.latitudeTarget.value !== "" && this.longitudeTarget.value !== ""
    if (!this.keyValue) {
      this.message("Map unavailable. Enter an area instead.")
      return
    }
    try {
      this.maps = await loadMaps(this.keyValue)
      if (!this.active) return
      const center = this.saved ? { lat: Number(this.latitudeTarget.value), lng: Number(this.longitudeTarget.value) } : { lat: 35.6812, lng: 139.7671 }
      this.map = new this.maps.Map(this.mapTarget, { center, zoom: 15, disableDefaultUI: true, zoomControl: true, gestureHandling: "greedy", clickableIcons: false })
      this.geocoder = new this.maps.Geocoder()
      this.pinTarget.hidden = false
      this.dragListener = this.map.addListener("dragstart", () => { this.revision++; this.dragging = true; this.clearCoordinates() })
      this.idleListener = this.map.addListener("idle", () => {
        if (this.dragging) { this.dragging = false; this.choose(this.map.getCenter().toJSON(), "Selected on map") }
      })
      this.clickListener = this.map.addListener("click", event => { this.revision++; this.choose(event.latLng.toJSON(), "Selected on map", true) })
      this.message(this.saved ? "Move the map to change location" : "Move the map or search for a meeting point")
      if (!this.saved && !this.areaTarget.value.trim()) this.locate()
    } catch (_) {
      this.message("Map unavailable. Enter an area instead.")
    }
  }

  disconnect() {
    this.active = false
    this.revision++
    this.dragListener?.remove()
    this.idleListener?.remove()
    this.clickListener?.remove()
  }

  message(text) { this.statusTarget.textContent = text }
  clearCoordinates() { this.latitudeTarget.value = ""; this.longitudeTarget.value = "" }
  areaEdited() { this.revision++; this.dragging = false; this.clearCoordinates(); this.message("Search to set the pin, or use the typed area") }
  choose(point, label, move = false) {
    if (!this.active) return
    this.latitudeTarget.value = point.lat
    this.longitudeTarget.value = point.lng
    this.areaTarget.value = label
    if (move) this.map.setCenter(point)
    this.message("Meeting point set · move the map to change")
  }
  locate() {
    if (!this.map || !navigator.geolocation) { this.message("Use search or move the map to choose a location"); return }
    const version = ++this.revision
    this.message("Finding your location…")
    navigator.geolocation.getCurrentPosition(({ coords }) => {
      if (!this.active || version !== this.revision) return
      this.choose({ lat: coords.latitude, lng: coords.longitude }, "Selected on map", true)
    }, () => {
      if (this.active && version === this.revision) this.message("Location unavailable. Search or move the map.")
    }, { enableHighAccuracy: false, timeout: 10000, maximumAge: 60000 })
  }
  async search(event) {
    event.preventDefault()
    const area = this.areaTarget.value.trim()
    if (!area || area === "Selected on map" || !this.geocoder) return
    const version = ++this.revision
    this.clearCoordinates()
    this.message("Searching…")
    try {
      const { results } = await this.geocoder.geocode({ address: area, componentRestrictions: { country: "JP" } })
      if (!this.active || version !== this.revision) return
      if (!results.length) throw new Error("No location")
      this.choose(results[0].geometry.location.toJSON(), area, true)
    } catch (_) {
      if (this.active && version === this.revision) this.message("Location not found. Try another area or move the map.")
    }
  }
  submit(event) {
    if (this.dragging || (this.areaTarget.value === "Selected on map" && !this.latitudeTarget.value)) {
      event.preventDefault(); this.message("Choose a meeting point first.")
    }
  }
  decrease() { this.peopleTarget.value = Math.max(2, (Number(this.peopleTarget.value) || 2) - 1) }
  increase() { this.peopleTarget.value = Math.min(50, (Number(this.peopleTarget.value) || 2) + 1) }
}
