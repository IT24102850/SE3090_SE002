import React from 'react';

export function Icon({ name, className }: { name: string; className?: string }) {
  const size = 16;
  switch (name) {
    case 'po':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M9 11V7a2 2 0 012-2h6" stroke="#1f2937" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M21 15v2a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2" stroke="#1f2937" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M16 3v4" stroke="#1f2937" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    case 'predict':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M3 12h3l3 8 4-16 4 10 3-4h1" stroke="#1f2937" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    case 'info':
      return (
        <svg className={className} width={size} height={size} viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <circle cx="12" cy="12" r="9" stroke="#1f2937" strokeWidth="1.5"/>
          <path d="M12 8v.01" stroke="#1f2937" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
          <path d="M11.5 12h1v4h-1z" stroke="#1f2937" strokeWidth="1" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      );
    default:
      return <span />;
  }
}
