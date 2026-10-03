import { Icon } from './Icon';

/** Decorative, card-contained motion shared by every inventory header. */
export function InventoryHeroArtwork({ icon = 'box' }: { icon?: string }) {
  return (
    <div className="inventory-hero-artwork" aria-hidden="true">
      <span className="inventory-hero-artwork-ring" />
      <span className="inventory-hero-artwork-tile">
        {icon === 'box' ? (
          <svg width="54" height="54" viewBox="0 0 64 64" fill="none">
            <path d="M8 20 32 8l24 12-24 13L8 20Z" fill="#E7BD8E" />
            <path d="M8 20v27l24 14V33L8 20Z" fill="#B98564" />
            <path d="M32 33v28l24-14V20L32 33Z" fill="#DDA579" />
            <path d="m22 13 24 13v11l-8 5V30L14 17l8-4Z" fill="#F5D5A8" />
            <path d="m14 40 7 4v8l-7-4v-8Z" fill="#F1C59E" />
          </svg>
        ) : <Icon name={icon} size={46} />}
        <span className="inventory-hero-artwork-sparkle">✦</span>
        <span className="inventory-hero-artwork-sparkle inventory-hero-artwork-sparkle-small">✧</span>
      </span>
      <span className="inventory-hero-artwork-dot" />
    </div>
  );
}
