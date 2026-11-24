ns.IS_FOREVER = false
addon("Data/TaxiPaths.lua"); addon("Data/Teleports.lua"); addon("Data/Writs.lua"); addon("Data/WaylaidCrates.lua")
eq(ns.TaxiPaths, nil, "no flight data on retail"); eq(ns.Transports, nil)
eq(ns.Teleports, nil, "no teleport data on retail")
eq(ns.Data and ns.Data.Writs, nil, "no writ data on retail"); eq(ns.Data and ns.Data.WaylaidCrates, nil)
