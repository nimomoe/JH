-- @Author: ChenWei-31027
-- @Date:   2015-06-19 16:31:21
-- @Last Modified by:   Webster
-- @Last Modified time: 2015-07-20 11:36:38

local _L = JH.LoadLangPack

local pairs, ipairs = pairs, ipairs
local GetClientTeam, GetClientPlayer = GetClientTeam, GetClientPlayer
local tinsert = table.insert

local RT_INIFILE = JH.GetAddonInfo().szRootPath .. "RaidTools/ui/RaidTools1.ini"
local RT_EQUIP_TOTAL = {
	"MELEE_WEAPON", -- 轻剑 藏剑取 BIG_SWORD 重剑
	"RANGE_WEAPON", -- 远程武器
	"CHEST",        -- 衣服
	"HELM",         -- 帽子
	"AMULET",       -- 项链
	"LEFT_RING",    -- 戒指
	"RIGHT_RING",   -- 戒指
	"WAIST",        -- 腰带
	"PENDANT",      -- 腰坠
	"PANTS",        -- 裤子
	"BOOTS",        -- 鞋子
	"BANGLE",       -- 护腕
}

local RT_SKILL_TYPE = {
	[0]  = "PHYSICS_DAMAGE",
	[1]  = "SOLAR_MAGIC_DAMAGE",
	[2]  = "NEUTRAL_MAGIC_DAMAGE",
	[3]  = "LUNAR_MAGIC_DAMAGE",
	[4]  = "POISON_DAMAGE",
	[5]  = "REFLECTIED_DAMAGE",
	[6]  = "THERAPY",
	[7]  = "STEAL_LIFE",
	[8]  = "ABSORB_THERAPY",
	[9]  = "ABSORB_DAMAGE",
	[10] = "SHIELD_DAMAGE",
	[11] = "PARRY_DAMAGE",
	[12] = "INSIGHT_DAMAGE",
	[13] = "EFFECTIVE_DAMAGE",
	[14] = "EFFECTIVE_THERAPY",
	[15] = "TRANSFER_LIFE",
	[16] = "TRANSFER_MANA",
}
-- 副本评分 晚点在做吧
-- local RT_DUNGEON_TOTAL = {}
local RT_SCORE = {
	Equip   = _L["Equip Score"],
	Buff    = _L["Buff Score"],
	Food    = _L["Food Score"],
	Enchant = _L["Enchant Score"],
	Special = _L["Special Equip Score"],
}

local RT_EQUIP_SPECIAL = {
	MELEE_WEAPON = true,
	BIG_SWORD    = true,
	AMULET       = true,
	PENDANT      = true
}

local RT_FOOD_TYPE = {
	[24] = true,
	[17] = true,
	[18] = true,
	[19] = true,
	[20] = true
}
-- 需要监控的BUFF
local RT_BUFF_ID = {
	-- 常规职业BUFF
	[362]  = true,
	[673]  = true,
	[112]  = true,
	[382]  = true,
	[2837] = true,
	-- 红篮球
	[6329] = true,
	[6330] = true,
	-- 帮会菜盘
	[2564] = true,
	[2563] = true,
	-- 七秀扇子
	[3098] = true,
	-- 缝针 / 凤凰谷
	[2313] = true,
	[5970] = true,
}
local RT_GONGZHAN_ID = 3219
-- default sort
local RT_SORT_MODE    = "DESC"
local RT_SORT_FIELD   = "nEquipScore"
local RT_SELECT_PAGE  = 0
local RT_SELECT_KUNGFU
local RT_SELECT_DEATH
--
local RT_SCORE_FULL = 15000
local RT = {
	tAnchor = {},
	tDamage = {},
	tDeath  = {},
}

RaidTools = {
	nStyle = 1,
}

JH.RegisterCustomData("RaidTools")

function RaidTools.OnFrameCreate()
	this:RegisterEvent("UI_SCALED")
	this:RegisterEvent("PEEK_OTHER_PLAYER")
	this:RegisterEvent("PARTY_ADD_MEMBER")
	this:RegisterEvent("PARTY_DISBAND")
	this:RegisterEvent("PARTY_DELETE_MEMBER")
	this:RegisterEvent("PARTY_SET_MEMBER_ONLINE_FLAG")
	this:RegisterEvent("LOADING_END")
	-- 团长变更 重新请求标签
	this:RegisterEvent("TEAM_AUTHORITY_CHANGED")
	-- 自定义事件
	this:RegisterEvent("JH_RAIDTOOLS_SUCCESS")
	this:RegisterEvent("JH_RAIDTOOLS_DEATH")
	-- 重置心法选择
	RT_SELECT_KUNGFU = nil
	-- 注册关闭
	JH.RegisterGlobalEsc("RaidTools", RT.IsOpened, RT.ClosePanel)
	-- 标题修改
	local title = _L["Raid Tools"]
	if JH.IsInParty() then
		local team = GetClientTeam()
		local info = team.GetMemberInfo(team.GetAuthorityInfo(TEAM_AUTHORITY_TYPE.LEADER))
		title = _L("%s's Team", info.szName) .. " (" .. team.GetTeamSize() .. "/" .. team.nGroupNum * 5  .. ")"
	end
	local ui          = GUI(this):Title(title):RegisterClose(RT.ClosePanel)
	this.hPlayer      = this:CreateItemData(RT_INIFILE, "Handle_Item_Player")
	this.hDeathPlayer = this:CreateItemData(RT_INIFILE, "Handle_Item_DeathPlayer")
	this.hPageSet     = this:Lookup("PageSet_Main")
	this.hList        = this.hPageSet:Lookup("Page_Info/Scroll_Player", "")
	this.hDeatList    = this.hPageSet:Lookup("Page_Death/Scroll_Player_List", "")
	this.hDeatMsg     = this.hPageSet:Lookup("Page_Death/Scroll_Death_Info", "")

	this.tScore       = {}
	-- 排序
	local hTitle  = this.hPageSet:Lookup("Page_Info", "Handle_Player_BG")
	for k, v in ipairs({ "dwForceID", "tFood", "tBuff", "tEquip", "nEquipScore", "nFightState" }) do
		local txt = hTitle:Lookup("Text_Title_" .. k)
		txt.nFont = txt:GetFontScheme()
		txt.OnItemMouseEnter = function()
			this:SetFontScheme(101)
		end
		txt.OnItemMouseLeave = function()
			this:SetFontScheme(this.nFont)
		end
		txt.OnItemLButtonClick = function()
			local frame = RT.GetFrame()
			if v == RT_SORT_FIELD then
				RT_SORT_MODE = RT_SORT_MODE == "ASC" and "DESC" or "ASC"
			else
				RT_SORT_MODE = "DESC"
			end
			RT_SORT_FIELD = v
			RT.UpdateList() -- set userdata
			frame.hList:Sort()
			frame.hList:FormatAllItemPos()
		end
	end
	-- 装备分
	this.hTotalScore = this.hPageSet:Lookup("Page_Info", "Handle_Score/Text_TotalScore")
	this.hProgress   = this.hPageSet:Lookup("Page_Info", "Handle_Progress")
	-- 副本信息
	local hDungeon = this.hPageSet:Lookup("Page_Info", "Handle_Dungeon")
	RT.UpdateDungeonInfo(hDungeon)
	this.hKungfuList = this.hPageSet:Lookup("Page_Info", "Handle_Kungfu/Handle_Kungfu_List")
	this.hKungfu     = this:CreateItemData(RT_INIFILE, "Handle_Kungfu_Item")
	this.hKungfuList:Clear()
	for k, v in pairs(JH_KUNGFU_LIST) do
		local h = this.hKungfuList:AppendItemFromData(this.hKungfu, v[1])
		local img = h:Lookup("Image_Force")
		img:FromIconID(select(2, JH.GetSkillName(v[1])))
		h:Lookup("Text_Num"):SetText(0)
		h.nFont = h:Lookup("Text_Num"):GetFontScheme()
		h.OnItemMouseLeave = function()
			HideTip()
			if RT_SELECT_KUNGFU == tonumber(this:GetName()) then
				this:Lookup("Text_Num"):SetFontScheme(101)
			else
				this:Lookup("Text_Num"):SetFontScheme(h.nFont)
			end
		end
		h.OnItemLButtonClick = function()
			if this:GetAlpha() ~= 255 then
				return
			end
			local frame = RT.GetFrame()
			frame.hList:Clear()
			if RT_SELECT_KUNGFU then
				if RT_SELECT_KUNGFU == tonumber(this:GetName()) then
					RT_SELECT_KUNGFU = nil
					h:Lookup("Text_Num"):SetFontScheme(101)
					return RT.UpdateList()
				else
					local h = this:GetParent():Lookup(tostring(RT_SELECT_KUNGFU))
					h:Lookup("Text_Num"):SetFontScheme(h.nFont)
				end
			end
			RT_SELECT_KUNGFU = tonumber(this:GetName())
			this:Lookup("Text_Num"):SetFontScheme(101)
			RT.UpdateList()
		end
	end
	this.hKungfuList:FormatAllItemPos()
	-- ui 临时变量
	this.tViewInvite = {} -- 请求装备队列
	this.tDataCache  = {} -- 临时数据
	-- 追加呼吸
	this.hPageSet:ActivePage(RT_SELECT_PAGE)
	-- 追加几个按钮
	ui:Fetch("PageSet_Main/Page_Death"):Fetch("Btn_All"):Click(function()
		RT_SELECT_DEATH = nil
		RT.UpdatetDeathMsg()
	end)
	ui:Fetch("PageSet_Main/Page_Death"):Fetch("Btn_Clear"):Click(function()
		JH.Confirm(_L["Wipe Record"], function()
			RT.tDeath = {}
			RT.UpdatetDeathPage()
		end)
	end)
	ui:Fetch("Btn_Style"):Click(function()
		RaidTools.nStyle = RaidTools.nStyle == 1 and 2 or 1
		RT.SetStyle()
		RT.ClosePanel()
		RT.OpenPanel()
	end)
	RT.UpdateAnchor(this)
end

function RaidTools.OnEvent(szEvent)
	if szEvent == "PEEK_OTHER_PLAYER" then
		if arg0 == PEEK_OTHER_PLAYER_RESPOND.SUCCESS then
			if this.tViewInvite[arg1] then
				RT.GetEquipCache(GetPlayer(arg1)) -- 抓取所有数据
			end
		else
			this.tViewInvite[arg1] = nil
		end
	elseif szEvent == "PARTY_SET_MEMBER_ONLINE_FLAG" then
		if arg2 == 0 then
			this.tDataCache[arg1] = nil
		end
	elseif szEvent == "PARTY_DELETE_MEMBER" then
		local me = GetClientPlayer()
		if me.dwID == arg1 then
			this.tDataCache = {}
			this.hList:Clear()
		else
			this.tDataCache[arg1] = nil
		end
	elseif szEvent == "LOADING_END" or szEvent == "PARTY_DISBAND" then
		this.tDataCache = {}
		this.hList:Clear()
		RT.UpdatetDeathPage()
		-- 副本信息
		local hDungeon = this.hPageSet:Lookup("Page_Info", "Handle_Dungeon")
		RT.UpdateDungeonInfo(hDungeon)
	elseif szEvent == "UI_SCALED" then
		RT.UpdateAnchor(this)
	elseif szEvent == "JH_RAIDTOOLS_SUCCESS" then
		if RT_SORT_FIELD   == "nEquipScore" then
			RT.UpdateList()
			this.hList:Sort()
			this.hList:FormatAllItemPos()
		end
	elseif szEvent == "JH_RAIDTOOLS_DEATH" then
		local nPage = this.hPageSet:GetActivePageIndex()
		if nPage == 1 then
			RT.UpdatetDeathPage()
		end
	end
	-- update title
	if szEvent == "PARTY_ADD_MEMBER"
		or szEvent == "PARTY_DELETE_MEMBER"
		or szEvent == "TEAM_AUTHORITY_CHANGED"
	then
		local team = GetClientTeam()
		local dwID = team.GetAuthorityInfo(TEAM_AUTHORITY_TYPE.LEADER)
		local info = team.GetMemberInfo(dwID)
		GUI(this):Title(_L("%s's Team", info.szName) .. " (" .. team.GetTeamSize() .. "/" .. team.nGroupNum * 5  .. ")")
	end
end

function RaidTools.OnActivePage()
	local nPage = this:GetActivePageIndex()
	if nPage == 0 then
		JH.BreatheCall("JH_RaidTools", RT.UpdateList, 1000)
		JH.BreatheCall("JH_RaidTools_Clear", RT.GetEquip, 3000)
		local hView = RT.GetPlayerView()
		if hView and hView:IsVisible() then
			hView:Hide()
		end
	else
		JH.UnBreatheCall("JH_RaidTools")
		JH.UnBreatheCall("JH_RaidTools_Clear")
	end
	if nPage == 1 then
		RT.UpdatetDeathPage()
	end
	RT_SELECT_PAGE = nPage
end

function RaidTools.OnItemMouseEnter()
	local szName = this:GetName()
	if szName == "Handle_Score" then
		local frame = RT.GetFrame()
		local img = this:Lookup("Image_Score")
		img:SetFrame(23)
		local nScore = this:Lookup("Text_TotalScore"):GetText()
		local xml = {}
		tinsert(xml, GetFormatText(g_tStrings.STR_SCORE .. g_tStrings.STR_COLON .. nScore .."\n", 157))
		for k, v in pairs(frame.tScore) do
			tinsert(xml, GetFormatText(RT_SCORE[k] .. g_tStrings.STR_COLON ..  v  .."\n", 106))
		end
		local x, y = img:GetAbsPos()
		local w, h = img:GetSize()
		OutputTip(table.concat(xml), 400, { x, y, w, h })
	elseif tonumber(szName:find("D(%d+)")) then
		this:Lookup("Image_Cover"):Show()
	end
end

function RaidTools.OnItemMouseLeave()
	local szName = this:GetName()
	HideTip()
	if szName == "Handle_Score" then
		this:Lookup("Image_Score"):SetFrame(22)
	elseif tonumber(szName:find("D(%d+)")) then
		if this and this:Lookup("Image_Cover") and this:Lookup("Image_Cover"):IsValid() then
			this:Lookup("Image_Cover"):Hide()
		end
	end
end

function RaidTools.OnFrameDragEnd()
	RT.tAnchor = GetFrameAnchor(this)
end

function RT.UpdateAnchor(frame)
	local a = RT.tAnchor
	if not IsEmpty(a) then
		frame:SetPoint(a.s, 0, 0, a.r, a.x, a.y)
	else
		frame:SetPoint("CENTER", 0, 0, "CENTER", 0, 0)
	end
end

function RaidTools.OnItemLButtonClick()
	local szName = this:GetName()
	if tonumber(szName:find("P(%d+)")) then
		local dwID = tonumber(szName:match("P(%d+)"))
		if IsCtrlKeyDown() then
			 EditBox_AppendLinkPlayer(this.szName)
		else
			RT.ViewInviteToPlayer(dwID)
		end
	elseif tonumber(szName:find("D(%d+)")) then
		local dwID = tonumber(szName:match("D(%d+)"))
		if IsCtrlKeyDown() then
			 EditBox_AppendLinkPlayer(this.szName)
		else
			RT_SELECT_DEATH = dwID
			RT.UpdatetDeathMsg(dwID)
		end
	end
end

function RaidTools.OnItemRButtonClick()
	local szName = this:GetName()
	local dwID = tonumber(szName:match("P(%d+)"))
	local me = GetClientPlayer()
	if dwID and dwID ~= me.dwID then
		local menu = {
			{ szOption = this.szName, bDisable = true },
			{ bDevide = true }
		}
		InsertPlayerCommonMenu(menu, dwID, this.szName)
		menu[#menu] = {
			szOption = g_tStrings.STR_LOOKUP, fnAction = function()
				RT.ViewInviteToPlayer(dwID)
			end
		}
		PopupMenu(menu)
	end
end

function RT.UpdateDungeonInfo(hDungeon)
	local me = GetClientPlayer()
	if JH.IsInDungeon(true) then
		local scene = me.GetScene()
		hDungeon:Lookup("Text_Dungeon"):SetText(Table_GetMapName(me.GetMapID()) .. "\n" .. "ID:(" .. scene.nCopyIndex  ..")")
		hDungeon:Show()
	else
		hDungeon:Hide()
	end
end

function RT.GetPlayerView()
	return Station.Lookup("Normal/PlayerView")
end

function RT.ViewInviteToPlayer(dwID)
	local frame = RT.GetFrame()
	local me = GetClientPlayer()
	if dwID ~= me.dwID then
		frame.tViewInvite[dwID] = true
		ViewInviteToPlayer(dwID)
	end
end
-- 分数计算
function RT.CountScore(tab, tScore)
	tScore.Food = tScore.Food + #tab.tFood * 100
	tScore.Buff = tScore.Buff + #tab.tBuff * 20
	if tab.nEquipScore then
		tScore.Equip = tScore.Equip + tab.nEquipScore
	end
	if tab.tTemporaryEnchant then
		tScore.Enchant = tScore.Enchant + #tab.tTemporaryEnchant * 300
	end
	if tab.tPermanentEnchant then
		tScore.Enchant = tScore.Enchant + #tab.tPermanentEnchant * 100
	end
	if tab.tEquip then
		for k, v in ipairs(tab.tEquip) do
			tScore.Special = tScore.Special + v.nLevel * 0.15 *  v.nQuality
		end
	end
end
-- 更新UI 没什么特殊情况 不要clear
function RT.UpdateList()
	local me = GetClientPlayer()
	if not me then return end
	local aTeam, frame, tKungfu = RT.GetTeam(), RT.GetFrame(), {}
	local tScore = {
		Equip   = 0,
		Buff    = 0,
		Food    = 0,
		Enchant = 0,
		Special = 0,
	}

	table.sort(aTeam, function(a, b)
		local nCountA, nCountB = -2, -2
		if a[RT_SORT_FIELD] then
			if type(a[RT_SORT_FIELD]) == "table" then
				nCountA = #a[RT_SORT_FIELD]
			else
				nCountA = a[RT_SORT_FIELD]
			end
		end
		if b[RT_SORT_FIELD] then
			if type(b[RT_SORT_FIELD]) == "table" then
				nCountB = #b[RT_SORT_FIELD]
			else
				nCountB = b[RT_SORT_FIELD]
			end
		end
		if nCountA == 0 and not a.bIsOnLine then
			nCountA = -2
		end
		if nCountB == 0 and not b.bIsOnLine then
			nCountB = -2
		end

		if RT_SORT_MODE == "ASC" then -- 升序
			return nCountA < nCountB
		else
			return nCountA > nCountB
		end
	end)

	for k, v in ipairs(aTeam) do
		-- 心法统计
		tKungfu[v.dwMountKungfuID] = tKungfu[v.dwMountKungfuID] or {}
		tinsert(tKungfu[v.dwMountKungfuID], v)
		RT.CountScore(v, tScore)
		if not RT_SELECT_KUNGFU or (RT_SELECT_KUNGFU and v.dwMountKungfuID == RT_SELECT_KUNGFU) then
			local szName = "P" .. v.dwID
			local h = frame.hList:Lookup(szName)
			if not h then
				h = frame.hList:AppendItemFromData(frame.hPlayer)
			end
			h:SetUserData(k)
			h:SetName(szName)
			h.dwID   = v.dwID
			h.szName = v.szName
			if v.dwMountKungfuID and v.dwMountKungfuID ~= 0 then
				local nIcon = select(2, JH.GetSkillName(v.dwMountKungfuID, 1))
				h:Lookup("Image_Icon"):FromIconID(nIcon)
			else
				h:Lookup("Image_Icon"):FromUITex(GetForceImage(v.dwForceID))
			end
			h:Lookup("Text_Name"):SetText(v.szName)
			h:Lookup("Text_Name"):SetFontColor(JH.GetForceColor(v.dwForceID))
			local hScore = h:Lookup("Text_Score")
			if v.nEquipScore then
				hScore:SetText(v.nEquipScore)
			else
				if v.bIsOnLine then
					hScore:SetText(_L["Loading"])
				else
					hScore:SetText(g_tStrings.STR_GUILD_OFFLINE)
				end
			end
			if v.nFightState == 1 then
				h:Lookup("Image_Fight"):Show()
			else
				h:Lookup("Image_Fight"):Hide()
			end
			for kk, vv in ipairs({ "Handle_Food", "Handle_Equip" }) do
				if not h["h" .. vv] then
					h["h" .. vv] = {
						self = h:Lookup(vv),
						Pool = JH.HandlePool(h:Lookup(vv), "<box>w=29 h=29 eventid=784</box>")
					}
				end
			end
			local hBuff = h:Lookup("Box_Buff")
			local hBox = h:Lookup("Box_Grandpa")
			if not v.bIsOnLine then
				h.hHandle_Equip.Pool:Clear()
				h:Lookup("Text_Toofar1"):Show()
				h:Lookup("Text_Toofar1"):SetText(g_tStrings.STR_GUILD_OFFLINE)
			end

			if not v.p then
				h.hHandle_Food.Pool:Clear()
				h:Lookup("Text_Toofar1"):Show()
				if v.bIsOnLine then
					h:Lookup("Text_Toofar1"):SetText(_L["Too Far"])
				end
				hBuff:Hide()
				hBox:Hide()
			else
				hBuff:Show()
				hBox:Show()
				h:Lookup("Text_Toofar1"):Hide()
				-- 小药UI处理
				local handle_food = h.hHandle_Food.self
				for kk, vv in ipairs(v.tFood) do
					local szName = vv.dwID .. "_" .. vv.nLevel
					local nIcon = select(2, JH.GetBuffName(vv.dwID, vv.nLevel))
					local box = handle_food:Lookup(szName)
					if not box then
						box = h.hHandle_Food.Pool:New()
					end
					box:SetName(szName)
					box:SetObject(UI_OBJECT_NOT_NEED_KNOWN, vv.dwID, vv.nLevel, vv.nEndFrame)
					box:SetObjectIcon(nIcon)
					box.OnItemMouseLeave = function()
						this:SetObjectMouseOver(false)
						HideTip()
					end
					box.OnItemMouseEnter = function()
						this:SetObjectMouseOver(true)
					end
					box.OnItemRefreshTip = function()
						local dwID, nLevel, nEndFrame = select(2, this:GetObject())
						local nTime = (nEndFrame - GetLogicFrameCount()) / 16
						local x, y = this:GetAbsPos()
						local w, h = this:GetSize()
						JH.OutputBuffTip(dwID, nLevel, { x, y, w, h }, nTime)
					end
					local nTime = (vv.nEndFrame - GetLogicFrameCount()) / 16
					if nTime < 480 then
						box:SetAlpha(80)
					else
						box:SetAlpha(255)
					end
					box:Show()
				end
				for i = 0, handle_food:GetItemCount() - 1, 1 do
					local item = handle_food:Lookup(i)
					if item and not item.bFree then
						local dwID, nLevel, nEndFrame = select(2, item:GetObject())
						if dwID and nLevel then
							if not JH.GetBuff(dwID, nLevel, v.p) then
								h.hHandle_Food.Pool:Remove(item)
							end
						end
					end
				end
				handle_food:FormatAllItemPos()
				-- BUFF UI处理
				if v.tBuff and #v.tBuff > 0 then
					hBuff:EnableObject(true)
					hBuff:SetOverTextPosition(0, ITEM_POSITION.RIGHT_BOTTOM)
					hBuff:SetOverTextFontScheme(1, 197)
					hBuff:SetOverText(1, #v.tBuff)
					hBuff.OnItemMouseLeave = function()
						this:SetObjectMouseOver(false)
						HideTip()
					end
					hBuff.OnItemMouseEnter = function()
						this:SetObjectMouseOver(true)
						local x, y = this:GetAbsPos()
						local w, h = this:GetSize()
						local xml = {}
						for k, v in ipairs(v.tBuff) do
							local nIcon = select(2, JH.GetBuffName(v.dwID, v.nLevel))
							local nTime = (v.nEndFrame - GetLogicFrameCount()) / 16
							local nAlpha = nTime < 600 and 80 or 255
							tinsert(xml, "<image> path=\"fromiconid\" frame=" .. nIcon .." alpha=" .. nAlpha ..  " w=30 h=30 </image>")
						end
						OutputTip(table.concat(xml), 250, { x, y, w, h })
					end
				else
					hBuff:SetOverText(1, "")
					hBuff.OnItemMouseEnter = nil
					hBuff.OnItemMouseLeave = nil
					hBuff:EnableObject(false)
				end
				if v.bGrandpa then
					hBox:EnableObject(true)
					hBox.OnItemMouseLeave = function()
						this:SetObjectMouseOver(false)
						HideTip()
					end
					hBox.OnItemMouseEnter = function()
						this:SetObjectMouseOver(true)
						local x, y = this:GetAbsPos()
						local w, h = this:GetSize()
						local kBuff = JH.GetBuff(RT_GONGZHAN_ID, v.p)
						if kBuff then
							JH.OutputBuffTip(kBuff.dwID, kBuff.nLevel, { x, y, w, h })
						end
					end
				end
				hBox:EnableObject(v.bGrandpa)
			end
			if v.tTemporaryEnchant and #v.tTemporaryEnchant > 0 then
				local vv = v.tTemporaryEnchant[1]
				local box = h:Lookup("Box_Enchant")
				box:Show()
				box.OnItemMouseLeave = function()
					this:SetObjectMouseOver(false)
					HideTip()
				end
				box.OnItemMouseEnter = function()
					this:SetObjectMouseOver(true)
				end
				box.OnItemRefreshTip = function()
					local desc = Table_GetCommonEnchantDesc(vv.dwTemporaryEnchantID)
					if desc then
						local x, y = this:GetAbsPos()
						local w, h = this:GetSize()
						OutputTip(desc:gsub("font=%d+", "font=113") .. GetFormatText(FormatString(g_tStrings.STR_ITEM_TEMP_ECHANT_LEFT_TIME .."\n", GetTimeText(vv.nTemporaryEnchantLeftSeconds)), 102), 400, { x, y, w, h })
					end
				end
				if vv.nTemporaryEnchantLeftSeconds < 480 then
					box:SetAlpha(80)
				else
					box:SetAlpha(255)
				end
			else
				h:Lookup("Box_Enchant"):Hide()
			end
			-- 装备处理
			if v.tEquip and #v.tEquip > 0 then
				local handle_equip = h.hHandle_Equip.self
				for kk, vv in ipairs(v.tEquip) do

					local szName = tostring(vv.nUiId)
					local box = handle_equip:Lookup(szName)
					if not box then
						box = h.hHandle_Equip.Pool:New()
						JH.UpdateItemBoxExtend(box, vv.nQuality)
					end
					box:SetName(szName)
					box:SetObject(UI_OBJECT_OTER_PLAYER_ITEM, vv.nUiId, vv.dwBox, vv.dwX, v.dwID)
					box:SetObjectIcon(vv.nIcon)
					local item = GetItem(vv.dwID)
					if item then
						UpdataItemBoxObject(box, vv.dwBox, vv.dwX, item, nil, nil, v.dwID)
					end
					box.OnItemRefreshTip = function()
						local x, y = this:GetAbsPos()
						local w, h = this:GetSize()
						if not GetItem(vv.dwID) then
							RT.GetTotalEquipScore(v.dwID)
							OutputItemTip(UI_OBJECT_ITEM_INFO, GLOBAL.CURRENT_ITEM_VERSION, vv.dwTabType, vv.dwIndex, {x, y, w, h})
						else
							OutputItemTip(UI_OBJECT_ITEM_ONLY_ID, vv.dwID, nil, nil, { x, y, w, h })
						end
					end
					box:Show()
				end
				for i = 0, handle_equip:GetItemCount() - 1, 1 do
					local item = handle_equip:Lookup(i)
					if item and not item.bFree then
						local nUiId, bDelete = item:GetName(), true
						for kk ,vv in ipairs(v.tEquip) do
							if tostring(vv.nUiId) == nUiId then
								bDelete = false
								break
							end
						end
						if bDelete then
							h.hHandle_Equip.Pool:Remove(item)
						end
					end
				end
				handle_equip:FormatAllItemPos()
			end
		end
	end
	frame.hList:FormatAllItemPos()
	for i = 0, frame.hList:GetItemCount() - 1, 1 do
		local item = frame.hList:Lookup(i)
		if item and item:IsValid() then
			if not JH.IsParty(item.dwID) and item.dwID ~= me.dwID then
				frame.hList:RemoveItem(item)
				frame.hList:FormatAllItemPos()
			end
		end
	end
	-- 分数
	frame.tScore = tScore
	local nScore = 0
	for k, v in pairs(tScore) do
		nScore = nScore + v
	end
	frame.hTotalScore:SetText(math.floor(nScore))
	local nNum      = #RT.GetTeamMemberList(true)
	local nAvgScore = nScore / nNum
	frame.hProgress:Lookup("Image_Progress"):SetPercentage(nAvgScore / RT_SCORE_FULL)
	frame.hProgress:Lookup("Text_Progress"):SetText(_L("Team strength(%d/%d)", math.floor(nAvgScore), RT_SCORE_FULL))
	-- 心法统计
	for k, v in pairs(JH_KUNGFU_LIST) do
		local h = frame.hKungfuList:Lookup(k - 1)
		local img = h:Lookup("Image_Force")
		local nCount = 0
		if tKungfu[v[1]] then
			nCount = #tKungfu[v[1]]
		end
		local szName, nIcon = JH.GetSkillName(v[1])
		img:FromIconID(nIcon)
		h:Lookup("Text_Num"):SetText(nCount)
		if not tKungfu[v[1]] then
			h:SetAlpha(60)
			h.OnItemMouseEnter = nil
		else
			h:SetAlpha(255)
			h.OnItemMouseEnter = function()
				this:Lookup("Text_Num"):SetFontScheme(101)
				local xml = {}
				tinsert(xml, GetFormatText(szName .. g_tStrings.STR_COLON .. nCount .. g_tStrings.STR_PERSON .."\n", 157))
				table.sort(tKungfu[v[1]], function(a, b)
					local nCountA = a.nEquipScore or -1
					local nCountB = b.nEquipScore or -1
					return nCountA > nCountB
				end)
				for k, v in ipairs(tKungfu[v[1]]) do
					if v.nEquipScore then
						tinsert(xml, GetFormatText(v.szName .. g_tStrings.STR_COLON ..  v.nEquipScore  .."\n", 106))
					else
						tinsert(xml, GetFormatText(v.szName .."\n", 106))
					end
				end
				local x, y = img:GetAbsPos()
				local w, h = img:GetSize()
				OutputTip(table.concat(xml), 400, { x, y, w, h })
			end
		end
	end
end

local function CreateItemTable(item, dwBox, dwX)
	return {
		nIcon     = Table_GetItemIconID(item.nUiId),
		dwID      = item.dwID,
		nLevel    = item.nLevel,
		szName    = Table_GetItemName(item.nUiId),
		nUiId     = item.nUiId,
		nVersion  = item.nVersion,
		dwTabType = item.dwTabType,
		dwIndex   = item.dwIndex,
		nQuality  = item.nQuality,
		dwBox     = dwBox,
		dwX       = dwX
	}
end

function RT.GetEquipCache(p)
	if not p then return end
	local me = GetClientPlayer()
	local frame = RT.GetFrame()
	local aInfo = {
		tEquip            = {},
		tPermanentEnchant = {},
		tTemporaryEnchant = {}
	}
	-- 装备 Output(GetClientPlayer().GetItem(0,0).GetMagicAttrib())
	for _, equip in ipairs(RT_EQUIP_TOTAL) do
		if #aInfo.tEquip >= 3 then break end
		-- 藏剑只看重剑
		if p.dwForceID == 8 and EQUIPMENT_INVENTORY[equip] == EQUIPMENT_INVENTORY.MELEE_WEAPON then
			equip = "BIG_SWORD"
		end
		local dwBox, dwX = INVENTORY_INDEX.EQUIP, EQUIPMENT_INVENTORY[equip]
		local item = p.GetItem(dwBox, dwX)
		if item then
			if RT_EQUIP_SPECIAL[equip] then
				if equip == "PENDANT" then
					local desc = Table_GetItemDesc(item.nUiId)
					if desc and (desc:find(_L["use"] .. g_tStrings.STR_COLON) or desc:find(_L["Use:"]) or desc:find("15" .. g_tStrings.STR_TIME_SECOND)) then
						tinsert(aInfo.tEquip, CreateItemTable(item, dwBox, dwX))
					end
				-- elseif item.nQuality == 5 then -- 橙色装备
				-- 	tinsert(aInfo.tEquip, CreateItemTable(item))
				else
					-- 黄字装备
					local aMagicAttrib = item.GetMagicAttrib()
					for _, tAttrib in ipairs(aMagicAttrib) do
						if tAttrib.nID == 317 or tAttrib.nID == 318 then
							tinsert(aInfo.tEquip, CreateItemTable(item, dwBox, dwX))
							break
						end
					end
				end
			end
			-- 永久的附魔 用于评分
			if item.dwPermanentEnchantID and item.dwPermanentEnchantID ~= 0 then
				tinsert(aInfo.tPermanentEnchant, {
					dwPermanentEnchantID = item.dwPermanentEnchantID,
				})
			end
			-- 大附魔 / 临时附魔 用于评分
			if item.dwTemporaryEnchantID and item.dwTemporaryEnchantID ~= 0 then
				if Table_GetCommonEnchantDesc(item.dwTemporaryEnchantID) then
					tinsert(aInfo.tTemporaryEnchant, {
						dwTemporaryEnchantID         = item.dwTemporaryEnchantID,
						nTemporaryEnchantLeftSeconds = item.GetTemporaryEnchantLeftSeconds()
					})
				else
					tinsert(aInfo.tPermanentEnchant, {
						dwPermanentEnchantID = item.dwTemporaryEnchantID,
					})
				end
			end
		end
	end
	-- 这些都是一次性的缓存数据
	frame.tDataCache[p.dwID] = {
		tEquip            = aInfo.tEquip,
		tPermanentEnchant = aInfo.tPermanentEnchant,
		tTemporaryEnchant = aInfo.tTemporaryEnchant,
		nEquipScore       = p.GetTotalEquipScore()
	}
	frame.tViewInvite[p.dwID] = nil
	if IsEmpty(frame.tViewInvite) then
		if p.dwID ~= me.dwID then
			FireUIEvent("JH_RAIDTOOLS_SUCCESS") -- 装备请求完毕
		end
	else
		ViewInviteToPlayer(next(frame.tViewInvite), true)
	end
end

function RT.GetTotalEquipScore(dwID)
	local frame = RT.GetFrame()
	if not frame.tViewInvite[dwID] then
		frame.tViewInvite[dwID] = true
		ViewInviteToPlayer(dwID, true)
	end
end

-- 获取团队大部分情况 非缓存
function RT.GetTeam()
	local me    = GetClientPlayer()
	local team  = GetClientTeam()
	local aList = {}
	local frame = RT.GetFrame()
	local bIsInParty = JH.IsInParty()
	for k, v in ipairs(RT.GetTeamMemberList()) do
		local p = GetPlayer(v)
		local info = bIsInParty and team.GetMemberInfo(v) or {}
		local aInfo = {
			p                 = p,
			szName            = p and p.szName or info.szName or _L["Loading..."],
			dwID              = v,  -- ID
			dwForceID         = p and p.dwForceID or info.dwForceID, -- 门派ID
			dwMountKungfuID   = info and info.dwMountKungfuID or UI_GetPlayerMountKungfuID(), -- 内功
			-- tPermanentEnchant = {}, -- 附魔
			-- tTemporaryEnchant = {}, -- 临时附魔
			-- tEquip            = {}, -- 特效装备
			tBuff             = {}, -- 增益BUFF
			tFood             = {}, -- 小吃和附魔
			-- nEquipScore       = -1,  -- 装备分
			nFightState       = p and p.bFightState and 1 or 0, -- 战斗状态
			bIsOnLine         = true,
			bGrandpa          = false, -- 大爷
		}
		if info and info.bIsOnLine ~= nil then
			aInfo.bIsOnLine = info.bIsOnLine
		end
		if p then
			-- 小吃和buff
			for _, tBuff in ipairs(JH.GetBuffList(p)) do
				local nType = GetBuffInfo(tBuff.dwID, tBuff.nLevel, {}).nDetachType or 0
				if RT_FOOD_TYPE[nType] then
					tinsert(aInfo.tFood, tBuff)
				end
				if RT_BUFF_ID[tBuff.dwID] then
					tinsert(aInfo.tBuff, tBuff)
				end
				if tBuff.dwID == RT_GONGZHAN_ID then -- grandpa
					aInfo.bGrandpa = true
				end
			end
			if me.dwID == p.dwID then
				RT.GetEquipCache(me)
			end
		end
		setmetatable(aInfo, { __index = frame.tDataCache[v] })
		tinsert(aList, aInfo)
	end
	return aList
end

function RT.GetEquip()
	local hView = RT.GetPlayerView()
	if hView and hView:IsVisible() then -- 查看装备的时候停止请求
		return
	end
	local me = GetClientPlayer()
	if not me then return end
	local frame = RT.GetFrame()
	local team  = GetClientTeam()
	for k, v in ipairs(RT.GetTeamMemberList()) do
		if v ~= me.dwID then
			local info = team.GetMemberInfo(v)
			if info.bIsOnLine then
				RT.GetTotalEquipScore(v)
			end
		end
	end
end

-- 获取团队成员列表
function RT.GetTeamMemberList(bIsOnLine)
	local me   = GetClientPlayer()
	local team = GetClientTeam()
	if me.IsInParty() then
		if bIsOnLine then
			local tTeam = {}
			for k, v in ipairs(team.GetTeamMemberList()) do
				local info = team.GetMemberInfo(v)
				if info and info.bIsOnLine then
					tinsert(tTeam, v)
				end
			end
			return tTeam
		else
			return team.GetTeamMemberList()
		end
	else
		return { me.dwID }
	end
end

-- 重伤记录
function RT.UpdatetDeathPage()
	local frame = RT.GetFrame()
	local team  = GetClientTeam()
	local me    = GetClientPlayer()
	frame.hDeatList:Clear()
	local tList = {}
	for k, v in pairs(RT.tDeath) do
		tinsert(tList, {
			dwID   = k,
			nCount = #v
		})
	end
	table.sort(tList, function(a, b)
		return a.nCount > b.nCount
	end)
	for k, v in ipairs(tList) do
		local dwID = v.dwID == "self" and me.dwID or v.dwID
		local info = team.GetMemberInfo(dwID)
		if info or dwID == me.dwID then
			local h = frame.hDeatList:AppendItemFromData(frame.hDeathPlayer, "D" .. dwID)
			local icon = select(2, JH.GetSkillName(info and info.dwMountKungfuID or UI_GetPlayerMountKungfuID()))
			local szName = info and info.szName or me.szName
			h.szName = szName
			h:Lookup("Image_DeathIcon"):FromIconID(icon)
			h:Lookup("Text_DeathName"):SetText(szName)
			h:Lookup("Text_DeathName"):SetFontColor(JH.GetForceColor(info and info.dwForceID or me.dwForceID))
			h:Lookup("Text_DeathCount"):SetText(v.nCount)
		end
	end
	frame.hDeatList:FormatAllItemPos()
	RT.UpdatetDeathMsg(RT_SELECT_DEATH)
end

function RaidTools.OnShowDeathInfo()
	local dwID, i = this:GetName():match("(%d+)_(%d+)")
	if dwID then
		dwID, i = tonumber(dwID), tonumber(i)
	else
		dwID = "self"
		i = tonumber(this:GetName():match("self_(%d+)"))
	end
	if  RT.tDeath[dwID] and  RT.tDeath[dwID][i] then
		local data = RT.tDeath[dwID][i]
		if data.tResult and data.szSkill then
			local xml = {
				GetFormatText("[" .. data.szSkill .. "]" .. (data.bCriticalStrike and g_tStrings.STR_SKILL_CRITICALSTRIKE or "") .. "\n" , 41, 255, 128, 0),
			}
			for k, v in pairs(data.tResult) do
				if v > 0 then
					tinsert(xml, GetFormatText(_L[RT_SKILL_TYPE[k]] .. g_tStrings.STR_COLON, 157))
					tinsert(xml, GetFormatText(v .. "\n", 41))
				end
			end
			local x, y = this:GetAbsPos()
			local w, h = this:GetSize()
			OutputTip(table.concat(xml), 400, { x, y, w, h })
		end
	end
end

function RaidTools.OnAppendEdit()
	local handle = this:GetParent()
	local edit = Station.Lookup("Lowest2/EditBox/Edit_Input")
	edit:ClearText()
	for i = this:GetIndex() + 1, handle:GetItemCount() do
		local h = handle:Lookup(i)
		local szText = h:GetText()
		if szText == "\n" then
			break
		end
		if h:GetName() == "namelink" then
			edit:InsertObj(szText, { type = "name", text = szText, name = string.sub(szText, 2, -2) })
		else
			edit:InsertObj(szText, { type = "text", text = szText })
		end
	end
	Station.SetFocusWindow(edit)
end

function RT.UpdatetDeathMsg(dwID)
	local frame = RT.GetFrame()
	local me    = GetClientPlayer()
	local team  = GetClientTeam()
	local data  = {}
	local key = dwID == me.dwID and "self" or dwID
	if not dwID then
		for k, v in pairs(RT.tDeath) do
			for kk, vv in ipairs(v) do
				if k == "self" then
					vv.dwID = me.dwID
				else
					vv.dwID = k
				end
				vv.nIndex = kk
				tinsert(data, vv)
			end
		end
	else
		for k, v in ipairs(RT.tDeath[key] or {}) do
			if key == "self" then
				v.dwID = me.dwID
			else
				v.dwID = key
			end
			v.nIndex = k
			tinsert(data, v)
		end
	end
	table.sort(data, function(a, b) return a.nCurrentTime > b.nCurrentTime end)
	frame.hDeatMsg:Clear()
	for k, v in ipairs(data) do
		if JH.IsParty(v.dwID) or v.dwID == me.dwID then
			local info  = team.GetMemberInfo(v.dwID)
			local key = v.dwID == me.dwID and "self" or v.dwID
			local t = TimeToDate(v.nCurrentTime)
			local xml = {}
			tinsert(xml, GetFormatText(_L[" * "] .. string.format("[%02d:%02d:%02d]", t.hour, t.minute, t.second), 10, 255, 255, 255, 16, "this.OnItemLButtonClick = RaidTools.OnAppendEdit"))
			local r, g, b = JH.GetForceColor(info and info.dwForceID or me.dwForceID)
			tinsert(xml, GetFormatText("[" .. (info and info.szName or me.szName) .."]", 10, r, g, b, 16, "this.OnItemLButtonClick = function() OnItemLinkDown(this) end", "namelink"))
			tinsert(xml, GetFormatText(g_tStrings.TRADE_BE, 10, 255, 255, 255))
			tinsert(xml, GetFormatText("[" .. (v.szCaster or _L["OUTER GUEST"]) .."]", 10, 255, 128, 0, 16, "this.OnItemLButtonClick = function() OnItemLinkDown(this) end", "namelink"))
			if v.szSkill then
				tinsert(xml, GetFormatText(g_tStrings.STR_PET_SKILL_LOG, 10, 255, 255, 255))
				tinsert(xml, GetFormatText("[" .. v.szSkill .. "]", 10, 50, 150, 255, 256, "this.OnItemMouseEnter = RaidTools.OnShowDeathInfo; this.OnItemMouseLeave = function() HideTip() end", key .. "_" .. v.nIndex))
			end
			tinsert(xml, GetFormatText(g_tStrings.STR_KILL .. g_tStrings.STR_FULL_STOP, 10, 255, 255, 255))
			tinsert(xml, GetFormatText("\n"))
			frame.hDeatMsg:AppendItemFromString(table.concat(xml))
		end
	end
	frame.hDeatMsg:FormatAllItemPos()
end

function RT.OnSkillEffectLog(dwCaster, dwTarget, nEffectType, dwID, dwLevel, bCriticalStrike, nCount, tResult)
	local KCaster = IsPlayer(dwCaster) and GetPlayer(dwCaster) or GetNpc(dwCaster)
	local KTarget = IsPlayer(dwTarget) and GetPlayer(dwTarget) or GetNpc(dwTarget)
	if not (KCaster and KTarget) then
		return
	end
	local szSkill = nEffectType == SKILL_EFFECT_TYPE.SKILL and JH.GetSkillName(dwID, dwLevel) or JH.GetBuffName(dwID, dwLevel)
	local me = GetClientPlayer()
	local team = GetClientTeam()
	-- 普通伤害
	if IsPlayer(dwTarget) and (JH.IsParty(dwTarget) or dwTarget == me.dwID) then
		-- 五类伤害
		local szCaster = IsPlayer(dwCaster) and KCaster.szName or JH.GetObjName(KCaster)
		for k, v in ipairs({ "PHYSICS_DAMAGE", "SOLAR_MAGIC_DAMAGE", "NEUTRAL_MAGIC_DAMAGE", "LUNAR_MAGIC_DAMAGE", "POISON_DAMAGE" }) do
			if tResult[SKILL_RESULT_TYPE[v]] and tResult[SKILL_RESULT_TYPE[v]] ~= 0 then
				RT.tDamage[dwTarget == me.dwID and "self" or dwTarget] = {
					szCaster        = szCaster,
					szSkill         = szSkill .. (nEffectType == SKILL_EFFECT_TYPE.BUFF and "(BUFF)" or ""),
					tResult         = tResult,
					bCriticalStrike = bCriticalStrike,
				}
				break
			end
		end
	end
	-- 有反弹伤害
	if IsPlayer(dwCaster) and (JH.IsParty(dwCaster) or dwCaster == me.dwID) and tResult[SKILL_RESULT_TYPE.REFLECTIED_DAMAGE] then
		local szTarget = IsPlayer(dwTarget) and KTarget.szName or JH.GetObjName(KTarget)
		RT.tDamage[dwCaster == me.dwID and "self" or dwCaster] = {
			szCaster        = szTarget,
			szSkill         = szSkill .. (nEffectType == SKILL_EFFECT_TYPE.BUFF and "(BUFF)" or ""),
			tResult         = tResult,
			bCriticalStrike = bCriticalStrike,
		}
	end
end

-- 意外摔伤 会触发这个日志
function RT.OnCommonHealthLog(dwCharacterID, nDeltaLife)
	-- 过滤非玩家和治疗日志
	if not IsPlayer(dwCharacterID) or nDeltaLife > 0 then
		return
	end
	local p = GetPlayer(dwCharacterID)
	if not p then
		return
	end
	local me = GetClientPlayer()
	if JH.IsParty(dwCharacterID) or dwCharacterID == me.dwID then
		RT.tDamage[dwCharacterID == me.dwID and "self" or dwCharacterID] = {
			nCount   = nDeltaLife * -1,
		}
	end
end

function RT.OnSkill(dwCaster, dwSkillID, dwLevel)
	if dwSkillID ~= 608 or not IsPlayer(dwCaster) or not GetPlayer(dwCaster) then
		return
	end
	local me = GetClientPlayer()
	RT.tDamage[dwCaster == me.dwID and "self" or dwCaster] = {
		szCaster = GetPlayer(dwCaster).szName,
		szSkill  = JH.GetSkillName(dwSkillID, dwLevel),
	}
end

function RT.OnDeath(dwCharacterID, szKiller)
	local me = GetClientPlayer()
	if IsPlayer(dwCharacterID) and (JH.IsParty(dwCharacterID) or dwCharacterID == me.dwID) then
		dwCharacterID = dwCharacterID == me.dwID and "self" or dwCharacterID
		RT.tDeath[dwCharacterID] = RT.tDeath[dwCharacterID] or {}
		local nCurrentTime = GetCurrentTime()
		if RT.tDamage[dwCharacterID] then
			RT.tDamage[dwCharacterID].nCurrentTime = nCurrentTime
			tinsert(RT.tDeath[dwCharacterID], RT.tDamage[dwCharacterID])
		else
			tinsert(RT.tDeath[dwCharacterID], {
				nCurrentTime = nCurrentTime,
				szCaster     = szKiller ~= "" and szKiller or nil
			})
		end
		-- Output(RT.tDamage[dwCharacterID])
		RT.tDamage[dwCharacterID] = nil
		FireUIEvent("JH_RAIDTOOLS_DEATH", dwCharacterID)
	end
end

-- UI操作 惯例

function RT.SetStyle()
	RT_INIFILE = JH.GetAddonInfo().szRootPath .. "RaidTools/ui/RaidTools" .. RaidTools.nStyle .. ".ini"
end

function RT.GetFrame()
	return Station.Lookup("Normal/RaidTools")
end

RT.IsOpened = RT.GetFrame

function RT.OpenPanel()
	if not RT.IsOpened() then
		Wnd.OpenWindow(RT_INIFILE, "RaidTools")
		PlaySound(SOUND.UI_SOUND, g_sound.OpenFrame)
	end
end

function RT.ClosePanel()
	if RT.IsOpened() then
		local frame = RT.GetFrame()
		Wnd.CloseWindow(RT.GetFrame())
		PlaySound(SOUND.UI_SOUND, g_sound.CloseFrame)
		JH.UnBreatheCall("JH_RaidTools")
		JH.UnBreatheCall("JH_RaidTools_Clear")
		JH.RegisterGlobalEsc("RaidTools")
	end
end

function RT.TogglePanel()
	if RT.IsOpened() then
		RT.ClosePanel()
	else
		RT.OpenPanel()
	end
end

-- 过地图清空
JH.RegisterEvent("LOADING_END", function()
	RT.tDamage = {}
end)

JH.RegisterEvent("SYS_MSG", function()
	if arg0 == "UI_OME_DEATH_NOTIFY" then -- 死亡记录
		RT.OnDeath(arg1, arg3)
	elseif arg0 == "UI_OME_SKILL_EFFECT_LOG" then -- 技能记录
		RT.OnSkillEffectLog(arg1, arg2, arg4, arg5, arg6, arg7, arg8, arg9)
	elseif arg0 == "UI_OME_COMMON_HEALTH_LOG" then
		RT.OnCommonHealthLog(arg1, arg2)
	end
end)
JH.RegisterEvent("DO_SKILL_CAST", function()
	RT.OnSkill(arg0, arg1, arg2)
end)

JH.RegisterEvent("LOGIN_GAME", RT.SetStyle)

JH.PlayerAddonMenu({ szOption = _L["Open Raid Tools Panel"], fnAction = RT.TogglePanel })
JH.AddHotKey("JH_RaidTools", _L["Open Raid Tools Panel"], RT.TogglePanel)
