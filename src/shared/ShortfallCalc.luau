--[[
	ShortfallCalc — Shared pure-math module for auto-buy cost calculation.
	
	Used by BOTH server (with MarketManager.GetBuyPrice) and client (with local AMM rates).
	No service/network dependencies — caller provides the price function.
	
	Slippage: Quantities beyond MAX_BUY are priced in batches, each batch
	more expensive than the last to punish lazy mass-buying and encourage
	using the HFT Terminal for big orders.
	
	Tax: 10% convenience tax is BURNED from the economy (never enters AMM pool).
]]

local ShortfallCalc = {}

-- Configurable constants (tweak here for balancing)
ShortfallCalc.CONVENIENCE_TAX = 0.10           -- 10% burned from economy
ShortfallCalc.SLIPPAGE_RATE_PER_BATCH = 1.02   -- Each batch of MAX_BUY costs 2% more

--[[
	Calculate the cost of auto-buying missing items from the AMM.
	
	@param itemCost       {[itemId]: needed}     — Items required by the unit
	@param playerItems    {[itemId]: have}        — Items the player currently owns (storage+backpack)
	@param getBuyPriceFn  (itemId) -> number      — Function returning current AMM buy price for an item
	@param maxBuyPerTx    number                  — MAX_BUY_PER_TRANSACTION slippage cap
	
	@return {
		totalRaw: number,       -- Raw AMM cost before tax
		totalTaxed: number,     -- Total cost including burned tax
		taxAmount: number,      -- The tax portion (burned)
		hasShortfall: boolean,  -- Whether any items are missing
		perItem: {[itemId]: {
			needed: number,     -- Total items required
			have: number,       -- Items player has
			missing: number,    -- Shortfall quantity
			unitPrice: number,  -- Current AMM price per item
			rawCost: number,    -- Cost for this item (with slippage)
		}}
	}
]]
function ShortfallCalc.Calculate(itemCost, playerItems, getBuyPriceFn, maxBuyPerTx)
	local result = {
		totalRaw = 0,
		totalTaxed = 0,
		taxAmount = 0,
		hasShortfall = false,
		perItem = {},
	}
	
	if not itemCost then return result end
	
	local slippageRate = ShortfallCalc.SLIPPAGE_RATE_PER_BATCH
	
	for itemId, needed in pairs(itemCost) do
		local have = (playerItems and playerItems[itemId]) or 0
		local missing = math.max(0, needed - have)
		local unitPrice = getBuyPriceFn(itemId) or 0
		local rawCost = 0
		
		if missing > 0 then
			result.hasShortfall = true
			
			if missing <= maxBuyPerTx then
				-- Small order: flat rate
				rawCost = missing * unitPrice
			else
				-- Large order: simulate batched buying with compound slippage
				local remaining = missing
				local batchIndex = 0
				
				while remaining > 0 do
					local batchSize = math.min(remaining, maxBuyPerTx)
					local batchMultiplier = slippageRate ^ batchIndex
					rawCost += batchSize * unitPrice * batchMultiplier
					remaining -= batchSize
					batchIndex += 1
				end
			end
		end
		
		result.perItem[itemId] = {
			needed = needed,
			have = have,
			missing = missing,
			unitPrice = unitPrice,
			rawCost = math.floor(rawCost),
		}
		
		result.totalRaw += math.floor(rawCost)
	end
	
	-- Apply convenience tax (burned from economy, never enters AMM)
	result.taxAmount = math.floor(result.totalRaw * ShortfallCalc.CONVENIENCE_TAX)
	result.totalTaxed = result.totalRaw + result.taxAmount
	
	return result
end

return ShortfallCalc
