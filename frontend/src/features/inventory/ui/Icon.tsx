export function Icon({ name, className, size: requestedSize = 18 }: { name: string; className?: string; size?: number }) {
  const size = requestedSize;
  const stroke = 'currentColor';
  const strokeWidth = 1.6;
  switch (name) {
    case 'stocksense':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <defs>
            <linearGradient id="stocksense-mark-gradient" x1="5" y1="7" x2="43" y2="41" gradientUnits="userSpaceOnUse">
              <stop stopColor="#67E8F9"/><stop offset=".52" stopColor="#60A5FA"/><stop offset="1" stopColor="#C4B5FD"/>
            </linearGradient>
          </defs>
          <path d="m7 16 17-9 17 9v16L24 42 7 32V16Z" stroke="url(#stocksense-mark-gradient)" strokeWidth="2.5" strokeLinejoin="round"/>
          <path d="m8 16.5 16 9 16-9M24 26v15" stroke="url(#stocksense-mark-gradient)" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/>
          <path d="m31.5 10 1.8-3.7L35 10l3.7 1.8L35 13.5l-1.7 3.7-1.8-3.7-3.7-1.7 3.7-1.8Z" fill="#A5F3FC" stroke="#E0F2FE" strokeWidth=".8" strokeLinejoin="round"/>
          <circle cx="17" cy="29" r="1.5" fill="#A5F3FC"/>
          <circle cx="31" cy="29" r="1.5" fill="#C4B5FD"/>
        </svg>
      );
    case 'inventory':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="m3 7 9-4 9 4v10l-9 4-9-4V7Z" stroke={stroke} strokeWidth={strokeWidth} strokeLinejoin="round"/>
          <path d="m3.5 7.5 8.5 4 8.5-4M12 11.5V21" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    case 'supplier':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M3 10 4.5 4h15L21 10M4 10v10h16V10M3 10a2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
          <path d="M9 20v-5h6v5M7 7h.01M12 7h.01M17 7h.01" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'branch':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M3 21V8l6-4v17M9 10h12v11M6 8h.01M6 12h.01M6 16h.01M13 14h.01M17 14h.01M13 18h.01M17 18h.01M2 21h20" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'alert':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M12 3 2.8 19a1.3 1.3 0 0 0 1.1 2h16.2a1.3 1.3 0 0 0 1.1-2L12 3Z" stroke={stroke} strokeWidth={strokeWidth} strokeLinejoin="round"/>
          <path d="M12 9v4.5M12 17h.01" stroke={stroke} strokeWidth="2" strokeLinecap="round"/>
        </svg>
      );
    case 'po':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M7 3.75h7l4 4V20a1.25 1.25 0 01-1.25 1.25h-9.5A1.25 1.25 0 016 20V5a1.25 1.25 0 011-1.25Z" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
          <path d="M14 4v4h4M9 12h6M9 15.5h6M9 19h3" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'movement':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
          <path d="M3 7h11m0 0-3-3m3 3-3 3M21 17H10m0 0 3-3m-3 3 3 3" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
          <path d="M5 14v6m-2-2 2 2 2-2M19 10V4m-2 2 2-2 2 2" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'predict':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M3 12h3l3 8 4-16 4 10 3-4h1" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    case 'info':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="12" cy="12" r="9" stroke={stroke} strokeWidth={strokeWidth}/>
          <path d="M12 8v.01" stroke={stroke} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M11.5 12h1v4h-1z" stroke={stroke} strokeWidth={1} strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    case 'approve':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M20 6L9 17l-5-5" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'reject':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M18 6L6 18M6 6l12 12" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'chart':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M3 3v18h18" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
          <path d="M7 14l3-4 4 6 5-10" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    case 'workflow':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M3 12h4l3 3 5-6 6 6" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      );
    default:
      return <span />;
  }
}
