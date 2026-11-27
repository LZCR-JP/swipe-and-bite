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
  static targets = ["map", "pin", "area", "latitude", "longitude", "status", "people", "locationName"]
  static values = { key: String }

  async connect() {
    this.active = true
    this.revision = 0
    this.pending = false
    this.dragging = false
    this.dirty = false
    this.lastCenter = null
    this.showLocation(this.areaTarget.value === "Selected on map" ? "Pinned location" : this.areaTarget.value.trim() || "Choose a meeting point")
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
      this.lastCenter = center
      this.dragListener = this.map.addListener("dragstart", () => {
        this.revision++
        this.pending = false
        this.dragging = true
        this.clearCoordinates()
        this.showLocation("Moving pin…")
        this.message("Move the map to choose your meeting point")
      })
      this.idleListener = this.map.addListener("idle", () => {
        const point = this.map.getCenter()?.toJSON()
        if (!point) return
        const moved = !this.samePoint(point, this.lastCenter)
        if (this.dragging || moved) {
          this.dragging = false
          this.choosePin(point)
        }
      })
      this.clickListener = this.map.addListener("click", event => this.choosePin(event.latLng.toJSON(), true))
      this.message(this.saved ? "Move the map to change location" : "Move the map or search for a meeting point")
      if (this.saved && this.areaTarget.value === "Selected on map") this.choosePin(center)
      else if (!this.saved && !this.areaTarget.value.trim()) this.locate()
      else if (!this.saved) { this.dirty = true; this.message("Search to confirm this location") }
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
  showLocation(text) { this.locationNameTarget.textContent = text }
  showLocationAccuracy(accuracy) {
    if (!Number.isFinite(accuracy)) return
    const meters = Math.max(1, Math.round(accuracy))
    this.message(accuracy > 100 ? `Approximate location (about ${meters} m). Move the map to fine-tune.` : `Current location found (about ${meters} m accuracy).`)
  }
  clearCoordinates() { this.latitudeTarget.value = ""; this.longitudeTarget.value = "" }
  samePoint(a, b) { return !!b && Math.abs(a.lat - b.lat) < 0.000001 && Math.abs(a.lng - b.lng) < 0.000001 }

  areaEdited() {
    this.revision++
    this.pending = false
    this.dragging = false
    this.dirty = true
    this.clearCoordinates()
    this.showLocation(this.areaTarget.value.trim() ? (this.map ? "Location not confirmed" : this.areaTarget.value.trim()) : "Choose a meeting point")
    this.message(this.map ? "Search to set the pin" : "Map unavailable. Enter an area instead.")
  }

  areaLabel(results) {
    // Prefer neighborhood and city instead of a street number or private address.
    const result = results?.[0]
    if (!result) return null
    const components = result.address_components || []
    const component = (...types) => components.find(item => types.some(type => item.types.includes(type)))?.long_name
    const neighborhood = component("neighborhood", "sublocality_level_2") || component("sublocality_level_1", "sublocality")
    const city = component("locality", "postal_town", "administrative_area_level_2")
    const region = component("administrative_area_level_1")
    return [...new Set([neighborhood, city, region].filter(Boolean))].join(", ") || null
  }

  choose(point, label, move = false) {
    if (!this.active) return
    this.lastCenter = point
    this.latitudeTarget.value = point.lat
    this.longitudeTarget.value = point.lng
    this.areaTarget.value = label
    this.pending = false
    this.dirty = false
    this.dragging = false
    if (move) this.map.setCenter(point)
    this.showLocation(label === "Selected on map" ? "Pinned location" : label)
    this.message(label === "Selected on map" ? "Pin set · area name unavailable" : "Meeting point set · move the map to change")
  }

  async choosePin(point, move = false, accuracy = null) {
    const version = ++this.revision
    this.lastCenter = point
    this.pending = true
    this.dirty = false
    this.dragging = false
    this.clearCoordinates()
    if (move) this.map.setCenter(point)
    this.showLocation("Finding area…")
    this.message("Finding the name of your meeting point…")
    try {
      const { results } = await this.geocoder.geocode({ location: point })
      if (!this.active || version !== this.revision) return
      this.choose(point, this.areaLabel(results) || "Selected on map")
      this.showLocationAccuracy(accuracy)
    } catch (_) {
      if (this.active && version === this.revision) {
        this.choose(point, "Selected on map")
        this.showLocationAccuracy(accuracy)
      }
    }
  }

  locate() {
    if (!this.map || !navigator.geolocation) { this.message("Use search or move the map to choose a location"); return }
    const version = ++this.revision
    this.pending = true
    this.message("Finding your location…")
    navigator.geolocation.getCurrentPosition(({ coords }) => {
      if (!this.active || version !== this.revision) return
      const point = { lat: coords.latitude, lng: coords.longitude }
      const accuracy = Number.isFinite(coords.accuracy) ? coords.accuracy : null
      this.map.setZoom(accuracy === null || accuracy > 500 ? 15 : accuracy > 100 ? 16 : 18)
      this.choosePin(point, true, accuracy)
    }, () => {
      if (this.active && version === this.revision) {
        this.pending = false
        this.message("Location unavailable. Search or move the map.")
      }
    }, { enableHighAccuracy: true, timeout: 20000, maximumAge: 0 })
  }

  async search(event) {
    event.preventDefault()
    const area = this.areaTarget.value.trim()
    if (!area || area === "Selected on map" || !this.geocoder) return
    const version = ++this.revision
    this.pending = true
    this.dirty = true
    this.clearCoordinates()
    this.showLocation("Searching…")
    this.message("Searching for your meeting point…")
    try {
      const { results } = await this.geocoder.geocode({ address: area, componentRestrictions: { country: "JP" } })
      if (!this.active || version !== this.revision) return
      if (!results.length) throw new Error("No location")
      this.choose(results[0].geometry.location.toJSON(), area, true)
    } catch (_) {
      if (this.active && version === this.revision) {
        this.pending = false
        this.showLocation("Location not found")
        this.message("Try another area or move the map.")
      }
    }
  }

  submit(event) {
    const center = this.map?.getCenter()?.toJSON()
    const unconfirmed = this.map && (this.dirty || !this.latitudeTarget.value || !this.longitudeTarget.value || (center && !this.samePoint(center, this.lastCenter)))
    if (this.pending || this.dragging || unconfirmed || (this.areaTarget.value === "Selected on map" && !this.latitudeTarget.value)) {
      event.preventDefault()
      this.message(this.pending ? "Finding your meeting point. Try again in a moment." : "Search or move the pin to confirm your meeting point first.")
    }
  }
  decrease() { this.peopleTarget.value = Math.max(2, (Number(this.peopleTarget.value) || 2) - 1) }
  increase() { this.peopleTarget.value = Math.min(50, (Number(this.peopleTarget.value) || 2) + 1) }
}
