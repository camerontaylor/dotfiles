---
name: tailwind-variants
description: "tailwind-variants (tv) API for type-safe component variants, slots, compound variants, composition, and class merging. Use when building variant-driven components with Tailwind CSS."
---

# tailwind-variants (`tv`)

Type-safe, first-class variant API for Tailwind CSS. Provides `tv()` for defining component variants, slots, compound variants, and composable component hierarchies — with full TypeScript inference.

Package: `tailwind-variants` (MIT, heroui-inc/tailwind-variants)

## When to Use This Skill

- Defining multi-variant component styles (color, size, state, etc.)
- Splitting a component into named **slots** (base, trigger, content, icon, etc.)
- Composing/extending component styles via `extend`
- Replacing hand-rolled `clsx`/`cx` conditional class logic
- Migrating from CVA, PandaCSS `cva`/`sva`, or Emotion `styled()` to Tailwind
- Extracting `VariantProps<typeof component>` for prop typing

## Installation

```bash
# Full build (includes tailwind-merge for conflict resolution)
pnpm add tailwind-variants tailwind-merge

# Lite build (~80% smaller, no conflict resolution)
# import from 'tailwind-variants/lite'
```

---

## Core API

### `tv(options, config?)` — Define a component

```ts
import { tv } from 'tailwind-variants';

const button = tv({
  base: 'font-medium rounded-full active:opacity-80',
  variants: {
    color: {
      primary: 'bg-blue-500 text-white',
      secondary: 'bg-purple-500 text-white',
      danger: 'bg-red-500 text-white',
    },
    size: {
      sm: 'text-sm px-3 py-1',
      md: 'text-base px-4 py-2',
      lg: 'text-lg px-6 py-3',
    },
    disabled: {
      true: 'opacity-50 pointer-events-none',
    },
  },
  compoundVariants: [
    {
      color: 'primary',
      size: 'lg',
      class: 'uppercase tracking-wide',
    },
    {
      color: ['primary', 'secondary'],
      disabled: true,
      class: 'bg-gray-300 text-gray-500',
    },
  ],
  defaultVariants: {
    color: 'primary',
    size: 'md',
  },
});
```

**Usage:**
```tsx
<button className={button({ color: 'danger', size: 'lg' })}>Delete</button>
<button className={button()}>Default (primary/md)</button>

// Override with className (merges, doesn't replace)
<button className={button({ color: 'primary', className: 'mt-4' })}>Spaced</button>
```

### Options Reference

| Key | Type | Description |
|-----|------|-------------|
| `base` | `ClassValue` | Always-applied base classes |
| `variants` | `Record<string, Record<string, ClassValue>>` | Named variant groups with named values |
| `defaultVariants` | `Record<string, string>` | Fallback variant selections |
| `compoundVariants` | `Array<VariantMatch & { class: ClassValue }>` | Conditional styles when multiple variants match |
| `compoundSlots` | `Array<{ slots: string[] } & VariantMatch & { class: ClassValue }>` | Apply classes to multiple slots at once |
| `slots` | `Record<string, ClassValue>` | Named sub-parts of a component |
| `extend` | `TVReturnType` | Inherit from another `tv()` definition |

### Config (2nd argument)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `twMerge` | `boolean` | `true` | Enable tailwind-merge conflict resolution |
| `twMergeConfig` | `TwMergeConfig` | `{}` | Custom tailwind-merge config |

---

## Slots — Multi-part Components

Use `slots` when a component has distinct DOM elements that need independent styling.

```ts
const card = tv({
  slots: {
    base: 'bg-white rounded-xl shadow-md overflow-hidden',
    header: 'px-6 py-4 border-b border-gray-100',
    title: 'text-lg font-semibold text-gray-900',
    body: 'px-6 py-4',
    footer: 'px-6 py-3 bg-gray-50 flex justify-end gap-2',
  },
  variants: {
    size: {
      sm: {
        base: 'max-w-sm',
        header: 'px-4 py-2',
        title: 'text-base',
        body: 'px-4 py-2',
        footer: 'px-4 py-2',
      },
      lg: {
        base: 'max-w-2xl',
        title: 'text-xl',
      },
    },
    elevated: {
      true: {
        base: 'shadow-xl',
      },
    },
  },
  defaultVariants: {
    size: 'sm',
  },
});
```

**Usage — destructure slots:**
```tsx
const { base, header, title, body, footer } = card({ size: 'lg', elevated: true });

<div className={base()}>
  <div className={header()}>
    <h2 className={title()}>Card Title</h2>
  </div>
  <div className={body()}>Content here</div>
  <div className={footer()}>
    <button>Cancel</button>
    <button>Save</button>
  </div>
</div>
```

**Key:** Each slot returns a **function** — call it with `()` to get the class string. You can pass `{ className }` to merge additional classes per-slot:

```tsx
<div className={base({ className: 'mt-8' })}>...</div>
```

### Compound Slots — Shared classes across multiple slots

```ts
const pagination = tv({
  slots: {
    item: 'data-[active=true]:bg-blue-500',
    prev: 'data-[disabled=true]:opacity-50',
    next: 'data-[disabled=true]:opacity-50',
  },
  compoundSlots: [
    {
      slots: ['item', 'prev', 'next'],
      class: 'flex items-center justify-center rounded-full w-9 h-9',
    },
    {
      slots: ['prev', 'next'],
      class: 'bg-gray-100',
    },
  ],
});
```

---

## Compound Variants — Conditional multi-variant styles

Match when **all** listed variant conditions are true:

```ts
const input = tv({
  base: 'border rounded px-3 py-2',
  variants: {
    variant: { outlined: 'border-2', filled: 'bg-gray-100 border-transparent' },
    severity: { error: '', warning: '', success: '' },
    size: { sm: 'text-sm', md: 'text-base' },
  },
  compoundVariants: [
    // Single match
    { variant: 'outlined', severity: 'error', class: 'border-red-500 text-red-700' },
    { variant: 'outlined', severity: 'warning', class: 'border-yellow-500 text-yellow-700' },
    // Array match (OR within a variant)
    { severity: ['error', 'warning'], size: 'sm', class: 'font-semibold' },
  ],
});
```

**With slots** — use a record for `class`:
```ts
compoundVariants: [
  {
    variant: 'outlined',
    severity: 'error',
    class: {
      root: 'border-red-500',
      label: 'text-red-700',
      helperText: 'text-red-500',
    },
  },
],
```

---

## Composition — `extend`

Build component hierarchies by extending a base definition:

```ts
const baseButton = tv({
  base: 'font-semibold rounded-full transition-colors',
  variants: {
    color: {
      primary: 'bg-blue-500 text-white hover:bg-blue-600',
      secondary: 'bg-gray-200 text-gray-800 hover:bg-gray-300',
    },
    size: {
      sm: 'text-sm px-3 py-1',
      md: 'text-base px-4 py-2',
      lg: 'text-lg px-6 py-3',
    },
  },
  defaultVariants: { color: 'primary', size: 'md' },
});

const iconButton = tv({
  extend: baseButton,
  base: 'inline-flex items-center gap-2',
  variants: {
    iconPosition: {
      left: 'flex-row',
      right: 'flex-row-reverse',
    },
  },
  defaultVariants: { iconPosition: 'left' },
});

// iconButton inherits color + size variants, gains iconPosition
iconButton({ color: 'secondary', size: 'lg', iconPosition: 'right' });
```

**What `extend` merges:**
- `base` — child appended after parent
- `variants` — deep merged (child overrides same-name variant values)
- `defaultVariants` — shallow merged (child wins)
- `compoundVariants` — concatenated (parent + child)
- `slots` — deep merged

---

## TypeScript

### Extract variant props

```ts
import { tv, type VariantProps } from 'tailwind-variants';

const button = tv({
  base: 'rounded-full',
  variants: {
    color: { primary: 'bg-blue-500', secondary: 'bg-gray-200' },
    size: { sm: 'text-sm', md: 'text-base', lg: 'text-lg' },
  },
});

type ButtonVariants = VariantProps<typeof button>;
// { color?: 'primary' | 'secondary'; size?: 'sm' | 'md' | 'lg' }

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement>, ButtonVariants {
  children: React.ReactNode;
}

function Button({ color, size, children, className, ...props }: ButtonProps) {
  return (
    <button className={button({ color, size, className })} {...props}>
      {children}
    </button>
  );
}
```

### Typed slots component

```ts
const card = tv({
  slots: {
    base: 'rounded-xl',
    title: 'font-bold',
    body: 'text-gray-600',
  },
  variants: {
    size: { sm: { base: 'p-3' }, lg: { base: 'p-6' } },
  },
});

type CardVariants = VariantProps<typeof card>;
type CardSlots = ReturnType<typeof card>;

function Card({ size, className }: CardVariants & { className?: string }) {
  const { base, title, body } = card({ size });
  return (
    <div className={base({ className })}>
      <h3 className={title()}>Title</h3>
      <p className={body()}>Body</p>
    </div>
  );
}
```

---

## Utility Functions

### `cn(...values)` — Merge with conflict resolution (v3.2.2+)
```ts
import { cn } from 'tailwind-variants';
cn('px-4 py-2', 'px-6');  // → 'py-2 px-6'
```

### `cx(...values)` — Lightweight concat (no merge)
```ts
import { cx } from 'tailwind-variants';
cx('px-4', condition && 'text-red-500', ['rounded', 'shadow']);
```

### `createTV(config)` — Custom `tv` instance
```ts
import { createTV } from 'tailwind-variants';

const tv = createTV({
  twMerge: true,
  twMergeConfig: {
    classGroups: {
      'font-size': [{ text: ['tiny', 'huge'] }],
    },
  },
});
```

---

## Migration from PandaCSS `cva`/`sva`

| PandaCSS | tailwind-variants |
|----------|-------------------|
| `cva({ base: {}, variants: {} })` | `tv({ base: '', variants: {} })` |
| `sva({ slots: [], base: {}, variants: {} })` | `tv({ slots: {}, variants: {} })` — slots is an object, not array |
| CSS property objects `{ bg: 'red.500' }` | Tailwind class strings `'bg-red-500'` |
| `recipe.variantMap` | `component.variantKeys` |
| Token references `{ color: '{colors.blue.500}' }` | Tailwind classes `'text-blue-500'` |
| `compoundVariants[].css` | `compoundVariants[].class` |

### Before (PandaCSS `cva`):
```ts
const button = cva({
  base: { display: 'flex', alignItems: 'center', fontWeight: 'semibold' },
  variants: {
    visual: {
      solid: { bg: 'blue.500', color: 'white' },
      outline: { borderWidth: '1px', borderColor: 'blue.500' },
    },
  },
});
// Usage: <button className={button({ visual: 'solid' })} />
```

### After (tailwind-variants `tv`):
```ts
const button = tv({
  base: 'flex items-center font-semibold',
  variants: {
    visual: {
      solid: 'bg-blue-500 text-white',
      outline: 'border border-blue-500',
    },
  },
});
// Usage: <button className={button({ visual: 'solid' })} />
```

### PandaCSS `sva` → `tv` with slots:
```ts
// Before (sva)
const card = sva({
  slots: ['root', 'title', 'body'],
  base: { root: { p: '4' }, title: { fontWeight: 'bold' }, body: { color: 'gray.600' } },
});
const styles = card({ size: 'lg' });
// styles.root, styles.title — these are class strings

// After (tv)
const card = tv({
  slots: { root: 'p-4', title: 'font-bold', body: 'text-gray-600' },
});
const { root, title, body } = card({ size: 'lg' });
// root(), title(), body() — these are functions, call them!
```

> **Critical difference:** PandaCSS slot values are strings. `tv` slot values are **functions** — you must call them: `root()` not `root`.

---

## Common Patterns

### Boolean variants
```ts
variants: {
  disabled: { true: 'opacity-50 cursor-not-allowed' },
  fullWidth: { true: 'w-full' },
}
// Usage: button({ disabled: true, fullWidth: true })
// Falsy values use base styles (no class applied)
```

### Responsive override at call site
```tsx
// tv doesn't have built-in responsive variants — use Tailwind's responsive prefixes directly
const box = tv({
  variants: {
    padding: {
      sm: 'p-2',
      md: 'p-4',
      lg: 'p-8',
    },
  },
});
// For responsive behavior, compose at the call site:
<div className={cn(box({ padding: 'sm' }), 'md:p-4 lg:p-8')} />
```

### Forwarding variants through wrapper components
```ts
const inner = tv({ variants: { size: { sm: 'text-sm', lg: 'text-lg' } } });
const outer = tv({
  extend: inner,
  base: 'border rounded',
});
// outer inherits size from inner — no manual forwarding needed
```

---

## Return Value Properties

The function returned by `tv()` also exposes metadata:

| Property | Type | Description |
|----------|------|-------------|
| `.base` | `string` | Raw base classes |
| `.slots` | `Record<string, string>` | Raw slot base classes |
| `.variants` | `object` | Variant definitions |
| `.variantKeys` | `string[]` | List of variant names |
| `.defaultVariants` | `object` | Default variant values |
| `.compoundVariants` | `array` | Compound variant rules |
