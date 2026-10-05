--!strict
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const LogService = game:GetService("LogService")

const JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
const describe = JestGlobals.describe
const it = JestGlobals.it
const expect = JestGlobals.expect

const DataTable = require(ReplicatedStorage.DataTable)

type Item = { Id: string, Rarity: "Common" | "Rare", Value: number? }

-- Ten items: every fifth is Rare, Value cycles 1, 2, 3 for the first eight, and the last two have no Value.
-- So Value 1 is rows 1, 4, 7; Value 2 is rows 2, 5, 8; Value 3 is rows 3, 6.
const function makeTable(): DataTable.DataTable<Item>
	const rows: { Item } = {}
	for i = 1, 10 do
		rows[i] = {
			Id = `item{i}`,
			Rarity = if i % 5 == 0 then "Rare" else "Common",
			Value = if i <= 8 then (i - 1) % 3 + 1 else nil,
		}
	end
	return DataTable.new(rows, { Name = "Items" })
end

const function ids(rows: { read [number]: Item }): { string }
	const result = {}
	for _, row in rows do
		table.insert(result, row.Id)
	end
	return result
end

-- Returns the message `callback` errors with. Assert on it with `toContain`, not `toThrow`: Jest strips what it takes to
-- be a "file:line:" prefix from thrown strings, and the file and line differ between Studio and the CLI anyway.
const function errorOf(callback: () -> ()): string
	const ok, err = pcall(callback)
	return if ok then "<no error>" else tostring(err)
end

-- Runs `callback` and returns the warnings it emitted for the DataTable named `name`. Filtering by name keeps a late
-- warning from an earlier test out of the result.
const function captureWarnings(name: string, callback: () -> ()): { string }
	const prefix = `[DataTable] {name}:`
	const warnings = {}
	const connection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning and string.find(message, prefix, 1, true) then
			table.insert(warnings, message)
		end
	end)
	callback()
	-- MessageOut may be deferred.
	task.wait()
	connection:Disconnect()
	return warnings
end

describe("Get", function()
	it("returns the first match in row order", function()
		const Items = makeTable()
		expect(Items:By("Value"):Get(2)).toBe(Items.Rows[2])
		expect(Items:By("Rarity"):Get("Rare")).toBe(Items.Rows[5])
	end)

	it("returns nil when nothing matches", function()
		const Items = makeTable()
		expect(Items:By("Value"):Get(4)).toBeNil()
		expect(Items:By("Id"):Get("missing")).toBeNil()
	end)
end)

describe("GetAll", function()
	it("returns every match in row order", function()
		const Items = makeTable()
		expect(ids(Items:By("Value"):GetAll(1))).toEqual({ "item1", "item4", "item7" })
	end)

	it("returns the same frozen bucket on each call", function()
		const Items = makeTable()
		const rare = Items:By("Rarity"):GetAll("Rare")
		expect(table.isfrozen(rare)).toBe(true)
		expect(Items:By("Rarity"):GetAll("Rare")).toBe(rare)
	end)

	it("returns a frozen empty table when nothing matches", function()
		const Items = makeTable()
		const result = Items:By("Value"):GetAll(4)
		expect(#result).toBe(0)
		expect(table.isfrozen(result)).toBe(true)
	end)

	it("never returns rows without a value", function()
		const Items = makeTable()
		const ByValue = Items:By("Value")
		local total = 0
		for value = 1, 3 do
			total += #ByValue:GetAll(value)
		end
		expect(total).toBe(8)
	end)
end)

describe("Range", function()
	it("is inclusive and sorted ascending, with ties in row order", function()
		const Items = makeTable()
		expect(ids(Items:By("Value"):Range(1, 2))).toEqual({ "item1", "item4", "item7", "item2", "item5", "item8" })
	end)

	it("supports exclusive bounds", function()
		const ByValue = makeTable():By("Value")
		expect(ids(ByValue:Range(1, 3, { MinExclusive = true }))).toEqual({
			"item2",
			"item5",
			"item8",
			"item3",
			"item6",
		})
		expect(ids(ByValue:Range(1, 3, { MaxExclusive = true }))).toEqual({
			"item1",
			"item4",
			"item7",
			"item2",
			"item5",
			"item8",
		})
		expect(ids(ByValue:Range(1, 3, { MinExclusive = true, MaxExclusive = true }))).toEqual({
			"item2",
			"item5",
			"item8",
		})
	end)

	it("treats nil bounds as unbounded, skipping rows without a value", function()
		const ByValue = makeTable():By("Value")
		expect(#ByValue:Range()).toBe(8)
		expect(ids(ByValue:Range(nil, 1))).toEqual({ "item1", "item4", "item7" })
		expect(ids(ByValue:Range(3, nil))).toEqual({ "item3", "item6" })
	end)

	it("handles bounds between and outside the values", function()
		const ByValue = makeTable():By("Value")
		expect(ids(ByValue:Range(2.5, 10))).toEqual({ "item3", "item6" })
		expect(#ByValue:Range(-10, 0)).toBe(0)
		expect(#ByValue:Range(3, 1)).toBe(0)
	end)

	it("limits the result from the low end", function()
		const ByValue = makeTable():By("Value")
		expect(ids(ByValue:Range(2, nil, { Limit = 2 }))).toEqual({ "item2", "item5" })
		expect(#ByValue:Range(nil, nil, { Limit = 100 })).toBe(8)
		expect(#ByValue:Range(nil, nil, { Limit = 0 })).toBe(0)
	end)

	it("sorts descending with ties in row order", function()
		const ByValue = makeTable():By("Value")
		expect(ids(ByValue:Range(nil, nil, { Descending = true }))).toEqual({
			"item3",
			"item6",
			"item2",
			"item5",
			"item8",
			"item1",
			"item4",
			"item7",
		})
		expect(ids(ByValue:Range(1, 2, { Descending = true, MaxExclusive = true }))).toEqual({
			"item1",
			"item4",
			"item7",
		})
	end)

	it("limits a descending result from the high end, splitting ties in row order", function()
		const ByValue = makeTable():By("Value")
		expect(ids(ByValue:Range(nil, nil, { Descending = true, Limit = 1 }))).toEqual({ "item3" })
		expect(ids(ByValue:Range(nil, nil, { Descending = true, Limit = 4 }))).toEqual({
			"item3",
			"item6",
			"item2",
			"item5",
		})
		expect(ids(ByValue:Range(nil, 2, { Descending = true, Limit = 100 }))).toEqual({
			"item2",
			"item5",
			"item8",
			"item1",
			"item4",
			"item7",
		})
		expect(#ByValue:Range(5, 6, { Descending = true })).toBe(0)
		expect(table.isfrozen(ByValue:Range(nil, nil, { Descending = true }))).toBe(true)
	end)

	it("returns frozen results", function()
		const ByValue = makeTable():By("Value")
		expect(table.isfrozen(ByValue:Range(1, 2))).toBe(true)
		expect(table.isfrozen(ByValue:Range(5, 6))).toBe(true)
	end)

	it("errors with the column name when values can't be compared", function()
		const Mixed = DataTable.new({ { X = 1 }, { X = "a" } } :: { { X: any } }, { Name = "Mixed" })
		expect(errorOf(function()
			Mixed:By("X"):Range()
		end)).toContain("[DataTable] Mixed: cannot sort column 'X'")
	end)
end)

describe("lookups on a sorted-only index", function()
	it("answers Get and GetAll by binary search, without building buckets", function()
		const Items = makeTable():Index("Value", "Sorted")
		const ByValue = Items:By("Value")

		expect(ByValue:Get(2)).toBe(Items.Rows[2])
		expect(ids(ByValue:GetAll(1))).toEqual({ "item1", "item4", "item7" })
		expect(#ByValue:GetAll(4)).toBe(0)
		expect(table.isfrozen(ByValue:GetAll(1))).toBe(true)
		expect((ByValue :: any)._buckets).toBeNil()
	end)
end)

describe("NaN values", function()
	const function makeNaNTable(name: string)
		return DataTable.new(
			{ { Id = "a", Value = 1 }, { Id = "b", Value = 0 / 0 }, { Id = "c", Value = 0 / 0 } },
			{ Name = name }
		)
	end

	it("are left out of both index kinds", function()
		const ByValue = makeNaNTable("NaNsExcluded"):By("Value")
		captureWarnings("NaNsExcluded", function()
			expect(#ByValue:Range()).toBe(1)
			expect(#ByValue:GetAll(1)).toBe(1)
			expect(ByValue:Get(0 / 0)).toBeNil()
		end)
	end)

	it("warn once per index, listing the rows", function()
		const ByValue = makeNaNTable("NaNsWarned"):By("Value")
		const warnings = captureWarnings("NaNsWarned", function()
			ByValue:Range()
			ByValue:GetAll(1)
		end)
		-- Compare the whole list, so a failure shows every warning that was captured.
		expect(warnings).toEqual({
			"[DataTable] NaNsWarned: column 'Value' has NaN values, which are not indexed (rows 2, 3)",
		})
	end)
end)
