import type { ReactNode } from 'react';

export const badgeTones = [
  'green',
  'amber',
  'red',
  'blue',
  'violet',
  'slate',
] as const;
export type BadgeTone = (typeof badgeTones)[number];

export function Badge({
  tone = 'slate',
  children,
  icon,
}: {
  tone?: BadgeTone;
  children: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <span className={`badge badge-${tone}`} style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '0.28rem 0.6rem', transition: 'transform .18s ease, box-shadow .18s ease' }}>
      {icon && <span style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 16, height: 16 }}>{icon}</span>}
      <span style={{ display: 'inline-block' }}>{children}</span>
    </span>
  );
}

