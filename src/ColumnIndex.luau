--!strict
--!native
--!optimize 2

--// Imports
local Types = require("./Types")

--// Types
type RangeOptions = Types.RangeOptions

type Row = { [any]: any }

export type ColumnIndex = {
	--- The column name, or nil for a computed key.
	Column: string?,
	_tableName: string,
	_rows: { Row },
	--- Returns the key of a row. nil and NaN keys are not indexed.
	_key: (row: Row) -> any,
	--- value -> frozen rows with that value, in row order.
	_buckets: { [any]: { Row } }?,
	--- Rows with a key, sorted by (key, row position). Frozen.
	_sorted: { Row }?,
	--- `_sortedKeys[i]` is the key of `_sorted[i]`, so lookups never call `_key`.
	_sortedKeys: { any }?,
	_warnedNaN: boolean,
}

--// Constants
local EMPTY: { Row } = table.freeze({} :: { Row })

--// ColumnIndex Class
--- Holds the lazily built indexes for one key. Rows are frozen, so built indexes never go stale.
local ColumnIndex = {}
ColumnIndex.__index = ColumnIndex

function ColumnIndex.new(rows: { Row }, column: string?, key: (row: Row) -> any, tableName: string): ColumnIndex
	local self: ColumnIndex = {
		Column = column,
		_tableName = tableName,
		_rows = rows,
		_key = key,
		_buckets = nil,
		_sorted = nil,
		_sortedKeys = nil,
		_warnedNaN = false,
	}
	return setmetatable(self, ColumnIndex) :: any
end

--- Returns an index keyed by `row[column]`.
function ColumnIndex.fromColumn(rows: { Row }, column: string, tableName: string): ColumnIndex
	return ColumnIndex.new(rows, column, function(row)
		return row[column]
	end, tableName)
end

--- Describes the key for error messages.
function ColumnIndex._label(self: ColumnIndex): string
	return if self.Column then `column '{self.Column}'` else "computed key"
end

--- Warns (once per index) that rows at `positions` were left out of the index for having a NaN key.
function ColumnIndex._warnNaN(self: ColumnIndex, positions: { number })
	if self._warnedNaN then
		return
	end
	self._warnedNaN = true
	warn(
		`[DataTable] {self._tableName}: {ColumnIndex._label(self)} has NaN values, which are not indexed (rows {table.concat(
			positions,
			", "
		)})`
	)
end

--- Returns the hash buckets, building them on first call.
function ColumnIndex._getBuckets(self: ColumnIndex): { [any]: { Row } }
	local buckets = self._buckets
	if buckets then
		return buckets
	end

	local built: { [any]: { Row } } = {}
	local key = self._key
	local nanPositions: { number }? = nil

	for position, row in self._rows do
		local value = key(row)
		if value == nil then
			continue
		end
		if value ~= value then
			nanPositions = nanPositions or {}
			table.insert(nanPositions :: { number }, position)
			continue
		end

		local bucket = built[value]
		if bucket then
			table.insert(bucket, row)
		else
			built[value] = { row }
		end
	end

	for _, bucket in built do
		table.freeze(bucket)
	end

	if nanPositions then
		ColumnIndex._warnNaN(self, nanPositions)
	end

	self._buckets = table.freeze(built)
	return built
end

--- Returns the sorted rows and their keys, building them on first call.
function ColumnIndex._getSorted(self: ColumnIndex): ({ Row }, { any })
	local sorted, sortedKeys = self._sorted, self._sortedKeys
	if sorted and sortedKeys then
		return sorted, sortedKeys
	end

	local rows = self._rows
	local key = self._key
	local keys: { [number]: any } = {}
	local order: { number } = {}
	local nanPositions: { number }? = nil

	for position, row in rows do
		local value = key(row)
		if value == nil then
			continue
		end
		if value ~= value then
			nanPositions = nanPositions or {}
			table.insert(nanPositions :: { number }, position)
			continue
		end
		keys[position] = value
		table.insert(order, position)
	end

	-- Sort row positions rather than rows, so ties fall back to row order.
	local ok, err = pcall(function()
		table.sort(order, function(i, j)
			local a, b = keys[i], keys[j]
			if a == b then
				return i < j
			end
			return a < b
		end)
	end)
	if not ok then
		-- Drop the "Script:line: " location: it points into this module, not the caller's data.
		local reason = string.gsub(tostring(err), "^.-:%d+: ", "")
		error(`[DataTable] {self._tableName}: cannot sort {ColumnIndex._label(self)}: {reason}`, 0)
	end

	local builtRows: { Row } = table.create(#order) :: { Row }
	local builtKeys: { any } = table.create(#order)
	for k, position in order do
		builtRows[k] = rows[position]
		builtKeys[k] = keys[position]
	end

	if nanPositions then
		ColumnIndex._warnNaN(self, nanPositions)
	end

	self._sorted = table.freeze(builtRows)
	self._sortedKeys = table.freeze(builtKeys)
	return builtRows, builtKeys
end

--- Errors if any key appears in more than one row.
function ColumnIndex._checkUnique(self: ColumnIndex)
	for _, bucket in ColumnIndex._getBuckets(self) do
		if #bucket == 1 then
			continue
		end

		-- Report the first duplicate in row order, so the error is deterministic.
		local key = self._key
		local seen: { [any]: number } = {}
		for position, row in self._rows do
			local value = key(row)
			if value == nil or value ~= value then
				continue
			end
			local previous = seen[value]
			if previous then
				error(
					`[DataTable] {self._tableName}: {ColumnIndex._label(self)} must be unique, but {value} appears in rows {previous} and {position}`,
					0
				)
			end
			seen[value] = position
		end
	end
end

--- Returns the [first, last) positions in the sorted keys equal to `value`.
function ColumnIndex._equalRange(sortedKeys: { any }, value: any): (number, number)
	local n = #sortedKeys + 1
	local first = ColumnIndex._lowerBound(sortedKeys, value, 1, n)
	local last = ColumnIndex._upperBound(sortedKeys, value, first, n)
	return first, last
end

function ColumnIndex.Get(self: ColumnIndex, value: any): Row?
	-- Use the sorted rows if they're the only index built, rather than building buckets too.
	local sorted, sortedKeys = self._sorted, self._sortedKeys
	if self._buckets == nil and sorted and sortedKeys then
		local first, last = ColumnIndex._equalRange(sortedKeys, value)
		return if first < last then sorted[first] else nil
	end

	local bucket = ColumnIndex._getBuckets(self)[value]
	return if bucket then bucket[1] else nil
end

function ColumnIndex.GetAll(self: ColumnIndex, value: any): { Row }
	-- Use the sorted rows if they're the only index built, rather than building buckets too.
	local sorted, sortedKeys = self._sorted, self._sortedKeys
	if self._buckets == nil and sorted and sortedKeys then
		local first, last = ColumnIndex._equalRange(sortedKeys, value)
		if first >= last then
			return EMPTY
		end
		return table.freeze(table.move(sorted, first, last - 1, 1, table.create(last - first) :: { Row }))
	end

	return ColumnIndex._getBuckets(self)[value] or EMPTY
end

function ColumnIndex.Range(self: ColumnIndex, min: any, max: any, options: RangeOptions?): { Row }
	local sorted, sortedKeys = ColumnIndex._getSorted(self)
	local n = #sortedKeys + 1
	local minExclusive = options and options.MinExclusive
	local maxExclusive = options and options.MaxExclusive
	local limit = options and options.Limit

	local first = if min == nil
		then 1
		elseif minExclusive then ColumnIndex._upperBound(sortedKeys, min, 1, n)
		else ColumnIndex._lowerBound(sortedKeys, min, 1, n)

	local last = if max == nil
		then n
		elseif maxExclusive then ColumnIndex._lowerBound(sortedKeys, max, first, n)
		else ColumnIndex._upperBound(sortedKeys, max, first, n)

	local count = last - first
	if limit then
		count = math.min(count, limit)
	end
	if count <= 0 then
		return EMPTY
	end

	if not (options and options.Descending) then
		return table.freeze(table.move(sorted, first, first + count - 1, 1, table.create(count) :: { Row }))
	end

	-- Walk runs of equal keys from the top down, copying each run forward so ties stay in row order.
	local result: { Row } = table.create(count) :: { Row }
	local written = 0
	local runEnd = last - 1
	while written < count do
		local key = sortedKeys[runEnd]
		local runStart = runEnd
		while runStart > first and sortedKeys[runStart - 1] == key do
			runStart -= 1
		end
		for i = runStart, math.min(runEnd, runStart + count - written - 1) do
			written += 1
			result[written] = sorted[i]
		end
		runEnd = runStart - 1
	end

	return table.freeze(result)
end

--- Returns the first position `i` in [i, j) such that `sortedKeys[i] >= value`, or `j` if none.
function ColumnIndex._lowerBound(sortedKeys: { any }, value: any, i: number, j: number): number
	while i < j do
		local k = (i + j) // 2
		if sortedKeys[k] < value then
			i = k + 1
		else
			j = k
		end
	end
	return i
end

--- Returns the first position `i` in [i, j) such that `sortedKeys[i] > value`, or `j` if none.
function ColumnIndex._upperBound(sortedKeys: { any }, value: any, i: number, j: number): number
	while i < j do
		local k = (i + j) // 2
		if sortedKeys[k] <= value then
			i = k + 1
		else
			j = k
		end
	end
	return i
end

return ColumnIndex
