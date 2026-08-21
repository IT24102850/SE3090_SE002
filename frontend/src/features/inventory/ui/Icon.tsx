export function Icon({ name, className }: { name: string; className?: string }) {
  const size = 18;
  const stroke = 'currentColor';
  const strokeWidth = 1.6;
  switch (name) {
    case 'po':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M9 11V7a2 2 0 012-2h6" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M21 15v2a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2" stroke={stroke} strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M16 3v4" stroke={stroke} strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"/>
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
