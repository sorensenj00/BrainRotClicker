local FormatUtils = {}

local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}

function FormatUtils.formatNumber(amount: number): string
	if amount < 1000 then
		return tostring(math.floor(amount))
	end
	
	local magnitude = math.floor(math.log(amount, 1000))
	if magnitude > #suffixes then
		magnitude = #suffixes
	end
	
	local value = amount / (1000 ^ magnitude)
	
	if magnitude == 1 then
		return string.format("%.1f%s", value, suffixes[magnitude])
	elseif magnitude >= 2 then
		return string.format("%.2f%s", value, suffixes[magnitude])
	else
		return string.format("%.0f%s", value, suffixes[magnitude])
	end
end

function FormatUtils.formatMoney(amount: number): string
	return "$" .. FormatUtils.formatNumber(amount)
end

FormatUtils.formatPrice = FormatUtils.formatNumber

return FormatUtils
