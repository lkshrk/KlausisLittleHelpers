ns.Data = {
    WaylaidCrates = {
        { itemID = 248682, name = "Apprentice Herbs", bundles = { { itemID = 2447, name = "Peacebloom", count = 20 }, { itemID = 765, name = "Silverleaf", count = 20 } } },
        { itemID = 248688, name = "Journeyman Textiles", bundles = { { itemID = 2592, name = "Wool Cloth", count = 20 } } },
    },
    UnlabeledCrate = { itemID = 248549, name = "Waylaid Crate" },
}
addon("Modules/WritCrateUse.lua")
local U = ns.WritUse

local items = {
    { bag = 0, slot = 3, itemID = 999, count = 1 },
    { bag = 1, slot = 5, itemID = 262902, count = 4 },
    { bag = 2, slot = 1, itemID = 248688, count = 1 },
    { bag = 2, slot = 2, itemID = 248549, count = 1 },
    { bag = 3, slot = 7, itemID = 262902, count = 2 },
}
local plan = U.ReceiptPlan(items)
eq(plan.receipts, 6, "receipts counted across stacks")
eq(plan.crates, 2, "labeled and unlabeled empty crates count")
eq(plan.uses, 2, "as many uses as the smaller of the two")
eq(U.ReceiptPlan({ { bag = 0, slot = 1, itemID = 262902, count = 3 } }).uses, 0, "no crates: nothing to do")
eq(U.ReceiptPlan({ { bag = 0, slot = 1, itemID = 248682, count = 1 } }).uses, 0, "no receipts: nothing to do")

local fill = U.FillPlan({
    { bag = 0, slot = 1, itemID = 248682, count = 1 },
    { bag = 0, slot = 2, itemID = 248682, count = 1 },
    { bag = 0, slot = 3, itemID = 248688, count = 1 },
    { bag = 0, slot = 4, itemID = 248549, count = 1 },
    { bag = 1, slot = 1, itemID = 2447, count = 10 },
    { bag = 1, slot = 2, itemID = 765, count = 45 },
    { bag = 1, slot = 3, itemID = 2592, count = 19 },
})
eq(fill.uses, 2, "two herb crates from one 45 Silverleaf stack; 10 Peacebloom and 19 Wool are too few; unlabeled crate skipped")

eq(U.MacroBody("receipt"), "#showtooltip item:262902\n/click KLHApplyReceiptButton")
eq(U.MacroBody("fill"), "/click KLHFillCrateButton", "fill macro keeps its fixed crate icon")

local skip = U.ReceiptPlan(items, { [248688] = true })
eq(skip.target and skip.target.itemID, 248549, "a crate kind that refused the receipt is skipped")
eq(skip.uses, 1, "and not counted")
eq(plan.target.bag, 2); eq(plan.target.slot, 1)
eq(fill.crate.bag, 0); eq(fill.crate.slot, 1); eq(fill.stack.bag, 1); eq(fill.stack.slot, 2)
local fillSkip = U.FillPlan({
    { bag = 0, slot = 1, itemID = 248682, count = 1 },
    { bag = 0, slot = 3, itemID = 248688, count = 1 },
    { bag = 1, slot = 2, itemID = 765, count = 45 },
    { bag = 1, slot = 3, itemID = 2592, count = 20 },
}, { [248682] = true })
eq(fillSkip.crate and fillSkip.crate.itemID, 248688, "a crate kind that refused filling is skipped")
