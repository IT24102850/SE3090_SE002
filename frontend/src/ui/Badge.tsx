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
}: {
  tone?: BadgeTone;
  children: ReactNode;
}) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}
