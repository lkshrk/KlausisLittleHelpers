ns.UI = {}
addon("Core/ListWindow.lua")
local L = ns.ListWindowLayout

local h, scroll = L({}, 50, 300)
eq(h, 50); eq(scroll, false, "empty list fits")
h, scroll = L({ 20, 20 }, 50, 300)
eq(h, 50 + 48); eq(scroll, false, "short list fits")
h, scroll = L({ 100, 100, 100 }, 50, 300)
eq(h, 300); eq(scroll, true, "long list scrolls")
h, scroll = L({ 100, 100, 100 }, 50, 362)
eq(h, 362); eq(scroll, false, "exact fit does not scroll")
h, scroll = L({ 100, 100, 100 }, 50, 361)
eq(h, 361); eq(scroll, true, "one pixel over scrolls")
h, scroll = L({ 100, 100, 100 }, 50, nil)
eq(h, 362); eq(scroll, false, "no max height never scrolls")
local _, ignored = L({ 100 }, 50, 0)
eq(ignored, false, "non-positive max ignored")
h, scroll = L({ 100, 100 }, 50, 60)
eq(h, 90); eq(scroll, true, "keeps a minimum viewport")

local function Region()
    local t = { shown = true, points = {} }
    function t:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function t:ClearAllPoints() self.points = {} end
    function t:SetText(s) self.value = s end
    function t:GetStringWidth() return #(self.value or "") * 5 end
    function t:GetStringHeight() return 12 end
    function t:SetWidth(w) self.width = w end
    function t:GetWidth() return self.width end
    function t:SetSize(w, ht) self.width, self.height = w, ht end
    function t:SetTexture(f) self.file = f end
    function t:SetVertexColor(r, g, b) self.color = { r, g, b } end
    function t:SetShown(v) self.shown = v and true or false end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:SetTextColor() end
    function t:SetColorTexture() end
    function t:SetWordWrap() end
    function t:SetJustifyH() end
    return t
end

local fill = ns.ListWindowFillRow
local row = { text = Region(), right = Region(), sel = Region(), icon = Region() }
fill(row, { text = "Cheapest", right = "1g", icon = { file = "x.png", r = 1, g = 0.5, b = 0 } }, 300)
eq(row.icon.file, "x.png"); eq(row.icon.shown, true)
eq(row.icon.color[1], 1); eq(row.icon.color[2], 0.5); eq(row.icon.color[3], 0)
eq(row.text.width, 300 - 18 - 12 - 3, "left text leaves room for the icon")
fill(row, { text = "Cheapest", right = "1g" }, 300)
eq(row.icon.shown, false, "no icon hides the texture")
eq(row.text.width, 300 - 18)
fill(row, { text = "Crate", right = "1g", itemID = 248699 }, 300)
eq(row.itemID, 248699, "a row keeps the item to show on hover")
fill(row, { text = "Plain", right = "1g" }, 300)
eq(row.itemID, nil, "a reused row forgets the item")

local align = ns.ListWindowAlignIcons
local function IconRow(rightText)
    local r = { text = Region(), right = Region(), sel = Region(), icon = Region() }
    fill(r, { text = "Option", right = rightText, icon = { file = "x.png", r = 1, g = 1, b = 1 } }, 300)
    return r
end
local short, long = IconRow("1g"), IconRow("113g 39s 87c 17 zones")
local plain = { text = Region(), right = Region(), sel = Region(), icon = Region() }
fill(plain, { text = "Header", right = "999g 99s 99c 99 zones and more" }, 300)
align({ short, long, plain })
local gap = short.icon.points[1][4] - long.icon.points[1][4]
eq(long.icon.points[1][4], -3, "the widest row keeps its icon right next to its text")
eq(gap, -(long.rightW - short.rightW), "a shorter row's icon moves left by the width difference, so all icons share one column")
eq(short.text.width, long.text.width, "every icon row leaves the same room for its label")
eq(#plain.icon.points, 0, "rows without an icon are ignored, even when wider")

local function ColRow(money, extra, withIcon)
    local r = { text = Region(), right = Region(), sel = Region(), icon = Region(), extra = Region() }
    fill(r, { text = "Option", right = money, extra = extra, icon = withIcon and { file = "x.png", r = 1, g = 1, b = 1 } or nil }, 300)
    return r
end
local ten, five = ColRow("117g 83s", "10 zones", true), ColRow("118g 74s", "5 zones", true)
align({ ten, five })
local function RightOffset(r) local p = r.right.points[#r.right.points]; return p[4] end
eq(RightOffset(ten), RightOffset(five), "costs share one right edge however wide the zone count is")
eq(RightOffset(ten), -(ten.extraW + 8), "the cost sits left of the widest extra plus the gap")
eq(ten.extra.value, "10 zones"); eq(five.extra.value, "5 zones")
eq(ten.icon.points[1][4] - five.icon.points[1][4], -(ten.rightW - five.rightW), "chevrons still share one column")
local noExtra = ColRow("1g", nil, false)
align({ noExtra })
eq(RightOffset(noExtra), 0, "without extras the cost stays at the right edge")

local pinRow, listA, listB = ColRow("3s 00c", "+25", true), ColRow("1g 00s", "3 zones", false), ColRow("2s", "1 zone", true)
align({ pinRow }, { listA, listB })
eq(RightOffset(pinRow), RightOffset(listA), "the pinned row shares the cost edge with the list")
eq(RightOffset(listB), RightOffset(listA))
eq(RightOffset(pinRow), -(listA.extraW + 8), "one extra column over pinned and list rows")
eq(pinRow.icon.points[1][4] - listB.icon.points[1][4], pinRow.rightW - listB.rightW, "one icon column over both blocks")

local loading = { text = Region(), right = Region(), sel = Region(), icon = Region(), extra = Region() }
local realWidth = loading.right.GetStringWidth
loading.right.GetStringWidth = function() return 0 end
loading.extra.GetStringWidth = function() return 0 end
fill(loading, { text = "Option", right = "5g 00s", extra = "2 zones" }, 300)
eq(loading.hasRight, true, "a row with a right column is flagged even when it measures 0")
loading.right.GetStringWidth, loading.extra.GetStringWidth = realWidth, realWidth
local other = ColRow("1g", "1 zone", false)
align({ loading, other })
eq(loading.moneyW, #"5g 00s" * 5, "widths re-measured at align time")
eq(loading.extraW, #"2 zones" * 5)
eq(RightOffset(other), -(loading.extraW + 8), "the late-measured extra widens the shared column")
eq(RightOffset(loading), RightOffset(other))
eq(loading.text.width, 300 - loading.rightW, "and its label leaves room for it")

local reused = ColRow("9g", "4 zones", true)
reused.box, reused.boxBorder = Region(), { SetColor = function() end }
fill(reused, { text = "Show other options", button = true }, 300)
eq(reused.moneyW, 0); eq(reused.extraW, 0); eq(reused.rightW, 0)
eq(reused.hasIcon, false); eq(reused.hasRight, false, "a button row drops the old column fields")
local textWidth = reused.text.width
align({ reused, ColRow("1g", "12 zones", true) })
eq(reused.text.width, textWidth, "alignment leaves a button row alone")

