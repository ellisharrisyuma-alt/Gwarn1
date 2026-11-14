script_name('GwarnV1')
script_author('Ellis_Harris')
script_version('1.2.3')
script_description('Справочник уставов Arizona RP, штат Yuma')

require 'lib.moonloader'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local imgui = require 'mimgui'
local inicfg = require 'inicfg'
local new = imgui.new

local cfg = inicfg.load({ settings = { accent_r = 0.20, accent_g = 0.48, accent_b = 0.82 } }, 'GwarnV1.ini')
local json = require 'dkjson'
local SCRIPT_VERSION = '1.2.3'
local accent = new.float[3](cfg.settings.accent_r, cfg.settings.accent_g, cfg.settings.accent_b)
local window = new.bool(false)
local idWindow = new.bool(false)
local settingsPage = new.bool(false)
local searchInput = new.char[256]()
local idInput = new.char[16]()
local idInputFocus = false
local activeOrg = 1
local chosenRule = nil
local chosenOrg = 1
local articleWindow = new.bool(false)
local articleWindowFocus = false
local manageMode = new.bool(false)
local editorOrg = new.int(0)
local manageOrg = new.int(0)
local editorNumber = new.char[64]()
local editorText = new.char[4096]()
local editorMode = 'add'
local editingOrg = nil
local editingIndex = nil
local manageHoverRow = nil
local themeId = tonumber(cfg.settings.theme_id) or 3

local organizations = {
    { name = "ЕУМЮ (полиция)", code = "ЕУМЮ", source = "https://forum.arizona-rp.com/threads/7672587/", note = "", updated_at = '2026-11-14', rules = {} },
    { name = "ЕУП (Правительство)", code = "ЕУП", source = "https://forum.arizona-rp.com/threads/6598859/", note = "", updated_at = '2026-11-14', rules = {} },
    { name = "УАП (Адвокатская палата)", code = "УАП", source = "https://forum.arizona-rp.com/threads/9859188/", note = "", updated_at = '2026-11-14', rules = {} },
    { name = "ЕУМО (Министерство обороны)", code = "ЕУМО", source = "https://forum.arizona-rp.com/threads/10032413/", note = "В опубликованном уставе МО нет нумерации пунктов. Скрипт присвоил внутренние номера по главам и порядку пунктов.", updated_at = '2026-11-14', rules = {} },
    { name = "ЕУМУ — Центр лицензирования", code = "ЕУМУ", source = "https://forum.arizona-rp.com/threads/11500410/", note = "", updated_at = '2026-11-14', rules = {} },
    { name = "ЕУМУ — СМИ", code = "ЕУМУ", source = "https://forum.arizona-rp.com/threads/11500410/", note = "", updated_at = '2026-11-14', rules = {} },
    { name = "ЕУМУ — Здравоохранение", code = "ЕУМУ", source = "https://forum.arizona-rp.com/threads/11500410/", note = "", updated_at = '2026-11-14', rules = {} }
}

local scriptPath = thisScript().path
local rulesPath = scriptPath:gsub('GwarnV1%.lua$', 'rules.json')
local customRulesPath = scriptPath:gsub('GwarnV1%.lua$', 'GwarnV1_custom.json')
local rulesUrl = 'https://raw.githubusercontent.com/ellisharrisyuma-alt/Gwarn1/main/rules.json'
local versionUrl = 'https://raw.githubusercontent.com/ellisharrisyuma-alt/Gwarn1/main/version.json'
local canonicalScriptUrl = 'https://raw.githubusercontent.com/ellisharrisyuma-alt/Gwarn1/main/GwarnV1.lua'
local REMOTE_UPDATES_ENABLED = true
local versionTempPath = rulesPath .. '.version.download'
local scriptTempPath = scriptPath .. '.update'
local scriptBackupPath = scriptPath .. '.backup'
local scriptUpdateStatus = REMOTE_UPDATES_ENABLED and ('Текущая версия: ' .. SCRIPT_VERSION) or 'Проверка GitHub приостановлена до публикации файлов'
local scriptUpdateInProgress = false
local scriptRequestToken = 0
local currentRulesEditedAt = ''
local temporaryRulesPath = rulesPath .. '.download'
local organizationNames = {}
local organizationItems = '\0\0'
local rulesStatus = 'Загрузка локальной базы...'
local rulesDownloadInProgress = false
local rulesRequestToken = 0
local currentRulesVersion = ''
local baseOrganizations = {}
local dlstatus = require('moonloader').download_status

local function rebuildOrganizationItems()
    organizationNames = {}
    for i, org in ipairs(organizations) do organizationNames[i] = org.name end
    organizationItems = table.concat(organizationNames, '\0') .. '\0\0'
end

rebuildOrganizationItems()

local themePresets = {
    { id = 1, name = 'Фиолетовая', color = { 0.41, 0.19, 0.63 } },
    { id = 2, name = 'Светло-тёмная', color = { 0.46, 0.46, 0.46 } },
    { id = 3, name = 'Синяя', color = { 0.20, 0.48, 0.82 } }
}

local function applyTheme()
    local style = imgui.GetStyle()
    if not style then return end
    if themeId == 2 then
        style.WindowPadding = imgui.ImVec2(9, 5)
        style.WindowRounding = 10
        style.ChildRounding = 10
        style.FramePadding = imgui.ImVec2(5, 3)
        style.FrameRounding = 6
        style.ItemSpacing = imgui.ImVec2(9, 3)
        style.ItemInnerSpacing = imgui.ImVec2(9, 3)
        style.IndentSpacing = 21
        style.ScrollbarSize = 6
        style.ScrollbarRounding = 13
        style.GrabMinSize = 17
        style.GrabRounding = 16
        style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
        style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)
    else
        style.WindowRounding = 2
        style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
        style.ChildRounding = 2
        style.FrameRounding = 3
        style.ItemSpacing = imgui.ImVec2(5, 4)
        style.ScrollbarSize = 13
        style.ScrollbarRounding = 0
        style.GrabMinSize = 8
        style.GrabRounding = 1
        style.WindowPadding = imgui.ImVec2(4, 4)
        style.FramePadding = imgui.ImVec2(3.5, 3.5)
        style.ButtonTextAlign = imgui.ImVec2(0, 0.5)
    end

    local primary = { accent[0], accent[1], accent[2] }
    local light = themeId == 2
    local darkBg = light and { 0, 0, 0, 1 } or { 0.14, 0.12, 0.16, 1 }
    local panel = light and { 0.20, 0.20, 0.20, 1 } or { 0.30, 0.20, 0.39, 1 }
    local frame = light and { 1, 1, 1, 0.28 } or { 0.30, 0.20, 0.39, 1 }
    local textColor = light and { 0.90, 0.90, 0.90, 1 } or { 0.94, 0.92, 0.96, 1 }
    local accentColor = { primary[1], primary[2], primary[3], 1 }
    local accentSoft = { primary[1], primary[2], primary[3], 0.44 }
    local accentHover = {
        math.min(primary[1] + 0.12, 1),
        math.min(primary[2] + 0.12, 1),
        math.min(primary[3] + 0.12, 1), 0.86
    }
    local accentActive = {
        math.min(primary[1] + 0.23, 1),
        math.min(primary[2] + 0.18, 1),
        math.min(primary[3] + 0.31, 1), 1
    }
    local border = light and { 0.82, 0.77, 0.78, 1 } or { 0.89, 0.85, 0.92, 0.30 }
    local colors = {
        Text = textColor,
        TextDisabled = light and { 1, 1, 1, 1 } or { 0.55, 0.53, 0.59, 1 },
        WindowBg = darkBg,
        ChildBg = light and darkBg or { 0.30, 0.20, 0.39, 0 },
        PopupBg = light and { 0, 0, 0, 1 } or { 0.05, 0.05, 0.10, 0.90 },
        Border = border,
        BorderShadow = light and { 0.35, 0.35, 0.35, 0.66 } or { 0, 0, 0, 0 },
        FrameBg = frame,
        FrameBgHovered = light and { 0.68, 0.68, 0.68, 0.67 } or accentHover,
        FrameBgActive = light and { 0.79, 0.73, 0.73, 0.62 } or accentColor,
        TitleBg = light and darkBg or { primary[1], primary[2], primary[3], 0.45 },
        TitleBgActive = light and { 0.46, 0.46, 0.46, 1 } or { primary[1], primary[2], primary[3], 0.78 },
        TitleBgCollapsed = light and darkBg or { primary[1], primary[2], primary[3], 0.35 },
        MenuBarBg = light and { 0, 0, 0, 0.80 } or panel,
        ScrollbarBg = light and { 0, 0, 0, 0.60 } or panel,
        ScrollbarGrab = light and { 1, 1, 1, 0.87 } or { primary[1], primary[2], primary[3], 0.31 },
        ScrollbarGrabHovered = light and { 1, 1, 1, 0.79 } or accentHover,
        ScrollbarGrabActive = light and { 0.80, 0.50, 0.50, 0.40 } or accentColor,
        CheckMark = light and { 0.99, 0.99, 0.99, 0.90 } or { 0.75, 0.68, 1, 1 },
        SliderGrab = light and { 1, 1, 1, 0.42 } or accentSoft,
        SliderGrabActive = light and { 0.76, 0.76, 0.76, 1 } or accentColor,
        Button = light and { 0.51, 0.51, 0.51, 0.60 } or accentSoft,
        ButtonHovered = light and { 0.68, 0.68, 0.68, 1 } or accentHover,
        ButtonActive = light and { 0.67, 0.67, 0.67, 1 } or accentActive,
        Header = light and { 0.72, 0.72, 0.72, 0.54 } or { primary[1], primary[2], primary[3], 0.76 },
        HeaderHovered = light and { 0.92, 0.92, 0.95, 0.77 } or accentHover,
        HeaderActive = light and { 0.82, 0.82, 0.82, 0.80 } or accentColor,
        Separator = light and { 0.73, 0.73, 0.73, 1 } or border,
        SeparatorHovered = light and { 0.81, 0.81, 0.81, 1 } or accentHover,
        SeparatorActive = light and { 0.74, 0.74, 0.74, 1 } or accentColor,
        ResizeGrip = light and { 0.80, 0.80, 0.80, 0.30 } or accentSoft,
        ResizeGripHovered = light and { 0.95, 0.95, 0.95, 0.60 } or accentHover,
        ResizeGripActive = light and { 1, 1, 1, 0.90 } or accentColor,
        Tab = light and { 0.40, 0.40, 0.40, 0.86 } or accentSoft,
        TabHovered = light and { 0.68, 0.68, 0.68, 0.80 } or accentHover,
        TabActive = light and { 0.48, 0.48, 0.48, 1 } or accentColor,
        TabUnfocused = light and { 0.30, 0.30, 0.30, 0.97 } or { panel[1], panel[2], panel[3], 1 },
        TabUnfocusedActive = light and { 0.40, 0.40, 0.40, 1 } or accentSoft,
        PlotLines = textColor,
        PlotLinesHovered = accentColor,
        PlotHistogram = textColor,
        PlotHistogramHovered = accentColor,
        TextSelectedBg = light and { 1, 1, 1, 0.35 } or { primary[1], primary[2], primary[3], 0.43 },
        DragDropTarget = accentColor,
        NavHighlight = accentColor,
        NavWindowingHighlight = textColor,
        NavWindowingDimBg = { 0.20, 0.20, 0.20, 0.35 },
        ModalWindowDimBg = light and { 0.88, 0.88, 0.88, 0.35 } or { 0.20, 0.20, 0.20, 0.35 }
    }
    for name, value in pairs(colors) do
        local index = imgui.Col[name]
        if index ~= nil then style.Colors[index] = imgui.ImVec4(value[1], value[2], value[3], value[4]) end
    end
end

local function cloneRules(rules)
    local copy = {}
    for _, rule in ipairs(rules or {}) do
        copy[#copy + 1] = { number = tostring(rule.number), text = tostring(rule.text) }
    end
    return copy
end

local function snapshotBaseOrganizations()
    baseOrganizations = {}
    for i, org in ipairs(organizations) do
        baseOrganizations[i] = {
            name = org.name, code = org.code, source = org.source, note = org.note,
            updated_at = org.updated_at or '', rules = cloneRules(org.rules)
        }
    end
end

local function decodeRulesDocument(raw)
    local ok, document = pcall(json.decode, raw)
    if not ok or type(document) ~= 'table' or tonumber(document.schema_version) ~= 1
        or type(document.organizations) ~= 'table' then return nil end

    local loaded = {}
    for _, item in ipairs(document.organizations) do
        if type(item) ~= 'table' or type(item.name) ~= 'string' or type(item.code) ~= 'string'
            or type(item.rules) ~= 'table' then return nil end
        local org = {
            name = item.name, code = item.code,
            source = type(item.source) == 'string' and item.source or '',
            note = type(item.note) == 'string' and item.note or '',
            updated_at = type(item.updated_at) == 'string' and item.updated_at or '', rules = {}
        }
        for _, rule in ipairs(item.rules) do
            if type(rule) ~= 'table' or type(rule.number) ~= 'string' or type(rule.text) ~= 'string' then
                return nil
            end
            org.rules[#org.rules + 1] = { number = rule.number, text = rule.text }
        end
        loaded[#loaded + 1] = org
    end
    if #loaded == 0 then return nil end
    return loaded, tostring(document.version or ''), tostring(document.updated_at or '')
end

local function upsertRule(org, rule)
    for _, current in ipairs(org.rules) do
        if current.number == rule.number then
            current.text = rule.text
            return
        end
    end
    org.rules[#org.rules + 1] = { number = rule.number, text = rule.text }
end

local function loadCustomRules()
    local file = io.open(customRulesPath, 'rb')
    if not file then return end
    local raw = file:read('*a')
    file:close()
    local ok, stored = pcall(json.decode, raw)
    if not ok or type(stored) ~= 'table' or type(stored.sections) ~= 'table' then return end

    for _, org in ipairs(organizations) do
        local patch = stored.sections[org.name]
        if type(patch) == 'table' then
            for _, number in ipairs(patch.removed or {}) do
                for i = #org.rules, 1, -1 do
                    if org.rules[i].number == number then table.remove(org.rules, i) end
                end
            end
            for _, rule in ipairs(patch.edited or {}) do
                if type(rule) == 'table' and type(rule.number) == 'string' and type(rule.text) == 'string' then
                    upsertRule(org, rule)
                end
            end
            for _, rule in ipairs(patch.added or {}) do
                if type(rule) == 'table' and type(rule.number) == 'string' and type(rule.text) == 'string' then
                    upsertRule(org, rule)
                end
            end
        end
    end
end

local function activateRulesDocument(loaded, version, updatedAt)
    organizations = loaded
    currentRulesVersion = version or ''
    currentRulesEditedAt = updatedAt or ''
    snapshotBaseOrganizations()
    loadCustomRules()
    rebuildOrganizationItems()
    activeOrg = math.max(1, math.min(activeOrg, #organizations))
    manageOrg[0] = math.max(0, math.min(manageOrg[0], #organizations - 1))
    editorOrg[0] = math.max(0, math.min(editorOrg[0], #organizations - 1))
end

local function applyRulesText(raw)
    local loaded, version, updatedAt = decodeRulesDocument(raw)
    if not loaded then return false end
    activateRulesDocument(loaded, version, updatedAt)
    return true
end

local function loadCachedRules()
    local file = io.open(rulesPath, 'rb')
    if file then
        local raw = file:read('*a')
        file:close()
        if applyRulesText(raw) then
            rulesStatus = currentRulesEditedAt ~= '' and ('Локальная база от ' .. currentRulesEditedAt) or 'Локальная база загружена'
            return true
        end
        rulesStatus = 'Локальный JSON повреждён; будет загружена копия с GitHub'
    else
        rulesStatus = 'Локальная база не найдена; ожидается загрузка с GitHub'
    end
    snapshotBaseOrganizations()
    loadCustomRules()
    rebuildOrganizationItems()
    return false
end

local function saveRuleStore()
    local sectionsPatch = {}
    for orgIndex, org in ipairs(organizations) do
        local base = baseOrganizations[orgIndex] or { rules = {} }
        local baseByNumber, currentByNumber = {}, {}
        for _, rule in ipairs(base.rules or {}) do baseByNumber[rule.number] = rule end
        for _, rule in ipairs(org.rules) do currentByNumber[rule.number] = rule end

        local added, edited, removed = {}, {}, {}
        for _, rule in ipairs(base.rules or {}) do
            local current = currentByNumber[rule.number]
            if not current then
                removed[#removed + 1] = rule.number
            elseif current.text ~= rule.text then
                edited[#edited + 1] = { number = current.number, text = current.text }
            end
        end
        for _, rule in ipairs(org.rules) do
            if not baseByNumber[rule.number] then
                added[#added + 1] = { number = rule.number, text = rule.text }
            end
        end
        if #added > 0 or #edited > 0 or #removed > 0 then
            sectionsPatch[org.name] = { added = added, edited = edited, removed = removed }
        end
    end

    local ok, encoded = pcall(json.encode, { schema_version = 1, sections = sectionsPatch })
    if not ok or type(encoded) ~= 'string' then return false end
    local file = io.open(customRulesPath, 'wb')
    if not file then return false end
    local wrote = file:write(encoded)
    file:close()
    return wrote ~= nil
end

local function checkForRulesUpdate(announce)
    if not REMOTE_UPDATES_ENABLED then
        rulesStatus = 'Проверка GitHub приостановлена до публикации файлов'
        if announce then sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} Проверка уставов возобновится после публикации файлов на GitHub.'), -1) end
        return
    end
    if rulesDownloadInProgress then
        if announce then sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} Проверка уставов уже выполняется.'), -1) end
        return
    end
    if type(downloadUrlToFile) ~= 'function' or not dlstatus then
        rulesStatus = 'Загрузка недоступна: проверьте MoonLoader'
        if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Не удалось запустить загрузчик MoonLoader.'), -1) end
        return
    end

    os.remove(temporaryRulesPath)
    rulesDownloadInProgress = true
    rulesRequestToken = rulesRequestToken + 1
    local requestToken = rulesRequestToken
    rulesStatus = 'Сверяю уставы с GitHub...'

    local rulesDataReceived = false
    local ok = pcall(downloadUrlToFile, rulesUrl, temporaryRulesPath, function(_, status)
        if requestToken ~= rulesRequestToken then return false end
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            if rulesDataReceived then return true end
            rulesDownloadInProgress = false
            os.remove(temporaryRulesPath)
            rulesStatus = 'Не удалось скачать rules.json с GitHub'
            if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Не удалось скачать rules.json с GitHub.'), -1) end
            return false
        end
        if status ~= dlstatus.STATUS_ENDDOWNLOADDATA then return true end
        rulesDataReceived = true

        rulesDownloadInProgress = false
        local file = io.open(temporaryRulesPath, 'rb')
        if not file then
            rulesStatus = 'Не удалось прочитать rules.json с GitHub'
            if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Не удалось прочитать rules.json.'), -1) end
            return
        end
        local raw = file:read('*a')
        file:close()
        local loaded, version, updatedAt = decodeRulesDocument(raw)
        if not loaded then
            rulesStatus = 'На GitHub найден некорректный rules.json'
            os.remove(temporaryRulesPath)
            if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} JSON уставов не прошёл проверку.'), -1) end
            return
        end

        local previousRaw = nil
        local previous = io.open(rulesPath, 'rb')
        if previous then previousRaw = previous:read('*a'); previous:close() end
        local alreadyCurrent = previousRaw == raw
        local cache = io.open(rulesPath, 'wb')
        if not cache then
            rulesStatus = 'Не удалось сохранить локальную копию rules.json'
            os.remove(temporaryRulesPath)
            if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Не удалось сохранить локальную базу.'), -1) end
            return
        end
        cache:write(raw)
        cache:close()
        os.remove(temporaryRulesPath)
        activateRulesDocument(loaded, version, updatedAt)
        local dateText = currentRulesEditedAt ~= '' and currentRulesEditedAt or 'дата не указана'
        if alreadyCurrent then
            rulesStatus = 'Уставы актуальны; база на GitHub от ' .. dateText
            if announce then sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} Уставы актуальны. База на GitHub от ' .. dateText .. '.'), -1) end
        else
            rulesStatus = 'Уставы обновлены с GitHub; база от ' .. dateText
            if announce then sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} Получены обновлённые уставы с GitHub. База от ' .. dateText .. '.'), -1) end
        end
    end)

    if not ok then
        rulesDownloadInProgress = false
        rulesStatus = 'Не удалось начать загрузку уставов'
        if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Не удалось начать проверку уставов.'), -1) end
        return
    end

    lua_thread.create(function()
        wait(30000)
        if rulesDownloadInProgress and rulesRequestToken == requestToken then
            rulesRequestToken = rulesRequestToken + 1
            rulesDownloadInProgress = false
            rulesStatus = 'GitHub не ответил за 30 секунд; сохранена локальная база'
            os.remove(temporaryRulesPath)
            if announce then sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} GitHub не ответил, оставлена локальная база.'), -1) end
        end
    end)
end

local function versionIsNewer(candidate, current)
    if type(candidate) ~= 'string' or not candidate:match('^%d+%.%d+%.%d+$') then return false end
    local remoteParts, currentParts = {}, {}
    for value in candidate:gmatch('%d+') do remoteParts[#remoteParts + 1] = tonumber(value) end
    for value in tostring(current):gmatch('%d+') do currentParts[#currentParts + 1] = tonumber(value) end
    for i = 1, 3 do
        local remoteValue, currentValue = remoteParts[i] or 0, currentParts[i] or 0
        if remoteValue > currentValue then return true end
        if remoteValue < currentValue then return false end
    end
    return false
end

local function checkForScriptUpdate(announce)
    if not REMOTE_UPDATES_ENABLED then
        scriptUpdateStatus = 'Проверка GitHub приостановлена до публикации файлов'
        if announce then sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} Проверка обновления LUA возобновится после публикации файлов на GitHub.'), -1) end
        return
    end
    if scriptUpdateInProgress then
        if announce then sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} Проверка обновления LUA уже выполняется.'), -1) end
        return
    end
    if type(downloadUrlToFile) ~= 'function' or not dlstatus then
        scriptUpdateStatus = 'Загрузка LUA недоступна: проверьте MoonLoader'
        if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Не удалось запустить обновление LUA.'), -1) end
        return
    end

    os.remove(versionTempPath)
    os.remove(scriptTempPath)
    scriptUpdateInProgress = true
    scriptRequestToken = scriptRequestToken + 1
    local requestToken = scriptRequestToken
    scriptUpdateStatus = 'Проверяю версию LUA на GitHub...'

    local function failUpdate(message)
        if requestToken ~= scriptRequestToken then return end
        scriptUpdateInProgress = false
        scriptUpdateStatus = message
        os.remove(versionTempPath)
        os.remove(scriptTempPath)
        if announce then sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} ' .. message), -1) end
    end

    local versionDataReceived = false
    local ok = pcall(downloadUrlToFile, versionUrl, versionTempPath, function(_, status)
        if requestToken ~= scriptRequestToken then return false end
        if status == dlstatus.STATUSEX_ENDDOWNLOAD then
            if versionDataReceived then return true end
            failUpdate('Не удалось скачать version.json с GitHub'); return false
        end
        if status ~= dlstatus.STATUS_ENDDOWNLOADDATA then return true end
        versionDataReceived = true

        local manifestFile = io.open(versionTempPath, 'rb')
        if not manifestFile then failUpdate('Не удалось прочитать version.json'); return end
        local manifestRaw = manifestFile:read('*a')
        manifestFile:close()
        local decoded, manifest = pcall(json.decode, manifestRaw)
        if not decoded or type(manifest) ~= 'table' or tonumber(manifest.schema_version) ~= 1 then
            failUpdate('version.json на GitHub повреждён')
            return
        end

        local remoteVersion = tostring(manifest.script_version or '')
        if not remoteVersion:match('^%d+%.%d+%.%d+$') or manifest.script_url ~= canonicalScriptUrl then
            failUpdate('В version.json неверно указана версия или ссылка LUA')
            return
        end
        if not versionIsNewer(remoteVersion, SCRIPT_VERSION) then
            scriptUpdateInProgress = false
            scriptUpdateStatus = 'LUA актуален: v' .. SCRIPT_VERSION
            os.remove(versionTempPath)
            if announce then sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} Скрипт LUA актуален: v' .. SCRIPT_VERSION .. '.'), -1) end
            return
        end

        scriptUpdateStatus = 'Найдена LUA v' .. remoteVersion .. '; скачиваю...'
        lua_thread.create(function()
            wait(250)
            if requestToken ~= scriptRequestToken then return end
            local scriptDataReceived = false
            local downloadOk = pcall(downloadUrlToFile, canonicalScriptUrl, scriptTempPath, function(_, scriptStatus)
                if requestToken ~= scriptRequestToken then return false end
                if scriptStatus == dlstatus.STATUSEX_ENDDOWNLOAD then
                    if scriptDataReceived then return true end
                    failUpdate('Не удалось скачать новую версию LUA'); return false
                end
                if scriptStatus ~= dlstatus.STATUS_ENDDOWNLOADDATA then return true end
                scriptDataReceived = true

                local scriptFile = io.open(scriptTempPath, 'rb')
                if not scriptFile then failUpdate('Не удалось прочитать загруженный LUA-файл'); return end
                local downloaded = scriptFile:read('*a')
                scriptFile:close()
                local expectedHeader = "script_version('" .. remoteVersion .. "')"
                local expectedHeaderDouble = 'script_version("' .. remoteVersion .. '")'
                if #downloaded > 524288 or (not downloaded:find(expectedHeader, 1, true) and not downloaded:find(expectedHeaderDouble, 1, true)) then
                    failUpdate('Загруженный LUA-файл не прошёл проверку версии')
                    return
                end

                os.remove(scriptBackupPath)
                local movedOld = os.rename(scriptPath, scriptBackupPath)
                if not movedOld then
                    failUpdate('Не удалось создать резервную копию LUA-файла')
                    return
                end
                local movedNew = os.rename(scriptTempPath, scriptPath)
                if not movedNew then
                    os.rename(scriptBackupPath, scriptPath)
                    failUpdate('Не удалось установить новую версию LUA')
                    return
                end

                scriptUpdateInProgress = false
                scriptUpdateStatus = 'LUA v' .. remoteVersion .. ' установлена; перезагружаю скрипт'
                os.remove(versionTempPath)
                if announce then sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} Скрипт обновлён до v' .. remoteVersion .. ', выполняю перезагрузку.'), -1) end
                lua_thread.create(function()
                    wait(600)
                    thisScript():reload()
                end)
            end)
            if not downloadOk then failUpdate('Не удалось начать загрузку новой версии LUA') end
        end)
    end)

    if not ok then
        failUpdate('Не удалось начать проверку версии LUA')
        return
    end
    lua_thread.create(function()
        wait(30000)
        if scriptUpdateInProgress and scriptRequestToken == requestToken then
            scriptRequestToken = scriptRequestToken + 1
            scriptUpdateInProgress = false
            scriptUpdateStatus = 'GitHub не ответил за 30 секунд; текущая LUA сохранена'
            os.remove(versionTempPath)
            os.remove(scriptTempPath)
            if announce then sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} GitHub не ответил, текущая LUA сохранена.'), -1) end
        end
    end)
end

local function checkAllUpdates(announce)
    checkForRulesUpdate(announce)
    lua_thread.create(function()
        local waited = 0
        while rulesDownloadInProgress and waited < 31000 do
            wait(250)
            waited = waited + 250
        end
        if rulesDownloadInProgress then return end
        wait(500)
        checkForScriptUpdate(announce)
    end)
end

local function saveConfig()
    cfg.settings.accent_r = accent[0]
    cfg.settings.accent_g = accent[1]
    cfg.settings.accent_b = accent[2]
    cfg.settings.theme_id = themeId
    inicfg.save(cfg, 'GwarnV1.ini')
end

local function makeBuffer(size, value)
    local buffer = new.char[size]()
    if value and #value > 0 then ffi.copy(buffer, value, math.min(#value, size - 1)) end
    return buffer
end

local function openArticleEditor(mode, orgIndex, ruleIndex, rule)
    editorMode = mode
    editingOrg = orgIndex
    editingIndex = ruleIndex
    editorOrg[0] = (orgIndex or activeOrg) - 1
    editorNumber = makeBuffer(64, rule and rule.number or '')
    editorText = makeBuffer(4096, rule and rule.text or '')
    articleWindow[0] = true
    articleWindowFocus = true
end

local function openRule(rule)
    chosenRule = rule
    chosenOrg = activeOrg
    idInput = new.char[16]()
    idInputFocus = true
    idWindow[0] = true
end

local function matches(rule, query)
    if query == '' then return true end
    return (rule.number .. ' ' .. rule.text):find(query, 1, true) ~= nil
end

loadCachedRules()

function onWindowMessage(msg, wparam, lparam)
    if not window[0] then return end
    if wparam ~= 0x1B or (msg ~= 0x0100 and msg ~= 0x0101) then return end
    if isPauseMenuActive() or sampIsChatInputActive() or sampIsDialogActive() then return end

    consumeWindowMessage(true, false)
    if msg == 0x0101 then
        if idWindow[0] then
            idWindow[0] = false
        elseif articleWindow[0] then
            articleWindow[0] = false
        else
            window[0] = false
        end
    end
end
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    sampRegisterChatCommand('gw', function()
        window[0] = not window[0]
        if not window[0] then idWindow[0] = false; articleWindow[0] = false end
    end)
    sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} Загружен. Открыть справочник: /gw'), -1)
    if REMOTE_UPDATES_ENABLED then
        lua_thread.create(function()
            wait(2500)
            checkAllUpdates(false)
            while true do
                wait(21600000)
                checkAllUpdates(false)
            end
        end)
    end
    while true do wait(0) end
end

imgui.OnFrame(function() return window[0] end, function()
    applyTheme()
    local color = imgui.ImVec4(accent[0], accent[1], accent[2], 1.0)
    imgui.PushStyleColor(imgui.Col.TitleBgActive, color)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(accent[0], accent[1], accent[2], 0.72))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(math.min(accent[0] + 0.12, 1.0), math.min(accent[1] + 0.12, 1.0), math.min(accent[2] + 0.12, 1.0), 1.0))
    imgui.SetNextWindowSize(imgui.ImVec2(800, 600), imgui.Cond.FirstUseEver)
    if imgui.Begin('GwarnV1 | Справочник уставов', window) then
        if imgui.Button(settingsPage[0] and 'К уставам' or 'Настройки') then
            settingsPage[0] = not settingsPage[0]
            manageMode[0] = false
        end
        imgui.SameLine()
        imgui.Text('Официальные уставы штата Yuma')
        imgui.Separator()

        if settingsPage[0] then
            imgui.TextWrapped('Автор идеи: Ellis_Harris')
            imgui.Text('Цвет интерфейса')
            for i, preset in ipairs(themePresets) do
                if i > 1 then imgui.SameLine() end
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(preset.color[1], preset.color[2], preset.color[3], 0.82))
                if imgui.Button(preset.name, imgui.ImVec2(145, 0)) then
                    themeId = preset.id
                    accent[0], accent[1], accent[2] = preset.color[1], preset.color[2], preset.color[3]
                    saveConfig()
                end
                imgui.PopStyleColor()
            end
            if imgui.ColorEdit3('Акцентный цвет', accent) then saveConfig() end
            imgui.Separator()
            if imgui.Button('Проверить обновление LUA', imgui.ImVec2(235, 0)) then checkForScriptUpdate(true) end
            imgui.SameLine()
            if imgui.Button('Проверить уставы', imgui.ImVec2(190, 0)) then checkForRulesUpdate(true) end
            imgui.TextWrapped('LUA: ' .. scriptUpdateStatus)
            imgui.TextWrapped('Уставы: ' .. rulesStatus)


            if imgui.Button('Добавить устав', imgui.ImVec2(180, 0)) then
                openArticleEditor('add', activeOrg, nil, nil)
            end
            imgui.SameLine()
            if imgui.Button(manageMode[0] and 'Скрыть редактирование' or 'Редактировать устав', imgui.ImVec2(220, 0)) then
                manageMode[0] = not manageMode[0]
                manageHoverRow = nil
            end

            if manageMode[0] then
                imgui.Separator()
                imgui.Text('Выберите раздел:')
                if imgui.ComboStr('##manage_section', manageOrg, organizationItems, 8) then
                    manageHoverRow = nil
                end
                local orgIndex = manageOrg[0] + 1
                local org = organizations[orgIndex] or organizations[1]
                imgui.BeginChild('##manage_rules', imgui.ImVec2(0, -8), true)
                local contentWidth = imgui.GetContentRegionAvail().x
                imgui.Columns(2, '##manage_columns', true)
                imgui.SetColumnWidth(0, math.max(300, contentWidth - 90))
                for i, rule in ipairs(org.rules) do
                    imgui.TextWrapped(rule.number .. ' - ' .. rule.text)
                    imgui.NextColumn()
                    local action = nil
                    if imgui.SmallButton('\208\160\208\181\208\180.##rule_edit_' .. i) then action = 'edit' end
                    imgui.SameLine()
                    if imgui.SmallButton('X##rule_delete_' .. i) then action = 'delete' end
                    imgui.NextColumn()

                    if action == 'edit' then
                        openArticleEditor('edit', orgIndex, i, rule)
                        break
                    elseif action == 'delete' then
                        table.remove(org.rules, i)
                        saveRuleStore()
                        break
                    end
                end
                imgui.Columns(1)
                if #org.rules == 0 then imgui.Text('В этом разделе пока нет статей.') end
                imgui.EndChild()
            end
        else
            imgui.InputText('Поиск по выбранному уставу', searchInput, 256)
            local query = ffi.string(searchInput)
            for i, org in ipairs(organizations) do
                if i > 1 and (i - 1) % 3 ~= 0 then imgui.SameLine() end
                local selected = i == activeOrg
                if selected then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(accent[0], accent[1], accent[2], 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(math.min(accent[0] + 0.12, 1.0), math.min(accent[1] + 0.12, 1.0), math.min(accent[2] + 0.12, 1.0), 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(math.min(accent[0] + 0.20, 1.0), math.min(accent[1] + 0.20, 1.0), math.min(accent[2] + 0.20, 1.0), 1.0))
                end
                if imgui.Button(org.name) then activeOrg = i end
                if selected then imgui.PopStyleColor(3) end
            end
            local org = organizations[activeOrg]
            imgui.Separator()
            if org.note ~= '' then imgui.TextWrapped(org.note) end
            if org.updated_at and org.updated_at ~= '' then imgui.Text('Дата обновления базы: ' .. org.updated_at) end
            imgui.Text('Нажмите на статью, чтобы открыть меню наказания.')
            imgui.BeginChild('##rules', imgui.ImVec2(0, -8), true)
            local shown = 0
            for _, rule in ipairs(org.rules) do
                if matches(rule, query) then
                    shown = shown + 1
                    imgui.TextWrapped(rule.number .. ' — ' .. rule.text)
                    if imgui.IsItemClicked(0) then openRule(rule) end
                    imgui.Separator()
                end
            end
            if shown == 0 then imgui.TextWrapped('Ничего не найдено.') end
            imgui.EndChild()
        end
    end
    imgui.End()
    if not window[0] then idWindow[0] = false; articleWindow[0] = false end
    imgui.PopStyleColor(3)
end)
imgui.OnFrame(function() return window[0] and idWindow[0] end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(360, 142), imgui.Cond.Always)
    imgui.SetNextWindowFocus()
    if imgui.Begin('\208\146\208\178\208\181\208\180\208\184\209\130\208\181 ID', idWindow, imgui.WindowFlags.NoResize) then
        imgui.Text('\208\161\209\130\208\176\209\130\209\140\209\143: ' .. (chosenRule and chosenRule.number or '?'))
        imgui.PushItemWidth(-1)
        if idInputFocus then
            imgui.SetKeyboardFocusHere()
            idInputFocus = false
        end
        imgui.InputTextWithHint('##player_id', 'ID: 123', idInput, 16)
        imgui.PopItemWidth()
        imgui.Spacing()

        local buttonWidth = (imgui.GetContentRegionAvail().x - 8) / 2
        if imgui.Button('\208\158\209\130\208\188\208\181\208\189\208\176', imgui.ImVec2(buttonWidth, 30)) then idWindow[0] = false end
        imgui.SameLine()
        if imgui.Button('\208\146\209\139\208\180\208\176\209\130\209\140', imgui.ImVec2(buttonWidth, 30)) then
            local id = ffi.string(idInput)
            if id:match('^%d+$') and chosenRule then
                local command = '/gwarn ' .. id .. ' ' .. chosenRule.number .. ' ' .. organizations[chosenOrg].code
                sampSendChat(u8:decode(command))
                idWindow[0] = false
                window[0] = false
            else
                sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} \208\146\208\178\208\181\208\180\208\184\209\130\208\181 ID \209\134\208\184\209\132\209\128\208\176\208\188\208\184.'), -1)
            end
        end
    end
    imgui.End()
end)
imgui.OnFrame(function() return window[0] and articleWindow[0] end, function()
    imgui.SetNextWindowSize(imgui.ImVec2(520, 350), imgui.Cond.FirstUseEver)
    if articleWindowFocus then
        imgui.SetNextWindowFocus()
        articleWindowFocus = false
    end
    local title = editorMode == 'add' and 'Добавить устав' or 'Редактировать устав'
    if imgui.Begin(title, articleWindow, imgui.WindowFlags.NoResize) then
        if articleWindow[0] then
            imgui.Text('Раздел:')
            imgui.ComboStr('##editor_section', editorOrg, organizationItems, 8)
            imgui.InputText('Номер статьи', editorNumber, 64)
            imgui.Text('Что гласит статья:')
            imgui.InputTextMultiline('##article_text', editorText, 4096, imgui.ImVec2(0, 150))

            if imgui.Button(editorMode == 'add' and 'Добавить' or 'Сохранить', imgui.ImVec2(245, 0)) then
                local number = ffi.string(editorNumber):match('^%s*(.-)%s*$')
                local text = ffi.string(editorText):match('^%s*(.-)%s*$')
                if number == '' or not number:match('^%d+%.?%d*$') or number:sub(-1) == '.' or text == '' then
                    sampAddChatMessage(u8:decode('{FF6666}[GwarnV1]{FFFFFF} Укажите корректный номер и текст статьи.'), -1)
                else
                    local targetOrgIndex = editorOrg[0] + 1
                    local targetOrg = organizations[targetOrgIndex]
                    if editorMode == 'edit' and editingOrg and editingIndex then
                        local oldOrg = organizations[editingOrg]
                        local oldRule = oldOrg and oldOrg.rules[editingIndex]
                        if oldRule then
                            if editingOrg == targetOrgIndex then
                                oldRule.number, oldRule.text = number, text
                            else
                                table.remove(oldOrg.rules, editingIndex)
                                targetOrg.rules[#targetOrg.rules + 1] = { number = number, text = text }
                            end
                        end
                    else
                        targetOrg.rules[#targetOrg.rules + 1] = { number = number, text = text }
                    end
                    saveRuleStore()
                    activeOrg = targetOrgIndex
                    manageOrg[0] = targetOrgIndex - 1
                    articleWindow[0] = false
                    manageMode[0] = false
                    settingsPage[0] = false
                end
            end
            imgui.SameLine()
            if imgui.Button('Отмена', imgui.ImVec2(245, 0)) then articleWindow[0] = false end
            imgui.Text('Закрыть это меню можно крестиком или клавишей ESC.')
        end
    end
    imgui.End()
end)
