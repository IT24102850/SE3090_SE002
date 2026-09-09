export const roles = ['Admin', 'Manager', 'Staff'] as const;
export type Role = (typeof roles)[number];

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (roles as readonly string[]).some(
    (role) => role.toLowerCase() === value.toLowerCase()
  );
}

export const roleAccess = {
  Admin: ['analytics', 'inventory', 'stock-movements', 'purchase-orders', 'agent-workflows', 'low-stock-alerts', 'branch-overview'],
  Manager: ['analytics', 'inventory', 'stock-movements', 'purchase-orders', 'low-stock-alerts', 'branch-overview'],
  Staff: ['inventory', 'stock-movements', 'low-stock-alerts'],
} as const satisfies Record<Role, readonly string[]>;
