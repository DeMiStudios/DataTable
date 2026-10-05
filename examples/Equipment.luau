--!strict
-- An equipment catalog: static item definitions loaded once, then queried by id, slot, level, and computed keys.

--// Services
const ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Imports
const DataTable = require(ReplicatedStorage.Packages.DataTable)

--// Types
export type Slot = "Head" | "Chest" | "Weapon"
export type Rarity = "Common" | "Rare" | "Epic"

export type Equipment = {
	Id: string,
	Name: string,
	Slot: Slot,
	Rarity: Rarity,
	RequiredLevel: number,
	Attack: number?,
	Defense: number?,
	--- Only some items belong to a set; the rest are left out of `By("Set")`.
	Set: string?,
}

--// Data
const rows: { Equipment } = {
	{ Id = "leather_cap", Name = "Leather Cap", Slot = "Head", Rarity = "Common", RequiredLevel = 1, Defense = 1 },
	{ Id = "iron_helm", Name = "Iron Helm", Slot = "Head", Rarity = "Common", RequiredLevel = 5, Defense = 3 },
	{
		Id = "knight_helm",
		Name = "Knight's Helm",
		Slot = "Head",
		Rarity = "Rare",
		RequiredLevel = 10,
		Defense = 6,
		Set = "Knight",
	},
	{ Id = "cloth_tunic", Name = "Cloth Tunic", Slot = "Chest", Rarity = "Common", RequiredLevel = 1, Defense = 2 },
	{
		Id = "knight_plate",
		Name = "Knight's Plate",
		Slot = "Chest",
		Rarity = "Rare",
		RequiredLevel = 10,
		Defense = 10,
		Set = "Knight",
	},
	{
		Id = "dragon_mail",
		Name = "Dragon Mail",
		Slot = "Chest",
		Rarity = "Epic",
		RequiredLevel = 25,
		Defense = 18,
		Attack = 4,
	},
	{ Id = "wooden_sword", Name = "Wooden Sword", Slot = "Weapon", Rarity = "Common", RequiredLevel = 1, Attack = 2 },
	{ Id = "iron_sword", Name = "Iron Sword", Slot = "Weapon", Rarity = "Common", RequiredLevel = 5, Attack = 5 },
	{
		Id = "knight_sword",
		Name = "Knight's Sword",
		Slot = "Weapon",
		Rarity = "Rare",
		RequiredLevel = 10,
		Attack = 9,
		Set = "Knight",
	},
	{ Id = "dragon_blade", Name = "Dragon Blade", Slot = "Weapon", Rarity = "Epic", RequiredLevel = 25, Attack = 20 },
}

--// Table
-- Freezes `rows` (and everything in them), so definitions can be shared freely without defensive copies.
const Items = DataTable
	.new(rows, { Name = "Equipment" })
	-- Save data stores item ids, so a duplicate id is a data bug: fail at load, not when a player hits it.
	:Unique(
		"Id"
	)
	-- Queried on every level up; build it at load rather than on the first query.
	:Index("RequiredLevel", "Sorted")

-- Computed keys are cached on the returned object, so create them once here, not inside the functions below.
const BySlotAndRarity = Items:Computed(function(item)
	return `{item.Slot}/{item.Rarity}`
end)

const ByPower = Items:Computed(function(item)
	return (item.Attack or 0) + (item.Defense or 0)
end)

--// Queries
const Equipment = {}

--- Looks up a definition from save data. O(1).
function Equipment.Get(id: string): Equipment?
	return Items:By("Id"):Get(id)
end

--- Every item for an inventory tab, in definition order. Returns the cached (frozen) bucket; nothing is copied.
function Equipment.GetForSlot(slot: Slot): { read [number]: Equipment }
	return Items:By("Slot"):GetAll(slot)
end

--- The items unlocked by going from `oldLevel` to `newLevel`, for a "new items" popup.
function Equipment.GetUnlocked(oldLevel: number, newLevel: number): { read [number]: Equipment }
	return Items:By("RequiredLevel"):Range(oldLevel, newLevel, { MinExclusive = true })
end

--- Every piece of a set. Items without a `Set` are never returned.
function Equipment.GetSet(set: string): { read [number]: Equipment }
	return Items:By("Set"):GetAll(set)
end

--- A shop's stock for one slot and rarity: a composite key, so one lookup instead of two.
function Equipment.GetStock(slot: Slot, rarity: Rarity): { read [number]: Equipment }
	return BySlotAndRarity:GetAll(`{slot}/{rarity}`)
end

--- The `count` smallest upgrades: items with more attack + defense than `currentPower`, weakest first.
function Equipment.GetUpgrades(currentPower: number, count: number): { read [number]: Equipment }
	return ByPower:Range(currentPower, nil, { MinExclusive = true, Limit = count })
end

--- The `count` strongest items, strongest first, for a leaderboard of best gear.
function Equipment.GetStrongest(count: number): { read [number]: Equipment }
	return ByPower:Range(nil, nil, { Descending = true, Limit = count })
end

--- Items a player can use but doesn't own yet. Depends on per-player state, so this is a one-off scan, not an index.
function Equipment.GetMissing(level: number, owned: { [string]: true }): { read [number]: Equipment }
	return Items:Filter(function(item)
		return item.RequiredLevel <= level and not owned[item.Id]
	end)
end

return table.freeze(Equipment)
