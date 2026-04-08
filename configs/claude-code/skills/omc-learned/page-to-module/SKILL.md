---
name: page-to-module
description: Convert Webfront custom-modules page configs into proper TypeScript packages with explicit imports
triggers:
  - page-to-module
  - pageToModule
  - custom-module
  - convert page
  - standardise page
  - standardize page
  - display-page-globals
  - remove S magic
argument-hint: "<path-to-page-import-dir>"
---

# Page-to-Module Conversion Skill

## Purpose

Convert Webfront "custom-modules" page configurations (which use runtime-injected globals and a shared `S` object) into proper TypeScript packages with explicit imports, direct dependencies, and standard ESM exports.

## When to Activate

- User asks to convert a page-import directory or custom-module to proper TypeScript
- User mentions removing `S` magic, `display-page-globals`, or converting custom-modules
- Files contain patterns like `S.componentName`, `W.something`, or bare `observer()` without imports
- Directory structure matches the page-to-module pattern: `page-import/` with `page.meta.ts`, `modules.ts`, `preload.tsx`, `prepare.tsx`, `template.tsx`, etc.

## Background: The Custom-Modules System

### The `S` Object Pattern

Custom-modules pages use a shared mutable object `S: Record<string, any>` defined in `page.meta.ts`. The page-to-module compiler auto-assigns each script's default export onto `S`:
- `export default MyComponent` in `MyComponent.tsx` becomes `S.MyComponent` at runtime
- `export default { Foo, Bar }` in `helpers.tsx` becomes `S.helpers.Foo`, `S.helpers.Bar`

This enables late-binding cross-references between scripts without circular imports, but sacrifices type safety and discoverability.

### The `display-page-globals.d.ts` Globals

Custom-modules have ~20 ambient globals injected at runtime. These are declared in:
`vendor/gears/core/src/custom-modules/display-page-globals.d.ts`

## Global-to-Import Mapping

This is the critical reference table. Every global used in custom-modules maps to a specific import:

### Core Webfront Globals

| Global | Import |
|--------|--------|
| `W` | `import { W } from '@webfront/core/react-components/WebfrontRegistry'` (only for runtime-only members; prefer direct imports below) |
| `registry` | `import { registry } from '@webfront/core/react-components/WebfrontRegistry'` |
| `loader` | `import { loader } from '@webfront/core/modules/Loader'` |
| `gearsState` | `import { gearsState } from '@webfront/core/gears/GearsState'` |

### Third-Party Globals

| Global | Import |
|--------|--------|
| `React` | `import React from 'react'` |
| `useEffect` / `useMemo` etc. | `import React, { useEffect } from 'react'` |
| `observer` | `import { observer } from 'mobx-react-lite'` |
| `Observer` | `import { Observer } from 'mobx-react-lite'` |
| `mobx` | `import * as mobx from 'mobx'` |
| `styled` | `import styled from '@emotion/styled'` |
| `css` | `import { css } from '@emotion/react'` |
| `classnames` | `import classnames from 'classnames'` |
| `_` (lodash) | `import _ from 'lodash'` |
| `$` (jQuery) | `import $ from 'jquery'` |

### Runtime Globals (no module export — use `declare const`)

| Global | Declaration |
|--------|-------------|
| `displayPageId` | `declare const displayPageId: (e: TemplateStringsArray) => string;` — set in PageState.ts on `(global as any)` |
| `getComponent` | `declare const getComponent: (name: string) => any;` — set in Compiler.ts |
| `AppNav` | `declare const AppNav: (user: any) => any[];` — injected by app-specific bootstrap |

## W Member to Direct Import Mapping

The `W` object is the Webfront runtime registry. Its members come from `Loader.ts` module chunks registered via `registerModule()`. **Prefer direct imports over `W.xxx`** — the W object requires runtime initialization which standalone packages won't have.

Reference: `vendor/gears/core/src/modules/Loader.ts` maps each `@memoizedLoader` getter to a chunk file.

### Forms (from `coreForms` → `gears/Forms/Core` which re-exports `gears/Forms/`)

| W reference | Direct import |
|-------------|---------------|
| `W.Form` | `import { Form } from '@webfront/core/gears/Forms'` |
| `W.Form.Field` / `{ Field } = W.Form` | `import { Field } from '@webfront/core/gears/Forms'` |
| `W.Form.NavItem` / `{ NavItem } = W.Form` | `import { NavItem } from '@webfront/core/gears/Forms'` |
| `W.Form.Section` | `import { FormSection } from '@webfront/core/gears/Forms'` |
| `W.FieldTypes` | `import { FieldTypes } from '@webfront/core/gears/Forms/FieldType'` |
| `W.autoFormContents()` | `import { autoFormContents } from '@webfront/core/gears/Forms/Form/auto'` |
| `W.useFormData()` | `import { useFormData } from '@webfront/core/gears/Forms/FormDataState'` |
| `W.useFormConfig()` | `import { useFormConfig } from '@webfront/core/gears/Forms/Form/FormConfig'` |
| `W.useFormTheme()` | `import { useFormTheme } from '@webfront/core/gears/Forms/FormTheme/useFormTheme'` |
| `W.MergeViewer` | `import { MergeViewer } from '@webfront/core/gears/Forms/Editors'` |
| `W.ContentEditableEditor` | `import { ContentEditableEditor } from '@webfront/core/gears/Forms/Editors'` |
| `W.coreForms.ListItemForm` | `import { ListItemForm } from '@webfront/core/gears/Forms/Core/ListItemForm'` |
| `W.forms.navUtil` | `import { navUtil } from '@webfront/core/gears/Forms'` |
| `W.forms.FormDataState.Context` | `import { FormDataContext } from '@webfront/core/gears/Forms/FormDataState'` |

### UI Components (from `components` → `modules/commonui-components`)

| W reference | Direct import |
|-------------|---------------|
| `W.ErrorDisplayComponent` | `import ErrorDisplayComponent from '@webfront/core/react-components/ErrorDisplayComponent'` |
| `W.PillItem` | `import { PillItem } from '@webfront/core/react-components/PillItem'` |
| `W.PillDisplay` | `import { PillDisplay } from '@webfront/core/react-components/PillItem'` |

### Page/Routing (from `liteGlobals` → `modules/lite-globals`)

| W reference | Direct import |
|-------------|---------------|
| `W.usePage()` | `import { usePage } from '@webfront/core/react-components/page/PageState'` |

### Style/Emotion (from `style` → `modules/style`)

| W reference | Direct import |
|-------------|---------------|
| `W.emotion` | `import * as emotion from '@emotion/react'` |
| `W.emotion.Global` | `import { Global } from '@emotion/react'` |
| `W.GlobalStyles` | `import { GlobalStyles } from '@webfront/core/modules/style'` |
| `W.GlobalFonts` | `import { GlobalFonts } from '@webfront/core/modules/style'` |
| `W.useTheme()` | `import { useTheme } from '@webfront/core/gears/theme'` |
| `W.addCss()` | `import { addCss } from '@webfront/core/modules/addCss'` |

### Theme (from `theme` → `gears/theme`, registered with `setNamespace: true` as `W.theme`)

| W reference | Direct import |
|-------------|---------------|
| `W.ThemeProvider` | `import { ThemeProvider } from '@webfront/core/gears/theme'` |
| `W.defaultTheme` / `W.theme.default` | `import { defaultTheme } from '@webfront/core/gears/theme'` |
| `W.theme.th` | `import { th } from '@webfront/core/gears/theme'` |
| `W.theme.colorTheme` | `import { colorTheme } from '@webfront/core/gears/theme'` |
| `W.theme.material` | `import { material } from '@webfront/core/gears/theme'` (e.g. `material.blue['darken-2']`) |
| `W.theme.form` | `import { form } from '@webfront/core/gears/theme'` (namespace: `form.blank`, `form.crud`, `form.view`) |
| `W.theme.form.blank` | `import { blankFormTheme } from '@webfront/core/gears/theme/formThemes'` |
| `W.theme.ColorProvider` | `import { ColorProvider } from '@webfront/core/gears/theme'` |
| `W.theme.getNamedTheme` | `import { getNamedTheme } from '@webfront/core/gears/theme'` |
| `W.xstyled.ColorModeProvider` | `import { ColorModeProvider } from '@webfront/core/gears/theme'` |
| `W.tocTheme` | `import * as tocTheme from '@webfront/toc-form'` (workspace package at `packages/toc-form`) |

### MDX (from `mdx` → `mdx-merge`, registered with `setNamespace: true` as `W.mdx`)

| W reference | Direct import |
|-------------|---------------|
| `W.mdx.Merge` | `import { Merge } from '@webfront/core/mdx-merge'` |
| `W.mdxEditor.WfMDXEditor` | `import { WfMDXEditor } from '@webfront/core/mdx-editor'` |

### Helpers (from `coreHelpers` → `gears/helpers`)

| W reference | Direct import |
|-------------|---------------|
| `W.formatDate()` | `import { formatDate } from '@webfront/core/gears/helpers/dateFormats'` |
| `W.inflection` | `import { inflection } from '@webfront/core/gears/helpers/inflection'` |
| `W.setGearsFavicon()` | `import { setGearsFavicon } from '@webfront/core/gears/helpers/SetGearsFavicon'` |
| `W.consoleError()` | `import { consoleError } from '@webfront/core/gears/helpers/consoleError'` |
| `W.iconSymbolizer` | `import { iconSymbolizer } from '@webfront/core/gears/helpers/IconSymbolizer'` |

### Server Grids / Data / ViewController (from `serverGrids` → `gears/Grid`)

| W reference | Direct import |
|-------------|---------------|
| `W.ViewController` | `import { ViewController } from '@webfront/core/gears/ViewController'` |
| `W.GearsViewDisplay` | `import { GearsViewDisplay } from '@webfront/core/gears/GearsViewDisplay'` |
| `W.viewDataLoader()` | `import { viewDataLoader } from '@webfront/core/react-components/page/FormPage'` |
| `W.data` | `import * as data from '@webfront/core/gears/data/DataSource'` |
| `W.grids.breadcrumbForGrid` | `import { breadcrumbForGrid } from '@webfront/core/gears/Grid'` |

### Lists (from `lists` → `gears/List/List`, registered with `setNamespace: true` as `W.lists`)

| W reference | Direct import |
|-------------|---------------|
| `W.lists.GroupedList` | `import { GroupedList } from '@webfront/core/gears/List/List'` |

### Popper (from `popper` → `react-popper`, registered with `setGlobal: true, setNamespace: true`)

| W reference | Direct import |
|-------------|---------------|
| `W.popper.usePopper` | `import { usePopper } from 'react-popper'` |

### Toastify

| W reference | Direct import |
|-------------|---------------|
| `W.LazyToastContainer` | `import { LazyToastContainer } from '@webfront/core/modules/toastify-placeholder'` |

### Other Modules

| W reference | Direct import |
|-------------|---------------|
| `W.dialog()` | `import { dialog } from '@webfront/core/gears/notifications/Notification'` |
| `W.defineModel()` | `import { defineModel } from '@webfront/core/gears/GearsModel/ModelType'` |
| `W.setFaviconUrl()` | `import { setFaviconUrl } from '@webfront/core/extensions/FaviconAwesome'` |
| `W.fzf` | `import { fzf } from '@webfront/core/modules/instant-search'` |
| `W.singularize()` / `W.camelize()` | `import { inflection } from '@webfront/core/gears/helpers/inflection'` → `inflection.singularize()` / `inflection.camelize()` |

### Converted Packages (formerly runtime-only, now available as direct imports)

| W reference | Direct import | Source |
|-------------|---------------|--------|
| `W.FlexibleFormPage` | `import { FlexibleFormPage } from '@webfront/one'` | `form-renderer/FlexibleFormPage.tsx` |
| `W.ViewFormPage` | `import { ViewFormPage } from '@webfront/one'` | `form-renderer/ViewFormPage.tsx` |
| `W.prepareFormPage` | `import { prepareFormPage } from '@webfront/one'` | `form-renderer/prepareFormPage.ts` |
| `W.UserMention` | `import { UserMention } from '@webfront/one'` | `form-components/UserMention.tsx` |
| `W.useCacheChildGrid` | `import { useCacheChildGrid } from '@webfront/one'` | `form-renderer/useCacheChildGrid.ts` |

### Print Theme (from `@webfront/one/print-theme`)

| W reference | Direct import |
|-------------|---------------|
| `W.printMediaCss` | `import { printMediaCss } from '@webfront/one/print-theme'` |
| `W.printTheme()` | `import getPrintTheme from '@webfront/one/print-theme/printTheme'` (default export; rename to avoid shadowing local vars that store the result) |

### xStyled Utilities

| W reference | Direct import |
|-------------|---------------|
| `W.xstyledUtil.getThemeValue` | `import { getThemeValue } from '@webfront/core/gears/theme/xstyled-utils'` |

### Runtime-Only W Members (no static export — keep W reference)

These are resolved at runtime and have no static import path:

| W reference | Notes |
|-------------|-------|
| `W.applicationTheme` | App-specific MobX-reactive theme, set by `packages/beedee/src/Application/global.tsx` via hostname-based resolver (`getApplicationTheme()`). Needs page-to-module treatment — the Application directory is already extracted on disk with 21 files including 6 theme variants. Future: replace with config-driven import map or MobX store export. |
| `W.theme.ThemeGlobals` | Theme-specific global styles component (e.g. `MaterialStyles`) — varies by loaded theme |
| `W.CustomGridTable` | Lazily-loaded component via `registry.loadPageComponent()` |
| `W[page.form]` / `W[name]` | Dynamic component lookups by string name — inherently runtime |

For these, keep `import { W } from '@webfront/core/react-components/WebfrontRegistry'` and add a comment explaining why.

### Self-Reference Anti-Pattern

Modules sometimes call themselves through the registry (e.g., `W.beedeebags.mergeNestedModelFields` calling beedee's own export). Replace with a direct relative import: `import { mergeNestedModelFields } from './items/mergeNestedModelFields'`.

### Cross-Package Circular Dependency Gotcha

When a file inside `@webfront/core` uses `W.beedeebags.*`, you **cannot** statically import from `@webfront/beedee` — that creates a circular dependency (beedee already depends on core). This applies to any `W.namespace.*` reference where the namespace module is a separate package that depends on core.

**Heuristic**: If the module is loaded at runtime via `$.getScript('/webpack/xxx.js')` or `loader.xxx`, it's likely a separate package. Check `pnpm-workspace.yaml` to confirm. If circular, leave the `W.*` access with a comment explaining why.

**Exception**: Dynamic `import()` can break the cycle at runtime since it resolves lazily, but may confuse the bundler if the target package is separately bundled via script tag loading.

### Legacy `@gears/` Path Aliases

The old custom-modules system had `@gears/` path aliases that don't exist in the monorepo. Map them to `@webfront/core/`:

| Old Path | New Path |
|----------|----------|
| `@gears/GearsModel/ModelType` | `@webfront/core/gears/GearsModel/ModelType` |
| `@gears/GearsState/CoreRegistry` | `@webfront/core/gears/GearsState/CoreRegistry` |
| `@gears/Grid` | `@webfront/core/gears/Grid/GridState` |
| `@gears/Forms` | `@webfront/core/gears/Forms/Form/Form` |
| `@gears/lookups` | `@webfront/types` (for `ILookup` interface) |

### The `global.Gears.Auto` Pattern

`global.Gears.Auto.models`, `.views`, `.grids` is a runtime-populated data store. This pattern is used throughout the core codebase (deepdive, FilterRow, etc.) and should be kept as `global.Gears.Auto.*` -- it is NOT a module import. Other core files use the same pattern.

### The `registry.registerModule()` Pattern

Old custom-module index files use:
```typescript
registry.registerModule("moduleName", { exports... }, { setDefault: false, setGlobal: false, setNamespace: true });
```
Replace with standard ESM named exports:
```typescript
export { foo } from './foo';
export { bar } from './bar';
```

## Automated Extraction: `pageToModule()`

Before the manual conversion steps, use the built-in `pageToModule()` function for the initial extraction:

**Location:** `vendor/gears/core/src/react-components/page/page-to-module/pagetoModule.ts`

```typescript
import { pageToModule } from '@webfront/core/react-components/page/page-to-module/pagetoModule';
pageToModule(config, outputDir, options?); // config: IRawPageConfig, outputDir: string
```

**What it does (Step 0):**
1. Creates a directory named `config.identifier || config.name`
2. Extracts `javascript` → `main.tsx`, `preload` → `preload.tsx`, `template` → `template.tsx`
3. Extracts each `scripts[name]` → `${name}.tsx` (handles `isRaw` vs function-wrapped via `wrapScript()`)
4. Generates `modules.ts`, `page.meta.ts` (with `S` placeholder), composite `style.scss`
5. Generates `index.ts` barrel with semantic ordering (styles → meta → core → scripts)
6. **Import resolution** (via `resolveImports()`): scans generated code for ambient globals (`React`, `observer`, `css`, `styled`, `_`, etc.), `W.xxx` registry access, and `S.xxx` cross-script references, then prepends proper static imports

**Options** (`PageToModuleOptions`):
- `coreAlias` — override `@webfront/core` prefix in generated imports (default: `'@webfront/core'`)
- `resolveImports` — enable/disable the import resolution pass (default: `true`)

**What still needs manual review:**
- Runtime-only W members (no static export) — resolver may miss these or add incorrect imports
- Deep W.theme namespace paths (e.g., `W.theme.form.blank`) — may need manual mapping to subpath imports
- Cross-package circular dependencies — resolver can't detect these automatically
- `@gears/` legacy paths — not handled by resolver

**Key helpers:**
- `wrapScript(name, script)` — wraps code with function header based on `isRaw`/`isAsync`/`decorator`
- `extractMeta(config)` — returns all properties NOT written to own files
- `generateCompositeStyleFile(config)` — combines styleAll/Desktop/Print/Mobile into one `.scss`
- `resolveImports(code, scriptName, allScriptNames, options)` — detects globals/W/S references and returns `{ imports, code }`

## Workflow

### Step 1: Identify all globals used

```bash
# Scan for globals in the target directory
grep -rn 'W\.\|registry\.\|loader\.\|observer\|gearsState\|@gears\|global\b\|_\.\|styled\.\|React\.\|mobx\.\|usePage\|useTheme\|\$\.' <path>
```

### Step 2: Remove the `S` object

1. In `page.meta.ts`: Remove `export const S: Record<string, any> = {};`
2. Find all `S.xxx` references across all files
3. Replace each `S.xxx` with a direct import from the sibling file that exports `xxx`:
   - `S.prepare(this)` -> `import prepare from './prepare'; prepare(this)`
   - `S.PaperBagForm` -> `import PaperBagForm from './PaperBagForm'`
   - `S.beedeeComponents.BeeDeeHeader` -> `import { BeeDeeHeader } from './beedeeComponents'`

### Step 3: Convert default-export objects to named exports

Files like `beedeeComponents.tsx` that use:
```typescript
export default { Foo, Bar, baz };
```
Convert to:
```typescript
export function Foo() { ... }
export function Bar() { ... }
export const baz = ...;
```

### Step 4: Add explicit imports to every file

For each file, add the appropriate imports from the mapping table above. Common patterns:
- TSX components need: `React`, `observer`, possibly `css`, `styled`
- Prepare/preload functions need: `gearsState`, possibly `$`
- Form components need: `Form`, `Field`, `NavItem` from `@webfront/core/gears/Forms`

### Step 5: Replace W.xxx with direct imports

This is the most impactful step. Use the "W Member to Direct Import Mapping" table above.

1. Find all `W.xxx` references: `grep -rn 'W\.' <path>`
2. For each reference, look up the direct import in the mapping table
3. Add the import at the top of the file
4. Replace the `W.xxx` usage with the direct reference
5. For destructuring patterns like `const { Field } = W.Form;` — replace with `import { Field } from '@webfront/core/gears/Forms'` and remove the destructuring line
6. For JSX tags like `<W.Form.Section>` — replace with `<FormSection>` using the imported name
7. For runtime-only members (see table), keep `W.xxx` with a TODO comment
8. Remove `import { W }` only if ALL W references in the file are replaced

### Step 6: Fix the `modules.ts` import

Change `import type { IModule } from '../PageConfig'` to:
```typescript
import type { IModule } from '@webfront/core/react-components/page/PageConfig';
```

### Step 7: Update the index.ts

If `beedeeComponents` was converted from default to named exports, change:
```typescript
export { default as beedeeComponents } from './beedeeComponents';
```
to:
```typescript
export * from './beedeeComponents';
```

### Step 8: Replace `global.history` with `window.history`

In `FormUrlHistory.tsx` and similar files, `global.history.pushState()` should become `window.history.pushState()`.

## How to Trace New W Members

When you encounter a `W.xxx` reference not listed in the mapping table:

1. **Check Loader.ts** (`vendor/gears/core/src/modules/Loader.ts`) — find the getter that loads the chunk containing `xxx`
2. **Follow the import chain** — the getter's `import(...)` path points to a barrel file (e.g., `./commonui-components`, `./style`, `../gears/Forms/Core`)
3. **Check registration options**:
   - `setGlobal: true` → module exports spread directly onto W (e.g., `ErrorDisplayComponent` → `W.ErrorDisplayComponent`)
   - `setNamespace: true` → nested under `W[name]` (e.g., theme → `W.theme.default`)
4. **Search for the export**: `grep -rn 'export.*memberName' vendor/gears/core/src/`
5. If not found as a static export → it's runtime-only, keep as `W.xxx` with TODO comment

## Verification

After conversion, verify:
1. No remaining `S.` references (except in comments): `grep -rn '\bS\.' <path>`
2. No remaining `W.` references except runtime-only ones (with TODO comments): `grep -rn 'W\.' <path>`
3. No `@gears/` imports remain: `grep -rn '@gears/' <path>`
4. No `(global as any)` casts remain: `grep -rn '(global as any)' <path>`
5. All `W` imports removed from files that have no remaining `W.` references

## File-by-File Template

Typical page-import directory structure and what each file needs:

| File | Key Changes |
|------|-------------|
| `page.meta.ts` | Remove `S`, keep `pageMeta` |
| `modules.ts` | Fix `IModule` import path |
| `preload.tsx` | Remove `S` import, import `prepare` directly |
| `prepare.tsx` | Direct imports for `gearsState`, `$`, `FieldTypes`, `prepareFormPage` (from `@webfront/one`), `getPrintTheme` (from `@webfront/one/print-theme/printTheme`); keep `W` only for cross-package namespace refs like `W.beedeebags.*` (circular dep) |
| `template.tsx` | Import `React`, import the render component directly |
| `setPageHead.tsx` | Direct `setGearsFavicon` import, remove `W` entirely |
| `beedeeComponents.tsx` | Direct imports: `ErrorDisplayComponent`, `PillItem`, `Merge`, `Field`, `FormSection`, `UserMention` (from `@webfront/one`); W removed |
| `SandboxForm.tsx` | Direct imports: `Form`, `formatDate`, `dialog`, `defineModel`, `useTheme`, `usePage`; remove `W` |
| `PaperBagForm.tsx` | Direct imports: `Form`, `Field`, `NavItem`, `FormSection`, `Global` (from `@emotion/react`), `Merge`, `usePage`, `useFormData`, `useFormConfig`, `useTheme`, `inflection`, `autoFormContents`, `printMediaCss` (from `@webfront/one/print-theme`), `MergeViewer`, `UserMention` (from `@webfront/one`); W removed |
| `FormUrlHistory.tsx` | Import `mobx`; `window.history` not `global.history` |
| `InspectionRenderPage.tsx` | Direct `usePage`, `setFaviconUrl`, `FlexibleFormPage` (from `@webfront/one`); W removed |
| `OutcomeMerge.tsx` | Direct imports: `ErrorDisplayComponent`, `PillItem`, `Merge`, `Field`, `UserMention` (from `@webfront/one`); W removed |
| `index.ts` | Adjust exports for named-export conversions |

## Notes

- The `@webfront/core/*` path alias maps to `vendor/gears/core/src/*` (defined in `vendor/gears/core/tsconfig.json`)
- The workspace already globs `packages/*` in `pnpm-workspace.yaml`, so new packages are auto-discovered
- TypeScript "Cannot find module" errors in the beedee package are expected until the package has its own tsconfig with paths or the dependencies are installed -- the core tsconfig resolves these via `baseUrl: "."` + path aliases
- `W` is the Webfront runtime registry — only keep it for runtime-only members that have no static export
- `Loader.ts` is the key to tracing W members: each `@memoizedLoader` getter → chunk file → barrel exports → onto W
- `beedeebags-theme-config.ts` files contain embedded code strings — do NOT modify W references inside those strings
- Theme files often reference `W.tocTheme` (from `@webfront/toc-form` workspace package) and `W.theme.default` (from `@webfront/core/gears/theme`)
