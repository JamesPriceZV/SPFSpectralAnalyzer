# Search Syntax

All search boxes in the app support boolean search with field-specific filters. Plain text queries work the same as before — type any word and it matches across all fields.

## Boolean Operators

| Operator | Description | Example |
|----------|-------------|---------|
| *(space)* | Implicit AND between terms | `cerave 30` matches both |
| `AND` | Explicit AND | `role:reference AND spf:>30` |
| `OR` | Match either term | `tag:Post-Irr OR tag:Blank` |
| `NOT` | Exclude matches | `NOT role:reference` |
| `-` | Shorthand for NOT | `-tag:Control` |
| `"..."` | Exact phrase match | `"commercial formula"` |
| `( )` | Group expressions | `(tag:Post-Irr OR tag:Blank) name:cerva` |

Operator precedence: NOT > AND > OR. Use parentheses to override.

## Dataset Field Filters

These prefixes work in the **Data Management** search boxes (stored and archived datasets).

| Prefix | Searches | Value Type |
|--------|----------|------------|
| `name:` | File name | Substring match |
| `file:` | File name (alias for `name:`) | Substring match |
| `role:` | Dataset role | `reference`, `prototype`, or `none` |
| `spf:` | Known in-vivo SPF value | Numeric comparison |
| `date:` | Import date | Date comparison (YYYY-MM-DD) |
| `spectra:` | Number of spectra in the dataset | Numeric comparison |
| `memo:` | SPC header memo field | Substring match |
| `instrument:` | Source instrument description | Substring match |
| `hash:` | File content hash | Prefix match |
| `path:` | Original source file path | Substring match |

### Numeric Comparisons

Use comparison operators with numeric fields:

- `spf:>30` — SPF greater than 30
- `spf:>=15` — SPF greater than or equal to 15
- `spf:=50` — SPF exactly 50
- `spectra:>5` — Datasets with more than 5 spectra

### Date Comparisons

Use ISO 8601 format (YYYY-MM-DD):

- `date:>2025-01-01` — Imported after January 1, 2025
- `date:<2025-06-15` — Imported before June 15, 2025

## Spectrum Field Filters

These prefixes work in the **Analysis** sidebar filter.

| Prefix | Searches | Value Type |
|--------|----------|------------|
| `name:` | Spectrum name | Substring match |
| `tag:` | Auto-generated tag or HDRS tag | Substring match |
| `plate:` | HDRS plate type | `moulded` or `sandblasted` |
| `irr:` | HDRS irradiation state | `pre` or `post` (prefix match) |
| `sample:` | HDRS sample name | Substring match |

Auto-generated tags include: Post-Irr, Blank, Control, Commercial, In House, Project, Base, Neutrogena, Cetaphil, CeraVe, CVS, Moulded, Sandblasted.

## Examples

### Dataset Search

| Query | Finds |
|-------|-------|
| `cerave` | Datasets with "cerave" anywhere in name, metadata, or hash |
| `role:reference` | All reference datasets |
| `role:reference spf:>30` | References with SPF above 30 |
| `"commercial formula"` | Exact phrase in any field |
| `-role:reference` | Everything except references |
| `date:>2025-01-01 spectra:>5` | Recent datasets with many spectra |
| `instrument:solidspec` | Datasets from SolidSpec instruments |

### Spectrum Sidebar Filter

| Query | Finds |
|-------|-------|
| `cerva` | Spectra with "cerva" in name or tags |
| `tag:Post-Irr` | Post-irradiation spectra |
| `tag:Post-Irr OR tag:Blank` | Post-irradiation or blank spectra |
| `name:cerva NOT tag:Control` | CeraVe spectra, excluding controls |
| `plate:moulded irr:post` | HDRS: moulded plates, post-irradiation |
| `sample:"CeraVe SPF 30"` | Exact HDRS sample name match |
