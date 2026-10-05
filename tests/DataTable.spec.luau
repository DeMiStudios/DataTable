--!strict
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
const describe = JestGlobals.describe
const it = JestGlobals.it
const expect = JestGlobals.expect

const DataTable = require(ReplicatedStorage.DataTable)

type Item = { Id: string, Rarity: "Common" | "Rare", Value: number?, Tags: { string } }

-- Ten items: every fifth is Rare, Value cycles 1, 2, 3 for the first eight, and the last two have no Value.
local function makeRows(): { Item }
	const rows: { Item } = {}
	for i = 1, 10 do
		rows[i] = {
			Id = `item{i}`,
			Rarity = if i % 5 == 0 then "Rare" else "Common",
			Value = if i <= 8 then (i - 1) % 3 + 1 else nil,
			Tags = { "tag" },
		}
	end
	return rows
end

local function ids(rows: { read [number]: Item }): { string }
	const result = {}
	for _, row in rows do
		table.insert(result, row.Id)
	end
	return result
end

-- Returns the message `callback` errors with. Assert on it with `toContain`, not `toThrow`: Jest strips what it takes to
-- be a "file:line:" prefix from thrown strings, and the file and line differ between Studio and the CLI anyway.
local function errorOf(callback: () -> ()): string
	const ok, err = pcall(callback)
	return if ok then "<no error>" else tostring(err)
end

describe("new", function()
	it("keeps the given rows table", function()
		const rows = makeRows()
		const Items = DataTable.new(rows)
		expect(Items.Rows).toBe(rows)
	end)

	it("defaults the name", function()
		expect(DataTable.new(makeRows()).Name).toBe("DataTable")
		expect(DataTable.new(makeRows(), { Name = "Items" }).Name).toBe("Items")
	end)

	it("deep freezes the rows by default", function()
		const rows = makeRows()
		DataTable.new(rows)
		expect(table.isfrozen(rows)).toBe(true)
		expect(table.isfrozen(rows[1])).toBe(true)
		expect(table.isfrozen(rows[1].Tags)).toBe(true)
		expect(function()
			(rows[1] :: any).Value = 100
		end).toThrow()
	end)

	it("freezes only the rows when DeepFreeze is false", function()
		const rows = makeRows()
		DataTable.new(rows, { DeepFreeze = false })
		expect(table.isfrozen(rows)).toBe(true)
		expect(table.isfrozen(rows[1])).toBe(true)
		expect(table.isfrozen(rows[1].Tags)).toBe(false)
	end)

	it("handles cyclic and already frozen tables", function()
		const cycle: { [string]: any } = {}
		cycle.Self = cycle
		const shared = table.freeze({ cycle })
		const rows = { { Id = "a", Data = shared }, { Id = "b", Data = shared } }

		DataTable.new(rows)
		expect(table.isfrozen(cycle)).toBe(true)
	end)

	it("is itself frozen", function()
		const Items = DataTable.new(makeRows())
		expect(table.isfrozen(Items :: any)).toBe(true)
		expect(function()
			(Items :: any).Name = "Other"
		end).toThrow()
	end)
end)

describe("Unique", function()
	it("returns the table, and Get finds each row", function()
		const rows = makeRows()
		const Items = DataTable.new(rows)
		expect(Items:Unique("Id")).toBe(Items)
		expect(Items:By("Id"):Get("item7")).toBe(rows[7])
	end)

	it("errors on the first duplicate in row order", function()
		const Dupes = DataTable.new({ { Id = 1 }, { Id = 2 }, { Id = 1 }, { Id = 2 } }, { Name = "Dupes" })
		expect(errorOf(function()
			Dupes:Unique("Id")
		end)).toContain("[DataTable] Dupes: column 'Id' must be unique, but 1 appears in rows 1 and 3")
	end)

	it("ignores rows without a value", function()
		const Sparse = DataTable.new(
			{ { Id = "a", Code = 1 }, { Id = "b" }, { Id = "c" }, { Id = "d", Code = 2 } } :: { { Id: string, Code: number? } }
		)
		expect(function()
			Sparse:Unique("Code")
		end).never.toThrow()
	end)
end)

describe("Index", function()
	it("returns the table, and queries match lazily built indexes", function()
		const Eager = DataTable.new(makeRows()):Index("Rarity", "Hash"):Index("Value", "Sorted")
		const Lazy = DataTable.new(makeRows())

		expect(ids(Eager:By("Rarity"):GetAll("Rare"))).toEqual(ids(Lazy:By("Rarity"):GetAll("Rare")))
		expect(ids(Eager:By("Value"):Range(1, 2))).toEqual(ids(Lazy:By("Value"):Range(1, 2)))
	end)

	it("errors on an unknown kind", function()
		const Items = DataTable.new(makeRows())
		expect(errorOf(function()
			Items:Index("Value", "BTree" :: any)
		end)).toContain("unknown index kind 'BTree'")
	end)

	it("surfaces sort errors at load time", function()
		const Mixed = DataTable.new({ { X = 1 }, { X = "a" } } :: { { X: any } }, { Name = "Mixed" })
		expect(errorOf(function()
			Mixed:Index("X", "Sorted")
		end)).toContain("[DataTable] Mixed: cannot sort column 'X'")
	end)
end)

describe("By", function()
	it("returns the same index for the same column", function()
		const Items = DataTable.new(makeRows())
		expect(Items:By("Rarity")).toBe(Items:By("Rarity"))
		expect(Items:By("Rarity")).never.toBe(Items:By("Id"))
		expect(Items:By("Rarity").Column).toBe("Rarity")
	end)
end)

describe("Computed", function()
	it("indexes a predicate under true and false", function()
		const Items = DataTable.new(makeRows())
		const IsRare = Items:Computed(function(item)
			return item.Rarity == "Rare"
		end)
		expect(ids(IsRare:GetAll(true))).toEqual({ "item5", "item10" })
		expect(#IsRare:GetAll(false)).toBe(8)
		expect(IsRare.Column).toBeNil()
	end)

	it("supports composite keys", function()
		const Items = DataTable.new(makeRows())
		const ByRarityAndValue = Items:Computed(function(item)
			return if item.Value then `{item.Rarity}/{item.Value}` else nil
		end)
		expect(ids(ByRarityAndValue:GetAll("Rare/2"))).toEqual({ "item5" })
		expect(#ByRarityAndValue:GetAll("Rare/3")).toBe(0)
	end)

	it("supports ranges over derived values", function()
		const Items = DataTable.new(makeRows())
		const Doubled = Items:Computed(function(item)
			return if item.Value then item.Value * 2 else nil
		end)
		expect(ids(Doubled:Range(5, nil))).toEqual({ "item3", "item6" })
	end)

	it("returns a new index on each call", function()
		const Items = DataTable.new(makeRows())
		const key = function(item: Item)
			return item.Rarity
		end
		expect(Items:Computed(key)).never.toBe(Items:Computed(key))
	end)

	it("calls the key function once per row, however many queries run", function()
		const Items = DataTable.new(makeRows())
		local calls = 0
		const ByValue = Items:Computed(function(item)
			calls += 1
			return item.Value
		end)

		ByValue:Range(1, 2)
		ByValue:Get(3)
		ByValue:GetAll(1)
		ByValue:Range(2, nil, { Limit = 1 })
		expect(calls).toBe(10)
	end)

	it("names the computed key in errors", function()
		const Mixed = DataTable.new({ { X = 1 }, { X = "a" } } :: { { X: any } }, { Name = "Mixed" })
		const ByX = Mixed:Computed(function(row: any)
			return row.X
		end)
		expect(errorOf(function()
			ByX:Range()
		end)).toContain("[DataTable] Mixed: cannot sort computed key")
	end)
end)

describe("Filter", function()
	it("returns matching rows in row order, frozen", function()
		const Items = DataTable.new(makeRows())
		const result = Items:Filter(function(item)
			return item.Value == 3
		end)
		expect(ids(result)).toEqual({ "item3", "item6" })
		expect(table.isfrozen(result)).toBe(true)
	end)

	it("returns a frozen empty table when nothing matches", function()
		const Items = DataTable.new(makeRows())
		const result = Items:Filter(function()
			return false
		end)
		expect(#result).toBe(0)
		expect(table.isfrozen(result)).toBe(true)
	end)
end)
