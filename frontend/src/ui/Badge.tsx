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
    <span className={`badge badge-${tone}`} style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
      {icon}
      {children}
    </span>
  );
}

