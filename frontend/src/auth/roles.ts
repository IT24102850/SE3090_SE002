export const roles = ['Admin', 'Manager', 'Staff'] as const;
export type Role = (typeof roles)[number];

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (roles as readonly string[]).some(
    (role) => role.toLowerCase() === value.toLowerCase()
  );
}
