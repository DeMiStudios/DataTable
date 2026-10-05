--!strict
--!native
--!optimize 2

--- Removes `nil` from a union type: `Required<number?>` is `number`.
export type function Required(t: type): type
	if t:is("union") then
		local nonNilUnion = nil
		for _, tt in t:components() do
			if tt:is("nil") or tt:is("never") then
				continue
			end
			nonNilUnion = if nonNilUnion then types.unionof(nonNilUnion, tt) else tt
		end
		return if nonNilUnion then nonNilUnion else types.never
	end

	return t
end

--- The type of `row[column]` without nil: `Required<index<Row, Column>>`.
--- A type function rather than an alias because StyLua can't parse the `>>` that nesting would need.
export type function ColumnValue(row: type, column: type): type
	local value = row:readproperty(column)
	if value == nil then
		-- Not a column; `keyof` at the call site reports the error.
		return types.never
	end
	return Required(value :: any)
end

--- How a column's index is stored. Either is built lazily on first use; `DataTable:Index` builds it eagerly.
--- - "Hash": rows bucketed by value, in row order. Get/GetAll in O(1).
--- - "Sorted": rows sorted by value, ties in row order. Range in O(log n + k).
export type IndexKind = "Hash" | "Sorted"

export type DataTableOptions = {
	--- Used in error messages. Defaults to "DataTable".
	Name: string?,
	--- Freeze every table nested in the rows, not just the rows themselves. Defaults to true.
	DeepFreeze: boolean?,
}

export type RangeOptions = {
	--- Exclude rows whose value equals `min`.
	MinExclusive: boolean?,
	--- Exclude rows whose value equals `max`.
	MaxExclusive: boolean?,
	--- Sort from `max` down to `min`. Ties stay in row order.
	Descending: boolean?,
	--- Return at most this many rows, starting from `min` (or from `max` when `Descending`).
	Limit: number?,
}

--- Queries over one column, or one computed key, of a DataTable.
--- Rows whose key is nil or NaN are never returned.
export type ColumnIndex<V, Row> = {
	--- The column name, or nil for a computed key.
	read Column: string?,

	--- Returns the first row (in row order) whose column equals `value`.
	read Get: (self: ColumnIndex<V, Row>, value: V) -> Row?,

	--- Returns every row whose column equals `value`, in row order. The result is frozen.
	read GetAll: (self: ColumnIndex<V, Row>, value: V) -> { read [number]: Row },

	--- Returns rows whose column is between `min` and `max` (inclusive by default), sorted ascending unless
	--- `Descending`. Ties are in row order. The result is frozen.
	--- A nil bound is unbounded.
	read Range: (self: ColumnIndex<V, Row>, min: V?, max: V?, options: RangeOptions?) -> { read [number]: Row },
}

--- An immutable list of rows with lazily indexed column queries.
export type DataTable<Row> = {
	read Name: string,
	read Rows: { read [number]: Row },

	--- Requires every value in `column` to be unique; errors if not. Builds the column's hash index.
	read Unique: (self: DataTable<Row>, column: keyof<Row>) -> DataTable<Row>,

	--- Builds the column's index of the given kind now instead of on first query.
	read Index: (self: DataTable<Row>, column: keyof<Row>, kind: IndexKind) -> DataTable<Row>,

	--- Returns the query interface for `column`.
	read By: <K>(self: DataTable<Row>, column: K & keyof<Row>) -> ColumnIndex<ColumnValue<Row, K>, Row>,

	--- Returns a query interface keyed by `key(row)`, e.g. a predicate for `GetAll(true)`.
	--- Indexes are cached on the returned object, not the DataTable: call this once and keep the result.
	read Computed: <V>(self: DataTable<Row>, key: (row: Row) -> V) -> ColumnIndex<Required<V>, Row>,

	--- Returns the rows for which `predicate` returns true, in row order. Scans every row; nothing is cached.
	--- The result is frozen.
	read Filter: (self: DataTable<Row>, predicate: (row: Row) -> boolean) -> { read [number]: Row },
}

return table.freeze({})
