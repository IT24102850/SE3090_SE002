export type AppTheme = 'light' | 'dark' | 'system';

const THEME_STORAGE_KEYS = ['unify-theme', 'unify-home-theme'] as const;

export function getStoredTheme(): AppTheme {
  for (const key of THEME_STORAGE_KEYS) {
    const stored = localStorage.getItem(key);
    if (stored === 'light' || stored === 'dark' || stored === 'system') return stored;
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function applyTheme(theme: AppTheme): void {
  const root = document.documentElement;
  const resolvedTheme = theme === 'system'
    ? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
    : theme;
  root.dataset.theme = resolvedTheme;
  root.dataset.unifyTheme = resolvedTheme;
  for (const key of THEME_STORAGE_KEYS) {
    localStorage.setItem(key, theme);
  }
}
