--!strict
--!native
--!optimize 2

--// Imports
local ColumnIndex = require("@self/ColumnIndex")
local Types = require("@self/Types")

--// Types
export type DataTable<Row> = Types.DataTable<Row>
export type ColumnIndex<V, Row> = Types.ColumnIndex<V, Row>
export type IndexKind = Types.IndexKind
export type DataTableOptions = Types.DataTableOptions
export type RangeOptions = Types.RangeOptions
export type Required<T> = Types.Required<T>

type Self = {
	Name: string,
	Rows: { any },
	--- column -> ColumnIndex, created on first `By`/`Index`/`Unique` for that column.
	_columns: { [string]: ColumnIndex.ColumnIndex },
}

--// DataTable Class
--- Data Tables are immutable lists of rows with lazily indexed, type-safe column queries.
local DataTable = {}
DataTable.__index = DataTable

--- Freezes `value` and every table reachable from it (keys included). Ignores `__iter`.
local function deepFreeze(value: any, visited: { [any]: true })
	if type(value) ~= "table" or visited[value] then
		return
	end
	visited[value] = true

	for key, child in next, value do
		deepFreeze(key, visited)
		deepFreeze(child, visited)
	end

	if not table.isfrozen(value) then
		table.freeze(value)
	end
end

local function freeze(value: any)
	if not table.isfrozen(value) then
		table.freeze(value)
	end
end

--- Creates a DataTable over `rows`. Freezes `rows` in place, and every nested table unless `DeepFreeze` is false.
function DataTable.new<Row>(rows: { Row }, options: DataTableOptions?): DataTable<Row>
	local name = options and options.Name or "DataTable"

	if options and options.DeepFreeze == false then
		for _, row in rows do
			freeze(row)
		end
		freeze(rows)
	else
		deepFreeze(rows, {})
	end

	local self: Self = {
		Name = name,
		Rows = rows,
		_columns = {},
	}
	return table.freeze(setmetatable(self, DataTable)) :: any
end

function DataTable.Unique(self: Self, column: string): Self
	ColumnIndex._checkUnique(DataTable._getColumn(self, column))
	return self
end

function DataTable.Index(self: Self, column: string, kind: IndexKind): Self
	local index = DataTable._getColumn(self, column)
	if kind == "Hash" then
		ColumnIndex._getBuckets(index)
	elseif kind == "Sorted" then
		ColumnIndex._getSorted(index)
	else
		error(`[DataTable] {self.Name}: unknown index kind '{kind}'`, 2)
	end
	return self
end

function DataTable.By(self: Self, column: string): ColumnIndex.ColumnIndex
	return DataTable._getColumn(self, column)
end

function DataTable.Computed(self: Self, key: (row: any) -> any): ColumnIndex.ColumnIndex
	return ColumnIndex.new(self.Rows, nil, key, self.Name)
end

function DataTable.Filter(self: Self, predicate: (row: any) -> boolean): { any }
	local results: { any } = {}
	for _, row in self.Rows do
		if predicate(row) then
			table.insert(results, row)
		end
	end
	return table.freeze(results)
end

--- Returns the cached ColumnIndex for `column`, creating it if missing.
function DataTable._getColumn(self: Self, column: string): ColumnIndex.ColumnIndex
	local index = self._columns[column]
	if index == nil then
		index = ColumnIndex.fromColumn(self.Rows, column, self.Name)
		self._columns[column] = index
	end
	return index
end

return DataTable
