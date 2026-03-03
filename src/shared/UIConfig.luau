local UIConfig = {}

UIConfig.COLORS = {
	Background = Color3.fromRGB(30, 25, 40),
	Header = Color3.fromRGB(20, 15, 25),
	Accent = Color3.fromRGB(150, 100, 255),
	AccentDark = Color3.fromRGB(100, 60, 200),
	Text = Color3.fromRGB(240, 240, 240),
	TextDark = Color3.fromRGB(180, 180, 200),
	Success = Color3.fromRGB(100, 255, 100),
	Error = Color3.fromRGB(255, 100, 100),
}

UIConfig.TWEEN_INFO = {
	Open = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Close = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Hover = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
}

-- Legacy constants used by various Shop UI scripts
UIConfig.PANEL_COLOR = Color3.fromRGB(35, 30, 45)
UIConfig.BACKGROUND_COLOR = Color3.fromRGB(20, 15, 25)
UIConfig.STROKE_COLOR = Color3.fromRGB(80, 70, 100)
UIConfig.SOFT_STROKE_COLOR = Color3.fromRGB(60, 50, 70)
UIConfig.TITLE_CHIP_COLOR = Color3.fromRGB(50, 40, 65)
UIConfig.TITLE_CHIP_STROKE = Color3.fromRGB(100, 80, 130)
UIConfig.TEXT_COLOR = Color3.fromRGB(255, 255, 255)
UIConfig.SECONDARY_TEXT_COLOR = Color3.fromRGB(200, 200, 200)
UIConfig.RED_COLOR = Color3.fromRGB(210, 55, 65)
UIConfig.GREEN_COLOR = Color3.fromRGB(100, 200, 100)
UIConfig.INFO_BLUE_COLOR = Color3.fromRGB(60, 120, 200)
UIConfig.ACCENT_COLOR = Color3.fromRGB(150, 100, 255)

UIConfig.CARD_COLOR = Color3.fromRGB(45, 40, 55)
UIConfig.CARD_INNER_COLOR = Color3.fromRGB(35, 30, 45)
UIConfig.CARD_DISABLED_COLOR = Color3.fromRGB(30, 25, 35)
UIConfig.CARD_HOVER_COLOR = Color3.fromRGB(55, 50, 65)
UIConfig.CARD_MAXED_COLOR = Color3.fromRGB(60, 50, 80)
UIConfig.CARD_WIDTH = 140
UIConfig.CARD_HEIGHT = 200
UIConfig.CARD_CORNER_RADIUS = 8
UIConfig.GRID_PADDING = 12

UIConfig.BUTTON_COLOR = Color3.fromRGB(150, 100, 255)
UIConfig.BUTTON_DISABLED_COLOR = Color3.fromRGB(60, 50, 70)

UIConfig.TWEEN_TIME = 0.15
UIConfig.SHOP_WIDTH_SCALE = 0.6
UIConfig.SHOP_CLOSED_POSITION = UDim2.new(2, 0, 0, 10)
UIConfig.SHOP_OPEN_POSITION = UDim2.new(1, -10, 0, 10)
UIConfig.CORNER_RADIUS = 12
UIConfig.SHOP_MAX_WIDTH = 900
UIConfig.SHOP_PADDING = 16
UIConfig.VIEWPORT_BG = Color3.fromRGB(25, 20, 30)

UIConfig.LOCKED_COLOR = Color3.fromRGB(15, 10, 15)
UIConfig.LOCKED_TEXT_COLOR = Color3.fromRGB(100, 100, 100)
UIConfig.LOCKED_OVERLAY_COLOR = Color3.fromRGB(0, 0, 0)
UIConfig.PRICE_COLOR = Color3.fromRGB(100, 255, 100)
UIConfig.GOLD_COLOR = Color3.fromRGB(255, 215, 0)
UIConfig.ITEM_COST_COLOR = Color3.fromRGB(180, 180, 180)
UIConfig.ITEM_NEED_COLOR = Color3.fromRGB(255, 100, 100)
UIConfig.ITEM_HAVE_COLOR = Color3.fromRGB(100, 255, 100)

UIConfig.CARD_COLORStrokeSoft = Color3.fromRGB(60, 50, 70)

-- Defensive fallbacks so older/newer UI scripts can coexist safely.
local FALLBACKS = {
	PANEL_COLOR = Color3.fromRGB(35, 30, 45),
	BACKGROUND_COLOR = Color3.fromRGB(20, 15, 25),
	STROKE_COLOR = Color3.fromRGB(80, 70, 100),
	SOFT_STROKE_COLOR = Color3.fromRGB(60, 50, 70),
	TITLE_CHIP_COLOR = Color3.fromRGB(50, 40, 65),
	TITLE_CHIP_STROKE = Color3.fromRGB(100, 80, 130),
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	SECONDARY_TEXT_COLOR = Color3.fromRGB(200, 200, 200),
	RED_COLOR = Color3.fromRGB(210, 55, 65),
	GREEN_COLOR = Color3.fromRGB(100, 200, 100),
	INFO_BLUE_COLOR = Color3.fromRGB(60, 120, 200),
	ACCENT_COLOR = Color3.fromRGB(150, 100, 255),
	CARD_COLOR = Color3.fromRGB(45, 40, 55),
	CARD_INNER_COLOR = Color3.fromRGB(35, 30, 45),
	CARD_DISABLED_COLOR = Color3.fromRGB(30, 25, 35),
	CARD_HOVER_COLOR = Color3.fromRGB(55, 50, 65),
	CARD_MAXED_COLOR = Color3.fromRGB(60, 50, 80),
	CARD_WIDTH = 140,
	CARD_HEIGHT = 200,
	CARD_CORNER_RADIUS = 8,
	GRID_PADDING = 12,
	BUTTON_COLOR = Color3.fromRGB(150, 100, 255),
	BUTTON_DISABLED_COLOR = Color3.fromRGB(60, 50, 70),
	TWEEN_TIME = 0.15,
	SHOP_WIDTH_SCALE = 0.6,
	SHOP_CLOSED_POSITION = UDim2.new(2, 0, 0, 10),
	SHOP_OPEN_POSITION = UDim2.new(1, -10, 0, 10),
	CORNER_RADIUS = 12,
	SHOP_MAX_WIDTH = 900,
	SHOP_PADDING = 16,
	VIEWPORT_BG = Color3.fromRGB(25, 20, 30),
	LOCKED_COLOR = Color3.fromRGB(15, 10, 15),
	LOCKED_TEXT_COLOR = Color3.fromRGB(100, 100, 100),
	LOCKED_OVERLAY_COLOR = Color3.fromRGB(0, 0, 0),
	PRICE_COLOR = Color3.fromRGB(100, 255, 100),
	GOLD_COLOR = Color3.fromRGB(255, 215, 0),
	ITEM_COST_COLOR = Color3.fromRGB(180, 180, 180),
	ITEM_NEED_COLOR = Color3.fromRGB(255, 100, 100),
	ITEM_HAVE_COLOR = Color3.fromRGB(100, 255, 100),
	CARD_COLORStrokeSoft = Color3.fromRGB(60, 50, 70),
}

for key, fallbackValue in pairs(FALLBACKS) do
	if UIConfig[key] == nil then
		UIConfig[key] = fallbackValue
	end
end

return UIConfig
