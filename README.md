# DataTable

Immutable, typed tables of rows for Roblox, with indexes that build themselves. Load static data such as item
definitions once, then look rows up by any column without choosing or maintaining indexes by hand.

```lua
local DataTable = require(ReplicatedStorage.Packages.DataTable)

local Items = DataTable.new(itemRows, { Name = "Items" }) -- freezes the rows
	:Unique("Id") -- errors now if two rows share an Id

Items:By("Id"):Get("iron_sword") --> Item?, O(1)
Items:By("Rarity"):GetAll("Rare") --> every Rare item, in row order
Items:By("Level"):Range(5, 10) --> items with 5 <= Level <= 10, sorted by Level

local ByPower = Items:Computed(function(item) return item.Attack + item.Defense end)
ByPower:Range(nil, nil, { Descending = true, Limit = 5 }) --> the 5 strongest items
```

Column names and values are type-checked: `Items:By("Rarity"):Get("Epic")` is a type error when `Rarity` is
`"Common" | "Rare"`, and so is a misspelled column. See [examples/Equipment.luau](examples/Equipment.luau) for a
fuller example.

## Installation

With [Wally](https://wally.run), add DataTable to your `wally.toml`:

```toml
[dependencies]
DataTable = "demistudios/datatable@0.1.0"
```

## Requirements

DataTable is written for current Luau and targets the **new type solver**:

- It uses `const` declarations, so it needs a Luau version (and tooling, if you lint or format your `Packages`
  folder) that supports them.
- Its types use type functions, `keyof`, `index` and read-only properties, which the old type solver doesn't
  understand. The old solver is not supported.

## Guarantees

1. **Immutable:** `DataTable.new` freezes the rows, each row, and (by default) every table nested in them. The
   DataTable itself and every result it returns are frozen too. Rows can't change, so an index never goes stale.
2. **Lazy, cached indexes:** the first query on a column builds the index it needs (a hash index for `Get` and
   `GetAll`, a sorted index for `Range`) and caches it. Later queries reuse it. `Index` builds one ahead of time.
3. **Deterministic order:** `GetAll` returns rows in row order, and `Get` returns the first of them. `Range` sorts by
   value, and rows with equal values stay in row order, in both directions.
4. **Typed:** `By` only accepts the row type's columns, and each query only accepts that column's value type
   (without `nil`). Results are typed as read-only arrays.

## API

### DataTable

| Member | Description |
|---|---|
| `DataTable.new(rows, options?)` | Freezes `rows` in place and wraps them. See [options](#options). |
| `table.Name` | The `Name` option, or `"DataTable"`. Used in error messages. |
| `table.Rows` | The rows, as given. |
| `table:By(column)` | Returns the query interface for `column`. The same object is returned for the same column. |
| `table:Unique(column)` | Errors if two rows have the same value in `column`. Returns the table, for chaining. |
| `table:Index(column, kind)` | Builds the `"Hash"` or `"Sorted"` index for `column` now instead of on first query. Returns the table. |
| `table:Computed(key)` | Returns a query interface keyed by `key(row)` instead of a column. See [computed keys](#computed-keys). |
| `table:Filter(predicate)` | Returns the rows for which `predicate(row)` is true, in row order. Scans every row; nothing is cached. |

### Queries

`By` and `Computed` return the same query interface:

| Method | Description | Cost |
|---|---|---|
| `index:Get(value)` | The first row, in row order, whose value equals `value`, or `nil`. | O(1) |
| `index:GetAll(value)` | Every row whose value equals `value`, in row order. Returns the index's own frozen list, without copying. | O(1) |
| `index:Range(min?, max?, options?)` | Rows with `min <= value <= max`, sorted by value. A `nil` bound is unbounded. | O(log n + k) |
| `index.Column` | The column name, or `nil` for a computed key. | |

Costs are for a built index. Building one costs O(n) for a hash index and O(n log n) for a sorted index, once per
column. If only the sorted index has been built, `Get` and `GetAll` use it instead of building a hash index too:
O(log n) and O(log n + k), with `GetAll` copying its result.

`Range` options:

| Option | Description |
|---|---|
| `MinExclusive` | Leave out rows equal to `min`. |
| `MaxExclusive` | Leave out rows equal to `max`. |
| `Descending` | Sort from `max` down to `min`. Equal values stay in row order. |
| `Limit` | Return at most this many rows, counting from `min` (or from `max` when `Descending`). |

### Options

| Option | Default | Description |
|---|---|---|
| `Name` | `"DataTable"` | Shown in error and warning messages. |
| `DeepFreeze` | `true` | Freeze every table nested in the rows. When `false`, only the rows list and each row are frozen. |

## Computed keys

`Computed` indexes a value derived from each row: a predicate, a composite key, or a calculation.

```lua
local IsUpgradeable = Items:Computed(function(item) return item.NextTier ~= nil end)
IsUpgradeable:GetAll(true)

local BySlotAndRarity = Items:Computed(function(item) return `{item.Slot}/{item.Rarity}` end)
BySlotAndRarity:GetAll("Weapon/Epic")
```

The indexes are cached on the returned object, not on the DataTable, so **call `Computed` once and keep the result**.
Calling it inside a function that runs often rebuilds the index every time. The key function is called once per row
when an index is built, and never during queries.

A predicate indexes every row, under `true` or `false`. A key function that returns `nil` leaves that row out.

## Edge cases

- **Missing values:** a row whose value is `nil` isn't in that column's index, so no query returns it. This matches
  Luau, where `nil` means the field isn't there.
- **NaN:** NaN can't be a table key and never equals itself, so rows with a NaN value are left out of the index, with
  one warning per index listing their row numbers.
- **Values that can't be compared:** `Range` on a column with mixed types, or with values `<` doesn't support, errors
  when the sorted index is built, naming the column. Use `Index(column, "Sorted")` to hit this at load time.
- **Read-only results:** results are typed `{ read Row }`, which can't be passed where `{ Row }` is
  expected. Type such parameters as `{ read Row }`.
- **`DeepFreeze = false`:** nested tables stay mutable. Hash indexes aren't affected, since table keys are compared by
  identity, but a sorted index over table values with `__lt` goes stale if those tables change.

## Errors

| Message | Cause |
|---|---|
| `<Name>: column '<column>' must be unique, but <value> appears in rows <a> and <b>` | `Unique` found a duplicate. The first duplicate in row order is reported. |
| `<Name>: cannot sort column '<column>': <reason>` | Building a sorted index failed because two values couldn't be compared. Computed keys say `computed key` instead. |
| `<Name>: unknown index kind '<kind>'` | `Index` was given something other than `"Hash"` or `"Sorted"`. |

Every message starts with `[DataTable]`.

## Development

Tools are managed by [Rokit](https://github.com/rojo-rbx/rokit). Run `rokit install`, then `wally install`.

Formatting is checked with StyLua (`stylua --check src tests examples`) and types with luau-lsp. The
[CI workflow](.github/workflows/ci.yml) runs both. The test place maps `src` to `ReplicatedStorage.Packages.DataTable`
as well, so the examples resolve their `require` and are type-checked too.

### Running the tests in Studio

1. Build the test place with `rojo build test.project.json -o tests.rbxl`, or serve it with
   `rojo serve test.project.json`, and open it in Studio.
2. Run this in the command bar:

   ```lua
   loadstring(game.ReplicatedStorage.Tests.Bootstrap.Source)()
   ```

The suite uses [Jest Roblox](https://github.com/Roblox/jest-roblox). It runs from the command bar because Jest needs
plugin-level access to read module sources; this avoids having to enable `FFlagEnableLoadModule`.

## License

MIT. See [LICENSE](LICENSE).
