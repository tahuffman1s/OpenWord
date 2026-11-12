import type { ComponentChildren } from 'preact';
import { Icon, type IconName } from './icon';

export interface TabItem<T> {
  value: T;
  label: ComponentChildren;
  icon?: IconName | string;
}

export function Tabs<T>({ tabs, selected, onSelect, scroll }: { tabs: TabItem<T>[]; selected: T; onSelect: (v: T) => void; scroll?: boolean }) {
  return (
    <div class={`m3-tabs${scroll ? ' m3-tabs--scroll' : ''}`} role="tablist">
      {tabs.map((t) => (
        <button
          type="button"
          role="tab"
          aria-selected={t.value === selected}
          class={`m3-tab m3-interactive${t.value === selected ? ' m3-tab--selected' : ''}`}
          onClick={() => onSelect(t.value)}
        >
          {t.icon && <Icon name={t.icon} />}
          {t.label}
        </button>
      ))}
    </div>
  );
}

export interface NavDestination<T> {
  value: T;
  label: string;
  icon: IconName | string;
  selectedIcon?: IconName | string;
  /** A dot, or a count, beside the icon. */
  badge?: boolean | number;
}

/** Material's navigation bar, along the bottom. */
export function NavigationBar<T>({ destinations, selected, onSelect }: { destinations: NavDestination<T>[]; selected: T; onSelect: (v: T) => void }) {
  return (
    <nav class="m3-nav-bar">
      {destinations.map((d) => {
        const on = d.value === selected;
        return (
          <button type="button" aria-current={on ? 'page' : undefined} class={`m3-nav-item${on ? ' m3-nav-item--selected' : ''}`} onClick={() => onSelect(d.value)}>
            <span class="m3-nav-item__pill m3-interactive">
              <Icon name={on && d.selectedIcon ? d.selectedIcon : d.icon} />
              {d.badge === true && <span class="m3-badge" />}
              {typeof d.badge === 'number' && d.badge > 0 && <span class="m3-badge m3-badge--count">{d.badge > 99 ? '99+' : d.badge}</span>}
            </span>
            {d.label}
          </button>
        );
      })}
    </nav>
  );
}
