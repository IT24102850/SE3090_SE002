import { useEffect, useState, type KeyboardEvent } from 'react';
import L, { type LatLngExpression, type LeafletMouseEvent } from 'leaflet';
import { MapContainer, Marker, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

export interface DeliveryPin {
  latitude: number;
  longitude: number;
}

interface PlaceResult extends DeliveryPin {
  id: string;
  label: string;
}

interface DeliveryLocationPickerProps {
  value: DeliveryPin | null;
  onChange: (pin: DeliveryPin | null) => void;
}

const DEFAULT_CENTER: LatLngExpression = [6.9271, 79.8612];
const deliveryPinIcon = L.divIcon({
  className: 'cust-delivery-leaflet-pin',
  html: '<span aria-hidden="true">📍</span>',
  iconSize: [32, 38],
  iconAnchor: [16, 36],
});

function MapCenter({ center }: { center: LatLngExpression }) {
  const map = useMap();
  useEffect(() => {
    map.setView(center, map.getZoom(), { animate: true });
  }, [center, map]);
  return null;
}

function ClickToPlacePin({ onChange }: { onChange: (pin: DeliveryPin) => void }) {
  useMapEvents({
    click(event: LeafletMouseEvent) {
      onChange({ latitude: event.latlng.lat, longitude: event.latlng.lng });
    },
  });
  return null;
}

export default function DeliveryLocationPicker({ value, onChange }: DeliveryLocationPickerProps) {
  const [search, setSearch] = useState('');
  const [center, setCenter] = useState<LatLngExpression>(value
    ? [value.latitude, value.longitude]
    : DEFAULT_CENTER);
  const [results, setResults] = useState<PlaceResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState('');
  const [locating, setLocating] = useState(false);

  useEffect(() => {
    if (value) setCenter([value.latitude, value.longitude]);
  }, [value]);

  async function searchPlaces() {
    const query = search.trim();
    if (!query) return;
    setSearching(true);
    setError('');
    setResults([]);
    try {
      const url = new URL('https://nominatim.openstreetmap.org/search');
      url.search = new URLSearchParams({ format: 'jsonv2', limit: '5', q: query }).toString();
      const response = await fetch(url);
      if (!response.ok) throw new Error('Place search is temporarily unavailable.');
      const places = await response.json() as Array<{ place_id: number; lat: string; lon: string; display_name: string }>;
      setResults(places.map((place) => ({
        id: String(place.place_id),
        latitude: Number(place.lat),
        longitude: Number(place.lon),
        label: place.display_name,
      })));
      if (!places.length) setError('No places found. Try a nearby town or landmark.');
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : 'Place search failed. Try again.');
    } finally {
      setSearching(false);
    }
  }

  function placePin(pin: DeliveryPin) {
    onChange(pin);
    setCenter([pin.latitude, pin.longitude]);
    setResults([]);
    setError('');
  }

  function useCurrentLocation() {
    setError('');
    if (!navigator.geolocation) {
      setError('Location is unavailable here. Search for a place or tap the map instead.');
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        placePin({ latitude: coords.latitude, longitude: coords.longitude });
        setLocating(false);
      },
      (failure) => {
        setError(failure.code === failure.PERMISSION_DENIED
          ? 'Location access was declined. You can search or tap the map to place a pin.'
          : 'We could not read your location. You can search or tap the map instead.');
        setLocating(false);
      },
      { enableHighAccuracy: true, timeout: 12000, maximumAge: 30000 },
    );
  }

  return (
    <section className="cust-delivery-map" aria-label="Choose delivery location">
      <div className="cust-delivery-map-search">
        <label className="cust-shop-field">
          <span>Search for an address, place or landmark</span>
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            maxLength={180}
            placeholder="e.g. Colombo, Sri Lanka"
            aria-label="Search delivery location"
            onKeyDown={(event: KeyboardEvent<HTMLInputElement>) => {
              if (event.key === 'Enter') {
                event.preventDefault();
                void searchPlaces();
              }
            }}
          />
        </label>
        <button className="btn btn-secondary" type="button" onClick={() => void searchPlaces()} disabled={searching || !search.trim()}>
          {searching ? 'Searching…' : 'Search'}
        </button>
      </div>
      {results.length > 0 && (
        <ul className="cust-delivery-map-results" aria-label="Place search results">
          {results.map((result) => (
            <li key={result.id}>
              <button type="button" onClick={() => placePin(result)}>
                <span aria-hidden="true">⌖</span> {result.label}
              </button>
            </li>
          ))}
        </ul>
      )}
      {error && <p className="cust-shop-error" role="status">{error}</p>}
      <div className="cust-delivery-map-canvas" aria-label="Map: tap to place or move your delivery pin">
        <MapContainer center={center} zoom={13} scrollWheelZoom className="cust-delivery-leaflet">
          <MapCenter center={center} />
          <ClickToPlacePin onChange={placePin} />
          <TileLayer
            attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          {value && <Marker
            position={[value.latitude, value.longitude]}
            icon={deliveryPinIcon}
            keyboard
            title="Delivery pin; tap the map to move it"
          />}
        </MapContainer>
        <div className="cust-delivery-map-hint"><span aria-hidden="true">⌖</span> Tap the map to drop or move your pin</div>
      </div>
      <div className="cust-delivery-map-footer">
        <button type="button" className="btn btn-secondary" onClick={useCurrentLocation} disabled={locating}>
          {locating ? 'Finding you…' : '◎ Use my current location'}
        </button>
        {value ? (
          <>
            <span className="cust-delivery-pin-coordinates" role="status">
              Pin set · {value.latitude.toFixed(5)}, {value.longitude.toFixed(5)}
            </span>
            <button type="button" className="cust-shop-clear-pin" onClick={() => onChange(null)}>Remove pin</button>
          </>
        ) : <span className="cust-delivery-pin-coordinates">No pin selected</span>}
      </div>
    </section>
  );
}
