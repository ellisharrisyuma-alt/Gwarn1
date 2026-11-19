script_name('GwarnV1')
script_author('Ellis_Harris')
script_version('1.4.1')
script_description('Справочник уставов Arizona RP, штат Yuma')

require 'lib.moonloader'
local ffi = require 'ffi'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local imgui = require 'mimgui'
local inicfg = require 'inicfg'
local new = imgui.new

local defaults = {accent_r = 0.20, accent_g = 0.48, accent_b = 0.82, rp_emotes = true, background_transparency = 0.25, auto_investigation = false}
local okConfig, cfg = pcall(inicfg.load, {settings = defaults}, 'GwarnV1.ini')
if not okConfig or type(cfg) ~= 'table' or type(cfg.settings) ~= 'table' then cfg = {settings = defaults} end
local function bounded(value, fallback, maximum)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.max(0, math.min(maximum, value))
end
local json = require 'dkjson'
local SCRIPT_VERSION = '1.4.1'
local accent = new.float[3](bounded(cfg.settings.accent_r, 0.20, 1), bounded(cfg.settings.accent_g, 0.48, 1), bounded(cfg.settings.accent_b, 0.82, 1))
local backgroundTransparencyPercent = new.float(bounded(cfg.settings.background_transparency, 0.25, 0.75) * 100.0)
local rpEmotes = cfg.settings.rp_emotes
if rpEmotes == nil then rpEmotes = true end
if type(rpEmotes) == 'string' then rpEmotes = rpEmotes == 'true' or rpEmotes == '1' end
if type(rpEmotes) == 'number' then rpEmotes = rpEmotes ~= 0 end
local window = new.bool(false)
local idWindow = new.bool(false)
local page = 'rules'
local searchInput = new.char[256]()
local idInput = new.char[16]()
local idInputFocusFrames = 0
local idInputSession = 0
local activeOrg = 1
local chosenRule = nil
local chosenOrg
local articleWindow = new.bool(false)
local manageMode = new.bool(false)
local editorOrg = new.int(0)
local editorNumber = new.char[64]()
local editorText = new.char[4096]()
local editingOrg, editingRule
local ruleRevision = 0
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
local directory = scriptPath:match('^(.*[/\\])') or ''
local rulesPath = directory .. 'rules.json'
local customRulesPath = directory .. 'GwarnV1_custom.json'
local rulesUrl = 'https://raw.githubusercontent.com/ellisharrisyuma-alt/Gwarn1/main/rules.json'
local versionUrl = 'https://raw.githubusercontent.com/ellisharrisyuma-alt/Gwarn1/main/version.json'
local canonicalScriptUrl = 'https://raw.githubusercontent.com/ellisharrisyuma-alt/Gwarn1/main/GwarnV1.lua'
local scriptUpdateStatus = 'Версия ' .. SCRIPT_VERSION
local currentRulesEditedAt = ''
local organizationNames = {}
local organizationItems = '\0\0'
local rulesStatus = 'Загрузка локальной базы...'
local currentRulesVersion = ''
local baseOrganizations = {}

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
    local file = io.open(customRulesPath, 'rb') or io.open(customRulesPath .. '.previous', 'rb')
    if not file then return end
    local raw = file:read('*a')
    file:close()
    local ok, stored = pcall(json.decode, raw)
    if not ok or type(stored) ~= 'table' or type(stored.sections) ~= 'table' then return end

    for _, org in ipairs(organizations) do
        local patch = stored.sections[org.name]
        if type(patch) == 'table' then
            for _, number in ipairs(type(patch.removed) == 'table' and patch.removed or {}) do
                for i = #org.rules, 1, -1 do
                    if org.rules[i].number == number then table.remove(org.rules, i) end
                end
            end
            for _, rule in ipairs(type(patch.edited) == 'table' and patch.edited or {}) do
                if type(rule) == 'table' and type(rule.number) == 'string' and type(rule.text) == 'string' then
                    upsertRule(org, rule)
                end
            end
            for _, rule in ipairs(type(patch.added) == 'table' and patch.added or {}) do
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
    local replacement = customRulesPath .. '.tmp'
    local backup = customRulesPath .. '.previous'
    local file = io.open(replacement, 'wb')
    if not file then return false end
    local wrote = file:write(encoded)
    local closed = file:close()
    if not wrote or not closed then os.remove(replacement); return false end

    local existing = io.open(customRulesPath, 'rb')
    if existing then
        existing:close()
        os.remove(backup)
        if not os.rename(customRulesPath, backup) then os.remove(replacement); return false end
    end
    if not os.rename(replacement, customRulesPath) then
        if existing then os.rename(backup, customRulesPath) end
        os.remove(replacement)
        return false
    end
    if existing then os.remove(backup) end
    return true
end

-- Run Windows' HTTPS client without Lua callbacks. Only the main loop reads its result.
local startDownload, pollDownload, replaceFile
do
    local kernel, curlPath
    local function initialize()
        ffi.cdef[[
            typedef struct {
                uint32_t cb; uint16_t *reserved, *desktop, *title;
                uint32_t x, y, width, height, columns, rows, fill, flags;
                uint16_t show, reservedSize; uint8_t *reservedData;
                void *input, *output, *errorOutput;
            } GWARN_STARTUP;
            typedef struct { void *process, *thread; uint32_t processId, threadId; } GWARN_PROCESS;
            int __stdcall CreateProcessW(const uint16_t *, uint16_t *, void *, void *, int, uint32_t,
                void *, const uint16_t *, GWARN_STARTUP *, GWARN_PROCESS *);
            int __stdcall CloseHandle(void *);
            uint32_t __stdcall WaitForSingleObject(void *, uint32_t);
            int __stdcall GetExitCodeProcess(void *, uint32_t *);
            uint32_t __stdcall GetSystemDirectoryW(uint16_t *, uint32_t);
            int __stdcall MultiByteToWideChar(uint32_t, uint32_t, const char *, int, uint16_t *, int);
            int __stdcall MoveFileExW(const uint16_t *, const uint16_t *, uint32_t);
        ]]
        kernel = ffi.load('kernel32')
        curlPath = ffi.new('uint16_t[512]')
        local n = tonumber(kernel.GetSystemDirectoryW(curlPath, 512))
        local suffix = '\\curl.exe'
        assert(n > 0 and n+#suffix < 512)
        for i=1,#suffix do curlPath[n+i-1] = suffix:byte(i) end
    end

    local function wide(text)
        local n = kernel.MultiByteToWideChar(0, 0, text, -1, nil, 0)
        assert(n > 0)
        local result = ffi.new('uint16_t[?]', n)
        assert(kernel.MultiByteToWideChar(0, 0, text, -1, result, n) == n)
        return result
    end

    function startDownload(url, path, limit)
        local ok, process = pcall(function()
            if not kernel then initialize() end
            assert(not path:find('"',1,true))
            local command = ('curl.exe --disable --fail --silent --proto =https --connect-timeout 5 ' ..
                '--max-time 15 --max-filesize %d --output "%s" --url "%s"'):format(limit,path,url)
            local start = ffi.new('GWARN_STARTUP[1]')
            local result = ffi.new('GWARN_PROCESS[1]')
            start[0].cb = ffi.sizeof('GWARN_STARTUP')
            if kernel.CreateProcessW(curlPath,wide(command),nil,nil,0,0x08000000,nil,nil,start,result) == 0 then return end
            kernel.CloseHandle(result[0].thread)
            return ffi.gc(result[0].process, kernel.CloseHandle)
        end)
        if ok then return process end
    end

    function pollDownload(process)
        local result = kernel.WaitForSingleObject(process, 0)
        if result == 258 then return nil end -- still running
        local code = ffi.new('uint32_t[1]')
        local ok = result == 0 and kernel.GetExitCodeProcess(process, code) ~= 0
        kernel.CloseHandle(ffi.gc(process, nil))
        return ok and code[0] == 0
    end

    function replaceFile(source, destination)
        local ok, moved = pcall(function()
            if not kernel then initialize() end
            return kernel.MoveFileExW(wide(source),wide(destination),9) ~= 0
        end)
        return ok and moved
    end
end

local function versionIsNewer(candidate, current)
    local ra, rb, rc = candidate:match('^(%d+)%.(%d+)%.(%d+)$')
    if not ra then return false end
    local a, b, c = current:match('^(%d+)%.(%d+)%.(%d+)$')
    if tonumber(ra) ~= tonumber(a) then return tonumber(ra) > tonumber(a) end
    if tonumber(rb) ~= tonumber(b) then return tonumber(rb) > tonumber(b) end
    return tonumber(rc) > tonumber(c)
end

local updateJob
local queuedUpdates = {}
local stagedVersion
local function queueUpdate(kind, announce)
    if kind == 'version' and stagedVersion then return end
    if updateJob and (updateJob.kind == kind or (kind == 'version' and updateJob.kind == 'script')) then
        updateJob.announce = updateJob.announce or announce
        return
    end
    queuedUpdates[kind] = queuedUpdates[kind] or announce
    if kind == 'rules' then rulesStatus = 'Уставы: ожидается проверка'
    else scriptUpdateStatus = 'Ожидается проверка версии' end
end

local function updateStatus(kind, message, announce)
    if kind == 'rules' then rulesStatus = message else scriptUpdateStatus = message end
    if announce and isSampAvailable() and sampGetGamestate() == 3 then
        sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} '..message), -1)
    end
end

local function handleDownload(job, raw)
    if job.kind == 'rules' then
        local loaded, version, edited = decodeRulesDocument(raw)
        if not loaded then return 'Файл уставов не прошёл проверку' end
        if not replaceFile(job.path, rulesPath) then return 'Не удалось обновить локальные уставы' end
        activateRulesDocument(loaded, version, edited)
        return 'База уставов загружена. Дата: ' .. (currentRulesEditedAt ~= '' and currentRulesEditedAt or 'не указана')
    elseif job.kind == 'version' then
        local ok, manifest = pcall(json.decode, raw)
        if not ok or type(manifest) ~= 'table' or tonumber(manifest.schema_version) ~= 1
            or manifest.script_url ~= canonicalScriptUrl or type(manifest.script_version) ~= 'string'
            or not manifest.script_version:match('^%d+%.%d+%.%d+$') then
            return 'Файл версии не прошёл проверку'
        end
        if versionIsNewer(manifest.script_version, SCRIPT_VERSION) then
            stagedVersion = manifest.script_version
            queueUpdate('script', job.announce)
            return 'Загружаю версию ' .. stagedVersion
        end
        return 'Установлена актуальная версия ' .. SCRIPT_VERSION
    end

    if raw:byte(1) == 27 or not (raw:find("script_version('"..stagedVersion.."')",1,true)
        or raw:find('script_version("'..stagedVersion..'")',1,true)) or not loadstring(raw,'@GwarnV1.update') then
        stagedVersion = nil
        return 'Загруженный скрипт не прошёл проверку'
    end
    if not replaceFile(job.path, scriptPath) then
        stagedVersion = nil
        return 'Не удалось заменить файл скрипта'
    end
    return 'Версия ' .. stagedVersion .. ' установлена. Вступит в силу после перезапуска игры.'
end

local function tickUpdates()
    if updateJob then
        local completed = pollDownload(updateJob.process)
        if completed == nil then return end
        local job = updateJob
        updateJob = nil
        local message = 'GitHub недоступен. Попробуйте позже.'
        if completed then
            local file = io.open(job.path, 'rb')
            if file then
                local raw = file:read(job.limit+1)
                file:close()
                if raw and #raw <= job.limit then
                    local ok, status = pcall(handleDownload, job, raw)
                    message = ok and status or 'Ошибка обработки обновления'
                    if not ok then print('[GwarnV1] '..tostring(status)) end
                end
            end
        end
        if job.kind == 'script' and not message:find('установлена',1,true) then stagedVersion = nil end
        os.remove(job.path)
        updateStatus(job.kind, message, job.announce and job.kind ~= 'version' or
            (job.announce and not stagedVersion))
        return
    end

    local kind
    if queuedUpdates.script ~= nil then kind = 'script'
    elseif queuedUpdates.rules ~= nil then kind = 'rules'
    elseif queuedUpdates.version ~= nil then kind = 'version' end
    if not kind then return end
    local announce = queuedUpdates[kind]
    queuedUpdates[kind] = nil

    local path = scriptPath .. '.' .. kind .. '.part'
    local url = kind == 'rules' and rulesUrl or (kind == 'version' and versionUrl or canonicalScriptUrl)
    local limit = kind == 'version' and 8192 or 524288
    os.remove(path)
    local process = startDownload(url, path, limit)
    if process then
        updateJob = {kind=kind, process=process, path=path, limit=limit, announce=announce}
        updateStatus(kind, 'Проверяю GitHub…', false)
    else
        if kind == 'script' then stagedVersion = nil end
        updateStatus(kind, 'Не удалось запустить загрузку GitHub', announce)
    end
end

-- Investigation uses the same MoonLoader main loop as the handbook.
local investigation = { enabled = false }
do
    local events, callbackNames = nil, {}
    local clock, errorLog = 0, nil
    local view, pending, finished, retry, lastActivity
    local controls = {
        evidence = {207.4, 275.8, 'LD_SPAC:white'},
        date = {207.4, 296.0, 'LD_SPAC:white'},
        weapon = {207.4, 317.8, 'LD_SPAC:white'},
        fill = {217.4, 411.9, 'particle:lamp_shad_64'},
        track = {353.1, 411.9, 'particle:lamp_shad_64'},
        close = {453.1, 135.9, 'LD_BEAT:chit'}
    }
    local fields = {
        date = {title = 'Дата и время убийства', label = 'Дата и время'},
        weapon = {title = 'Орудие убийства', label = 'Орудие убийства'}
    }
    local responseCount, paused, nextClick, connected, sentForm
    local function reset()
        view = {buttons = {}, marks = {}}
        pending, finished, retry, lastActivity = nil, false, {}, nil
        responseCount, paused, nextClick, sentForm = {}, false, 0, false
    end
    reset()

    local function report(s)
        print('[Assistant] ' .. s)
    end
    local function stopOnError(err)
        investigation.enabled = false
        reset()
        investigation.issue = 'Авторасследование остановлено. Подробности в moonloader.log.'
        errorLog = tostring(err)
    end
    local function on(name, handler)
        callbackNames[#callbackNames+1] = name
        events[name] = function(...)
            local ok, result = pcall(handler, ...)
            if not ok then stopOnError(result); return end
            return result
        end
    end
    local function clearId(id)
        for action, current in pairs(view.buttons) do
            if current == id then view.buttons[action] = nil end
        end
        for field, current in pairs(view.marks) do
            if current == id then view.marks[field] = nil end
        end
        if view.progressId == id then view.progressId, view.progress = nil, nil end
    end
    local function progress(s)
        return tonumber(tostring(s or ''):match('^%s*(%d+)%s*%%%s*$'))
    end
    local function shown(id, td)
        clearId(id) -- the server can reuse a visible ID
        if not td or type(td.position) ~= 'table' then return end
        local x, y = tonumber(td.position.x), tonumber(td.position.y)
        if not x or not y then return end
        local function near(cx, cy) return math.abs(x-cx) < 2 and math.abs(y-cy) < 2 end
        if tonumber(td.style) == 4 and (td.selectable == true or tonumber(td.selectable) == 1) then
            for action, spec in pairs(controls) do
                if td.text == spec[3] and near(spec[1], spec[2]) then
                    view.buttons[action] = id
                    nextClick = clock + 300
                    break
                end
            end
        elseif tonumber(td.style) == 1 then
            if near(288.4, 343.5) and progress(td.text) then
                view.progressId, view.progress = id, progress(td.text)
            elseif td.text and td.text:find('%S') then
                if near(252.9, 277.1) then view.marks.evidence = id
                elseif near(252.9, 297.3) then view.marks.date = id
                elseif near(252.9, 318.6) then view.marks.weapon = id end
            end
        end
    end
    local function hidden(id)
        if id == view.buttons.fill and lastActivity == 'fill' then
            finished, sentForm = true, true
        end
        clearId(id)
    end
    local function clicked(id)
        for action, button in pairs(view.buttons) do
            if button == id then
                if action == 'close' or action == 'track' then
                    finished, lastActivity = true, nil
                    pending = nil
                else
                    lastActivity = action
                    nextClick = clock + 2000
                end
                return
            end
        end
    end

    local function gameText(text)
        return (tostring(text or ''):gsub('{%x+}', ''):gsub('\r',''))
    end
    local function dialog(id, style, title, b1, b2, body)
        pending = nil -- any replacement invalidates the old dialog
        local name, button = gameText(title), gameText(b1)
        local text = gameText(body)
        local kind, answer
        if style == 0 and name == u8:decode('Расследование') and button == u8:decode('Да')
            and text:find(u8:decode('Начать расследовать данное место преступления'), 1, true) then
            reset()
            kind, answer = 'start', ''
        elseif style == 1 and button == u8:decode('Ввод') then
            for key, field in pairs(fields) do
                if name == u8:decode(field.title) then
                    kind = key
                    -- Keep the exact bytes sent by the game, including Cyrillic.
                    answer = ('\n'..text):match('\n%s*'..u8:decode(field.label)..'[ \t]*:[ \t]*([^\n]+)')
                    if answer then answer = answer:match('^%s*(.-)%s*$') end
                    if not answer or answer == '' or answer == u8:decode('Неизвестно') then return end
                    if key == 'weapon' and responseCount.weapon == 1 and
                        text:find(u8:decode('Укажите орудие убийства в точности'), 1, true) then
                        answer = u8:encode(answer)
                    end
                    break
                end
            end
        end
        if not kind or paused or finished then return end
        if (responseCount[kind] or 0) >= 2 then
            paused = true
            report('Повторный отказ при заполнении поля ' .. kind)
            return
        end
        pending = {id=id, kind=kind, value=answer, at=clock+120, visible=not investigation.enabled,
            title=title, body=body, button1=b1, button2=b2, style=style}
        if investigation.enabled then return false end
    end

    local function receivedAnswer(id, button)
        if pending and pending.id == id then
            if pending.kind == 'start' and button ~= 1 then finished = true end
            pending = nil
        end
        nextClick = clock + 1200
    end
    local function step()
        if not investigation.enabled or paused or finished then return end
        local now = clock
        if pending then
            local p = pending
            if now < p.at then return end
            pending = nil
            if p.visible then
                if not sampIsDialogActive() or sampGetCurrentDialogId() ~= p.id then return end
                if p.kind ~= 'start' then sampSetCurrentDialogEditboxText(p.value) end
                sampCloseCurrentDialogWithButton(1)
            else
                if sampIsDialogActive() then return end
                sampSendDialogResponse(p.id, 1, 0, p.value)
            end
            responseCount[p.kind] = (responseCount[p.kind] or 0) + 1
            nextClick = now + 1500
            return
        end

        local b, pct = view.buttons, view.progress
        -- All three fields belong to the same form. While it is hidden there is nothing to click.
        if now < nextClick or not (pct and b.evidence and b.date and b.weapon and b.fill)
            or sampIsDialogActive() then return end
        local action
        if pct >= 100 then action = 'fill'
        elseif view.marks.weapon then return -- wait for the final percentage update
        elseif view.marks.date or pct >= 57 then action = 'weapon'
        elseif view.marks.evidence or pct >= 35 then action = 'date'
        else action = 'evidence' end
        if (retry[action] or 0) >= 5 then
            if retry[action] == 5 then
                report('Нет подтверждения этапа ' .. action .. ', ожидаю изменения бланка')
                retry[action] = 6
            end
            return
        end
        retry[action] = (retry[action] or 0) + 1
        lastActivity, nextClick = action, now + 2000
        sampSendClickTextdraw(b[action])
    end
    local stageIndex = {evidence=1, date=2, weapon=3, fill=4}
    function investigation.status()
        if not investigation.enabled then return 0, 0, 'Авторасследование выключено' end
        if sentForm then return 100, 5, 'Бланк отправлен' end
        if finished then return 0, 0, 'Ожидание нового дела' end
        local percent = math.max(0, math.min(100, view.progress or 0))
        local stage = stageIndex[lastActivity] or 0
        if paused or (lastActivity and (retry[lastActivity] or 0) >= 6) then
            return percent, stage, 'Игра не подтвердила этап. Проверь бланк.'
        end
        if pending and pending.kind == 'start' then return 0, 0, 'Открываю бланк' end
        if pending then stage = stageIndex[pending.kind] or stage end
        if not view.progress and stage == 0 then return 0, 0, 'Ожидание нового дела' end
        if view.progress then
            local current = percent >= 100 and 4 or (percent >= 57 and 3 or (percent >= 35 and 2 or 1))
            stage = math.max(stage, current)
        end
        return percent, stage, 'Заполняю бланк'
    end
    local function attach()
        if not events then
            local ok, library = pcall(require, 'lib.samp.events')
            if not ok or type(library) ~= 'table' then
                investigation.issue = 'Не удалось подключить SAMP.Lua.'
                errorLog = tostring(library)
                return false
            end
            events = library
        end
        on('onShowTextDraw', shown)
        on('onTextDrawHide', hidden)
        on('onTextDrawSetString', function(id, value)
            if id == view.progressId then view.progress = progress(value) end
        end)
        on('onSendClickTextDraw', clicked)
        on('onShowDialog', dialog)
        on('onSendDialogResponse', receivedAnswer)
        on('onConnectionLost', reset)
        on('onConnectionClosed', reset)
        return true
    end
    local function detach()
        if events then
            for _, name in ipairs(callbackNames) do events[name] = nil end
        end
        callbackNames = {}
    end
    function investigation.setEnabled(value)
        if value and ((script and script.find and script.find('Rasledka'))
            or (doesFileExist and doesFileExist(directory .. 'Rasledka.lua'))) then
            investigation.issue = 'Отключите отдельный Rasledka.lua и перезагрузите скрипты.'
            return false
        end
        if value == investigation.enabled then return value end
        investigation.issue = nil
        if value then
            if not attach() then return false end
            clock = getGameTimer()
            if sampIsDialogActive() and type(sampGetDialogCaption) == 'function'
                and type(sampGetDialogText) == 'function' and type(sampGetCurrentDialogType) == 'function' then
                local ok, err = pcall(function()
                    local style = sampGetCurrentDialogType()
                    dialog(sampGetCurrentDialogId(), style, sampGetDialogCaption(),
                        u8:decode(style == 0 and 'Да' or 'Ввод'), '', sampGetDialogText())
                end)
                if not ok then errorLog = tostring(err) end
            end
        else
            detach()
            local dialog = pending
            reset()
            if dialog and not dialog.visible then pending = dialog end
        end
        investigation.enabled = value
        return value
    end
    function investigation.tick(now)
        clock = now
        if errorLog then
            report(errorLog)
            errorLog = nil
            if not investigation.enabled then detach() end
        end
        if not investigation.enabled and not (pending and not pending.visible) then return end
        if not isSampAvailable() or sampGetGamestate() ~= 3 then
            if connected or pending then reset() end
            connected = false
            return
        end
        connected = true
        if not investigation.enabled then
            -- A dialog already consumed by SAMP.Lua must become available to the player again.
            local p = pending
            p.visible = true
            if not sampIsDialogActive() then
                local ok, err = pcall(sampShowDialog, p.id, p.title, p.body, p.button1, p.button2, p.style)
                if not ok then stopOnError(err) end
            end
            return
        end
        local ok, err = pcall(step)
        if not ok then stopOnError(err) end
    end
end

local function saveConfig()
    cfg.settings.accent_r = accent[0]
    cfg.settings.accent_g = accent[1]
    cfg.settings.accent_b = accent[2]
    cfg.settings.theme_id = themeId
    cfg.settings.rp_emotes = rpEmotes
    cfg.settings.background_transparency = backgroundTransparencyPercent[0] / 100.0
    local ok, saved = pcall(inicfg.save, cfg, 'GwarnV1.ini')
    if not ok or saved == false then print('Не удалось сохранить GwarnV1.ini') end
end

local function wrappedText(text)
    imgui.PushTextWrapPos(0)
    imgui.TextUnformatted(text)
    imgui.PopTextWrapPos()
end

local function warningCommand(id)
    return '/gwarn ' .. id .. ' ' .. chosenRule.number .. ' ' .. chosenOrg.code
end

local warningQueue
local function submitWarning(id)
    local org = chosenOrg
    if not org or not chosenRule or warningQueue then return end

    local command = warningCommand(id)
    local emotes = rpEmotes
    local fractionTag = org.code
    idWindow[0] = false
    window[0] = false

    local messages = {}
    if emotes then
        messages[#messages + 1] = '/do КПК находится на поясном держателе.'
        messages[#messages + 1] = '/me берёт в руки свой КПК и включает его'
        messages[#messages + 1] = '/me открыв базу данных ' .. fractionTag .. ' переходит в раздел управление сотрудниками других организаций'
        messages[#messages + 1] = '/me открывает дело нужного сотрудника и вносит в него изменения'
        messages[#messages + 1] = '/do Изменения успешно сохранены.'
    end
    messages[#messages + 1] = command
    if emotes then
        messages[#messages + 1] = '/me выходит с базы данных ' .. fractionTag .. ' и выключив КПК убирает его на поясной держатель'
    end
    warningQueue = {messages=messages, index=1, nextAt=0}
end

local function tickWarnings(now, online)
    local queue = warningQueue
    if not queue then return end
    if not online then warningQueue = nil; return end
    if now < queue.nextAt then return end
    sampSendChat(u8:decode(queue.messages[queue.index]))
    queue.index, queue.nextAt = queue.index + 1, now + 1100
    if queue.index > #queue.messages then warningQueue = nil end
end

local function makeBuffer(size, value)
    local buffer = new.char[size]()
    if value and #value > 0 then ffi.copy(buffer, value, math.min(#value, size - 1)) end
    return buffer
end

local function openArticleEditor(orgIndex, rule)
    editingOrg, editingRule = organizations[orgIndex], rule
    editorOrg[0] = orgIndex - 1
    editorNumber = makeBuffer(64, rule and rule.number or '')
    editorText = makeBuffer(4096, rule and rule.text or '')
    articleWindow[0] = true
end

local function openRule(org, rule)
    chosenRule, chosenOrg = rule, org
    idInput = new.char[16]()
    idInputSession = idInputSession + 1
    idInputFocusFrames = 2
    idWindow[0] = true
end

local function findRule(org, rule)
    for _, currentOrg in ipairs(organizations) do
        if currentOrg == org then
            for i, current in ipairs(org.rules) do
                if current == rule then return i end
            end
            break
        end
    end
end

local function saveArticle()
    local number = ffi.string(editorNumber):match('^%s*(.-)%s*$')
    local description = ffi.string(editorText):match('^%s*(.-)%s*$')
    if not number:match('^%d[%d.]*$') or number:sub(-1) == '.' or number:find('..',1,true) then
        return 'Укажите номер статьи, например 1.4.1.'
    end
    if description == '' then return 'Введите текст статьи.' end
    local target = organizations[editorOrg[0]+1]
    if not target then return 'Выберите раздел.' end
    local position
    if editingRule then
        position = findRule(editingOrg, editingRule)
        if not position then return 'База уставов обновилась. Откройте статью ещё раз.' end
    end
    for _, rule in ipairs(target.rules) do
        if rule ~= editingRule and rule.number == number then return 'В этом разделе уже есть статья с таким номером.' end
    end
    local replacement = {number=number, text=description}
    if position and target == editingOrg then
        target.rules[position] = replacement
        if not saveRuleStore() then
            target.rules[position] = editingRule
            return 'Не удалось сохранить статью.'
        end
    else
        if position then table.remove(editingOrg.rules, position) end
        target.rules[#target.rules+1] = replacement
        if not saveRuleStore() then
            table.remove(target.rules)
            if position then table.insert(editingOrg.rules, position, editingRule) end
            return 'Не удалось сохранить статью.'
        end
    end
    ruleRevision = ruleRevision + 1
end

local function removeArticle(org, rule)
    local position = findRule(org, rule)
    if not position then return 'Статья уже изменилась. Откройте её ещё раз.' end
    table.remove(org.rules, position)
    if not saveRuleStore() then
        table.insert(org.rules, position, rule)
        return 'Не удалось сохранить изменения.'
    end
    ruleRevision = ruleRevision + 1
end

local closeExtraWindow

loadCachedRules()

function onWindowMessage(msg, wparam, lparam)
    if not window[0] then return end
    if idWindow[0] and (msg == 0x0100 or msg == 0x0101) and (wparam == 0x0D or wparam == 0x6C) then
        consumeWindowMessage(true, false)
        return
    end
    if wparam ~= 0x1B or (msg ~= 0x0100 and msg ~= 0x0101) then return end
    if isPauseMenuActive() or sampIsChatInputActive() or sampIsDialogActive() then return end

    consumeWindowMessage(true, false)
    if msg == 0x0101 then
        if idWindow[0] then
            idWindow[0] = false
        elseif articleWindow[0] then
            articleWindow[0] = false
        elseif not closeExtraWindow() then
            window[0] = false
        end
    end
end
local requestInvestigation
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end
    print('[GwarnV1] v' .. SCRIPT_VERSION .. ' ready')
    sampRegisterChatCommand('gw', function()
        window[0] = not window[0]
        if not window[0] then
            idWindow[0], articleWindow[0] = false, false
            closeExtraWindow()
        end
    end)
    sampAddChatMessage(u8:decode('{66B3FF}[GwarnV1]{FFFFFF} Загружен. Открыть справочник: /gw'), -1)
    local configured = cfg.settings.auto_investigation
    local restoreInvestigation = configured == true or configured == 1 or configured == '1' or configured == 'true'
    local connectedAt, nextCheckAt
    while true do
        wait(100)
        local now = getGameTimer()
        local online = isSampAvailable() and sampGetGamestate() == 3
        if online then connectedAt = connectedAt or now else connectedAt = nil end
        if online and requestInvestigation ~= nil then
            local enabled = investigation.setEnabled(requestInvestigation)
            print('[GwarnV1] Investigation enabled: ' .. tostring(enabled))
            cfg.settings.auto_investigation = enabled
            saveConfig()
            requestInvestigation, restoreInvestigation = nil, false
        elseif restoreInvestigation and connectedAt and now-connectedAt >= 2500 then
            local enabled = investigation.setEnabled(true)
            print('[GwarnV1] Restored investigation: ' .. tostring(enabled))
            restoreInvestigation = false
        end
        investigation.tick(now)
        tickWarnings(now, online)
        if connectedAt and now-connectedAt >= 15000 and (not nextCheckAt or now >= nextCheckAt) then
            nextCheckAt = now + 21600000
            queueUpdate('rules', false)
            queueUpdate('version', false)
        end
        tickUpdates()
    end
end

do
    local gap = 10
    local theme = {}
    local function accentColor(alpha)
        return imgui.ImVec4(accent[0], accent[1], accent[2], alpha or 1)
    end

    local function applyTheme()
        local opacity = 1 - backgroundTransparencyPercent[0] / 100
        local r, g, b = accent[0], accent[1], accent[2]
        if theme.id == themeId and theme.r == r and theme.g == g and theme.b == b and theme.opacity == opacity then return end
        theme.id, theme.r, theme.g, theme.b, theme.opacity = themeId, r, g, b, opacity
        local palettes = {
            [1] = {0.085, 0.063, 0.127}, -- violet
            [2] = {0.075, 0.079, 0.091}, -- graphite
            [3] = {0.048, 0.074, 0.122}  -- midnight blue
        }
        local p = palettes[themeId] or palettes[3]
        local red, green, blue = p[1], p[2], p[3]
        local function shade(n, alpha) return imgui.ImVec4(red+n, green+n, blue+n, alpha or 1) end
        local style = imgui.GetStyle()
        style.WindowPadding = imgui.ImVec2(16, 14)
        style.FramePadding = imgui.ImVec2(10, 7)
        style.ItemSpacing = imgui.ImVec2(gap, 8)
        style.ItemInnerSpacing = imgui.ImVec2(7, 5)
        style.WindowTitleAlign = imgui.ImVec2(0.04, 0.5)
        style.WindowRounding, style.ChildRounding, style.FrameRounding, style.PopupRounding = 13, 11, 8, 9
        style.WindowBorderSize, style.ChildBorderSize, style.FrameBorderSize, style.PopupBorderSize = 1, 1, 0, 1
        style.ScrollbarSize, style.ScrollbarRounding, style.GrabRounding = 9, 8, 7
        local colors = {
            Text = imgui.ImVec4(0.94, 0.96, 0.99, 1), TextDisabled = imgui.ImVec4(0.69, 0.73, 0.80, 1),
            WindowBg = shade(0, opacity), ChildBg = shade(0.016, opacity * 0.90),
            TitleBg = shade(0.025, 0.99), TitleBgActive = shade(0.057, 1), TitleBgCollapsed = shade(0.025, 0.99),
            PopupBg = shade(0.032, 1), Border = shade(0.17, 0.78), Separator = shade(0.15, 0.8),
            FrameBg = shade(0.072), FrameBgHovered = shade(0.112), FrameBgActive = shade(0.13),
            Button = shade(0.078), ButtonHovered = shade(0.125), ButtonActive = shade(0.161),
            Header = accentColor(0.26), HeaderHovered = accentColor(0.42), HeaderActive = accentColor(0.56),
            ScrollbarBg = shade(0, 0), ScrollbarGrab = shade(0.14, 0.8),
            ScrollbarGrabHovered = shade(0.21), ScrollbarGrabActive = shade(0.26),
            CheckMark = accentColor(), SliderGrab = accentColor(0.75), SliderGrabActive = accentColor(),
            ResizeGrip = accentColor(0.23), ResizeGripHovered = accentColor(0.65), ResizeGripActive = accentColor(),
            TextSelectedBg = accentColor(0.45), PlotHistogram = accentColor()
        }
        for name, color in pairs(colors) do style.Colors[imgui.Col[name]] = color end
        theme.card = imgui.U32(red+0.052, green+0.052, blue+0.068, 0.98)
        theme.cardHover = imgui.U32(red+0.09+r*0.07, green+0.09+g*0.07, blue+0.09+b*0.07, 1)
        theme.line = imgui.U32(red+0.17, green+0.17, blue+0.17, 0.95)
        theme.text = imgui.U32(0.92, 0.94, 0.98, 1)
        theme.secondary = imgui.U32(0.73, 0.77, 0.85, 1)
        theme.tag = imgui.U32(red+0.14+r*0.15, green+0.14+g*0.15, blue+0.14+b*0.15, 1)
        theme.borderActive = imgui.U32(r*0.7+0.28, g*0.7+0.28, b*0.7+0.28, 0.92)
    end

    local function availableWidth() return math.max(1, imgui.GetContentRegionAvail().x) end
    local function shadeText(text, color)
        imgui.PushStyleColor(imgui.Col.Text, color)
        wrappedText(text)
        imgui.PopStyleColor()
    end
    local function muted(text)
        shadeText(text, imgui.ImVec4(0.69, 0.73, 0.80, 1))
    end
    local function failure(text)
        shadeText(text, imgui.ImVec4(1, 0.57, 0.55, 1))
    end
    local function heading(text)
        imgui.SetWindowFontScale(1.40)
        wrappedText(text)
        imgui.SetWindowFontScale(1)
    end
    local function primaryButton(label, width, height, tone)
        imgui.PushStyleColor(imgui.Col.Button, tone or accentColor(0.57))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, tone or accentColor(0.78))
        imgui.PushStyleColor(imgui.Col.ButtonActive, tone or accentColor(0.96))
        local clicked = imgui.Button(label, imgui.ImVec2(width, height or 36))
        imgui.PopStyleColor(3)
        return clicked
    end

    local navigation = {{'rules','Уставы'}, {'assistant','Ассистент'}, {'settings','Настройки'}}
    local searchAll = new.bool(true)
    local searchFocus = false
    local resetScroll = false
    local searchIndex = {}
    local indexedOrganizations, indexedRevision
    local cachedQuery, cachedScope, cachedResults
    local editorError, warningError, actionError
    local deletion
    local deleteWindow = new.bool(false)
    local investigationAnimation = 0
    local animationReady = false

    local cyrillicUpper = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
    local cyrillicLower = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
    local caseMap = {['ё']='е'}
    for i = 1, #cyrillicUpper, 2 do
        local lower = cyrillicLower:sub(i, i+1)
        caseMap[cyrillicUpper:sub(i, i+1)] = lower == 'ё' and 'е' or lower
    end
    local function searchText(value)
        return (value:lower():gsub('[\208\209][\128-\191]', caseMap))
    end

    local function resultRows(rawQuery, scope)
        if indexedOrganizations ~= organizations or indexedRevision ~= ruleRevision then
            searchIndex = {}
            for orgIndex, org in ipairs(organizations) do
                local rows = {}
                for _, rule in ipairs(org.rules) do
                    rows[#rows+1] = {rule = rule, org = org, orgIndex = orgIndex,
                        text = searchText(rule.number .. ' ' .. rule.text .. ' ' .. org.name)}
                end
                searchIndex[orgIndex] = rows
            end
            indexedOrganizations, indexedRevision = organizations, ruleRevision
            cachedResults = nil
        end
        local query = searchText(rawQuery):match('^%s*(.-)%s*$')
        if cachedResults and cachedQuery == query and cachedScope == scope then return cachedResults end
        local terms, found = {}, {}
        for term in query:gmatch('%S+') do terms[#terms+1] = term end
        for orgIndex, rows in ipairs(searchIndex) do
            if scope == 0 or scope == orgIndex then
                for _, row in ipairs(rows) do
                    local matches = true
                    for _, term in ipairs(terms) do
                        if not row.text:find(term, 1, true) then matches = false; break end
                    end
                    if matches then found[#found+1] = row end
                end
            end
        end
        cachedQuery, cachedScope, cachedResults = query, scope, found
        return found
    end

    local function selectedOrg(index)
        if activeOrg ~= index then
            activeOrg = index
            resetScroll = true
        end
    end
    local function drawOrgSelector(width)
        if imgui.BeginChild('##organizations', imgui.ImVec2(width, 0), true) then
            muted('Разделы')
            for i, org in ipairs(organizations) do
                local w = availableWidth()
                local h = math.max(45, imgui.CalcTextSize(org.name, nil, false, math.max(1, w-25)).y+20)
                local clicked = imgui.InvisibleButton('##organization_'..i, imgui.ImVec2(w, h))
                local a, z = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                local draw = imgui.GetWindowDrawList()
                local selected = activeOrg == i
                if imgui.IsItemVisible() then
                    if selected or imgui.IsItemHovered() then
                        draw:AddRectFilled(a, z, selected and theme.tag or theme.cardHover, 8)
                    end
                    if selected then
                        draw:AddRect(a, z, theme.borderActive, 8)
                        draw:AddRectFilled(imgui.ImVec2(a.x+4,a.y+8), imgui.ImVec2(a.x+7,z.y-8), theme.borderActive, 2)
                    end
                    draw:AddTextFontPtr(imgui.GetFont(), imgui.GetFontSize(), imgui.ImVec2(a.x+13,a.y+10),
                        theme.text, org.name, nil, math.max(1, w-25))
                end
                if clicked then selectedOrg(i) end
            end
        end
        imgui.EndChild()
    end

    local function openEditor(orgIndex, rule)
        openArticleEditor(orgIndex, rule)
        editorError = nil
    end

    local function drawRule(row, index, globalSearch, width)
        local editing = manageMode[0]
        local rule = row.rule
        local textWidth = math.max(1, width - (editing and 122 or 28))
        if row.textWidth ~= textWidth then
            row.textWidth = textWidth
            row.bodyHeight = imgui.CalcTextSize(rule.text, nil, false, textWidth).y
        end
        local h = math.max(editing and 92 or 72, row.bodyHeight+56)
        if globalSearch then h = h+19 end
        imgui.PushIDInt(index)
        local clicked = imgui.InvisibleButton('##article', imgui.ImVec2(width, h))
        local visible, hovered = imgui.IsItemVisible(), imgui.IsItemHovered()
        if visible then
            local a, z = imgui.GetItemRectMin(), imgui.GetItemRectMax()
            local draw = imgui.GetWindowDrawList()
            draw:AddRectFilled(a, z, hovered and theme.cardHover or theme.card, 10)
            draw:AddRect(a, z, hovered and theme.borderActive or theme.line, 10)
            local label = '§ ' .. rule.number
            local labelWidth = math.min(textWidth, imgui.CalcTextSize(label).x+16)
            draw:AddRectFilled(imgui.ImVec2(a.x+14,a.y+10), imgui.ImVec2(a.x+14+labelWidth,a.y+35), theme.tag, 7)
            draw:AddText(imgui.ImVec2(a.x+22,a.y+15), theme.text, label)
            if globalSearch then
                draw:AddTextFontPtr(imgui.GetFont(), imgui.GetFontSize(), imgui.ImVec2(a.x+14,a.y+43),
                    theme.secondary, row.org.name, nil, textWidth)
            end
            draw:AddTextFontPtr(imgui.GetFont(), imgui.GetFontSize(), imgui.ImVec2(a.x+14,a.y+(globalSearch and 61 or 44)),
                theme.text, rule.text, nil, textWidth)

            if editing then
                local after = imgui.GetCursorScreenPos()
                imgui.SetCursorScreenPos(imgui.ImVec2(z.x-90, a.y+10))
                if imgui.Button('Править', imgui.ImVec2(79,32)) then openEditor(row.orgIndex, rule) end
                imgui.SetCursorScreenPos(imgui.ImVec2(z.x-90, a.y+49))
                if imgui.Button('Удалить', imgui.ImVec2(79,31)) then
                    deletion = row
                    deleteWindow[0] = true
                    actionError = nil
                end
                imgui.SetCursorScreenPos(after)
            elseif hovered then
                imgui.SetMouseCursor(imgui.MouseCursor.Hand)
            end
        end
        if clicked and not editing then
            openRule(row.org, rule)
            warningError = nil
        end
        imgui.PopID()
    end

    local comboOrg = new.int(0)
    local function drawRules()
        local wide = availableWidth() >= 660 and imgui.GetContentRegionAvail().y >= 340
        if wide then
            drawOrgSelector(math.min(226, math.floor(availableWidth()*0.265)))
            imgui.SameLine()
        end
        if imgui.BeginChild('##handbook', imgui.ImVec2(0, 0), true) then
            if not wide then
                comboOrg[0] = activeOrg-1
                imgui.SetNextItemWidth(-1)
                if imgui.ComboStr('##organization', comboOrg, organizationItems, 8) then selectedOrg(comboOrg[0]+1) end
            end
            local w = availableWidth()
            local org = organizations[activeOrg]
            if wide then heading(org.name) end
            local query = ffi.string(searchInput)
            if searchFocus then
                imgui.SetKeyboardFocusHere()
                searchFocus = false
            end
            imgui.SetNextItemWidth(math.max(1, w-87))
            if imgui.InputTextWithHint('##rules_search', 'Поиск по номеру или словам', searchInput, 256) then
                query = ffi.string(searchInput)
                resetScroll = true
            end
            imgui.SameLine()
            if imgui.Button('Очистить', imgui.ImVec2(77,0)) then
                searchInput[0] = 0
                query, searchFocus, resetScroll = '', true, true
            end
            local hasQuery = query:find('%S') ~= nil
            if hasQuery and imgui.Checkbox('Искать во всех разделах', searchAll) then resetScroll = true end
            local globalSearch = hasQuery and searchAll[0]
            local rows = resultRows(query, globalSearch and 0 or activeOrg)
            if imgui.Button(manageMode[0] and 'Завершить правку' or 'Править уставы') then
                manageMode[0] = not manageMode[0]
            end
            imgui.SameLine()
            if imgui.Button('Добавить статью') then openEditor(activeOrg) end
            imgui.SameLine()
            imgui.AlignTextToFramePadding()
            imgui.TextUnformatted(('Найдено: %d'):format(#rows))
            if not globalSearch and (org.note ~= '' or org.updated_at ~= '') then
                imgui.SameLine()
                if imgui.Button('О разделе') then imgui.OpenPopup('##section_info') end
                if imgui.BeginPopup('##section_info') then
                    imgui.PushTextWrapPos(imgui.GetCursorPosX()+360)
                    imgui.TextUnformatted(org.name)
                    if org.updated_at ~= '' then imgui.TextUnformatted('Дата обновления: '..org.updated_at) end
                    if org.note ~= '' then imgui.TextUnformatted(org.note) end
                    imgui.PopTextWrapPos()
                    imgui.EndPopup()
                end
            end
            imgui.Separator()
            if imgui.BeginChild('##rule_results', imgui.ImVec2(0, 0), false) then
                if resetScroll then imgui.SetScrollY(0); resetScroll = false end
                if #rows == 0 then
                    muted(hasQuery and 'По этому запросу ничего не найдено.' or 'В этом разделе пока нет статей.')
                end
                local rowWidth = math.max(1, availableWidth()-1)
                for i, row in ipairs(rows) do drawRule(row, i, globalSearch, rowWidth) end
            end
            imgui.EndChild()
        end
        imgui.EndChild()
    end

    local function switch(label, enabled, animation)
        local clicked = imgui.InvisibleButton(label, imgui.ImVec2(52,28))
        local hovered = imgui.IsItemHovered()
        if hovered then imgui.SetMouseCursor(imgui.MouseCursor.Hand) end
        local render = imgui.GetWindowDrawList()
        local a, z = imgui.GetItemRectMin(), imgui.GetItemRectMax()
        local delta = tonumber(imgui.GetIO().DeltaTime) or 0.016
        animation = animation + ((enabled and 1 or 0) - animation) * math.min(1, delta*15)
        render:AddRectFilled(a, z, enabled and theme.tag or theme.cardHover, 14)
        render:AddRect(a, z, (enabled or hovered) and theme.borderActive or theme.line, 14)
        render:AddCircleFilled(imgui.ImVec2(a.x+14+24*animation, a.y+14), 9, enabled and theme.borderActive or theme.secondary, 20)
        return clicked, animation
    end

    local stages = {'Улики', 'Дата и время', 'Орудие', 'Отправка'}
    local function drawAssistant()
        heading('Авторасследование')
        muted('Открой дело в игре. Ассистент заполнит и отправит бланк.')
        imgui.Spacing()
        if not animationReady then
            investigationAnimation = investigation.enabled and 1 or 0
            animationReady = true
        end
        do
            local changed
            changed, investigationAnimation = switch('##investigation_switch', investigation.enabled, investigationAnimation)
            if changed then
                requestInvestigation = not investigation.enabled
            end
            imgui.SameLine()
            imgui.AlignTextToFramePadding()
            imgui.TextUnformatted(investigation.enabled and 'Авторасследование включено' or 'Авторасследование выключено')
        end
        imgui.Spacing()
        local percent, stage, status = investigation.status()
        if investigation.issue then failure(investigation.issue) else imgui.TextUnformatted(status) end
        imgui.ProgressBar(percent / 100, imgui.ImVec2(-1, 20), ('%d%%'):format(percent))

        local w = availableWidth()
        local columns = w >= 510 and 4 or 2
        for i, label in ipairs(stages) do
            if (i-1)%columns ~= 0 then imgui.SameLine() end
            local tileWidth = math.floor((w-(columns-1)*gap)/columns)
            if i == stage then imgui.PushStyleColor(imgui.Col.Border, accentColor(0.8)) end
            if imgui.BeginChild('##stage_'..i, imgui.ImVec2(tileWidth, 67), true) then
                imgui.TextUnformatted(label)
                muted(i < stage and 'Готово' or (i == stage and 'В процессе' or 'Ожидает'))
            end
            imgui.EndChild()
            if i == stage then imgui.PopStyleColor() end
        end
    end

    local rpAnimation = rpEmotes and 1 or 0
    local function drawSettings()
        heading('Оформление')
        local w = availableWidth()
        local buttonWidth = math.floor((w-2*gap)/3)
        for i, preset in ipairs(themePresets) do
            if i ~= 1 then imgui.SameLine() end
            if themeId == preset.id then imgui.PushStyleColor(imgui.Col.Button, accentColor(0.58)) end
            local picked = imgui.Button(preset.name, imgui.ImVec2(buttonWidth,36))
            if themeId == preset.id then imgui.PopStyleColor() end
            if picked then
                themeId = preset.id
                accent[0], accent[1], accent[2] = unpack(preset.color)
                saveConfig()
            end
        end
        local colorWidth = math.min(w, 420)
        imgui.TextUnformatted('Акцентный цвет')
        imgui.SetNextItemWidth(colorWidth)
        imgui.ColorEdit3('##accent', accent)
        if imgui.IsItemDeactivatedAfterEdit() then saveConfig() end
        imgui.TextUnformatted('Прозрачность фона')
        imgui.SetNextItemWidth(colorWidth)
        imgui.SliderFloat('##opacity', backgroundTransparencyPercent, 0, 75, '%.0f%%')
        if imgui.IsItemDeactivatedAfterEdit() then saveConfig() end

        imgui.Separator()
        heading('Выдача выговора')
        local changed
        changed, rpAnimation = switch('##rp', rpEmotes, rpAnimation)
        if changed then rpEmotes = not rpEmotes; saveConfig() end
        imgui.SameLine()
        imgui.AlignTextToFramePadding()
        imgui.TextUnformatted('RP-отыгровка')

        imgui.Separator()
        heading('Обновления')
        local half = math.floor((w-gap)/2)
        if imgui.Button('Проверить скрипт', imgui.ImVec2(half,36)) then queueUpdate('version', true) end
        imgui.SameLine()
        if imgui.Button('Проверить уставы', imgui.ImVec2(half,36)) then queueUpdate('rules', true) end
        muted('Скрипт  ·  ' .. scriptUpdateStatus)
        muted('Уставы  ·  ' .. rulesStatus)
        imgui.TextUnformatted('GwarnV1 ' .. SCRIPT_VERSION .. '  ·  Ellis_Harris')
        if imgui.Button('Скопировать ссылку на GitHub') then
            imgui.SetClipboardText('https://github.com/ellisharrisyuma-alt/Gwarn1')
        end
    end

    local function dialogLayout(width, height)
        local size = imgui.GetIO().DisplaySize
        imgui.SetNextWindowPos(imgui.ImVec2(size.x/2,size.y/2), imgui.Cond.Appearing, imgui.ImVec2(0.5,0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(math.min(width,size.x-18), math.min(height,size.y-18)), imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0.99)
    end

    local function drawWarning()
        dialogLayout(525, 386)
        local flags = imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoSavedSettings
        if imgui.Begin('Выдача выговора###gw_warning', idWindow, flags) then
            local org, rule = chosenOrg, chosenRule
            heading('§ '..rule.number .. '  ·  ' .. org.code)
            muted(org.name)
            if imgui.BeginChild('##warning_preview', imgui.ImVec2(0,114), true) then wrappedText(rule.text) end
            imgui.EndChild()
            imgui.TextUnformatted('ID игрока')
            if idInputFocusFrames > 0 then
                imgui.SetKeyboardFocusHere()
                idInputFocusFrames = idInputFocusFrames-1
            end
            imgui.SetNextItemWidth(-1)
            local enter = imgui.InputTextWithHint('##player_id_'..idInputSession, 'Например, 123', idInput, 16,
                imgui.InputTextFlags.EnterReturnsTrue + imgui.InputTextFlags.CharsDecimal)
            local id = ffi.string(idInput)
            local valid = id:match('^%d+$') ~= nil and #id <= 6
            if warningError then
                failure(warningError)
            elseif valid then
                muted(warningCommand(id))
            else
                muted('Введите числовой ID игрока.')
            end
            local width = availableWidth()
            if imgui.Button('Отмена', imgui.ImVec2(88,36)) then idWindow[0] = false end
            imgui.SameLine()
            if imgui.Button('Копировать команду', imgui.ImVec2(156,36)) and valid then imgui.SetClipboardText(warningCommand(id)) end
            imgui.SameLine()
            local issue = primaryButton('Выдать', math.max(1,width-264), 36)
            if idWindow[0] and (enter or issue) then
                if not valid then
                    warningError = 'Укажите числовой ID игрока.'
                elseif warningQueue then
                    warningError = 'Предыдущая команда ещё отправляется.'
                elseif findRule(org, rule) then
                    submitWarning(id)
                else
                    idWindow[0] = false
                    sampAddChatMessage(u8:decode('{FFCC66}[GwarnV1]{FFFFFF} Статья обновилась. Выберите её ещё раз.'), -1)
                end
            end
        end
        imgui.End()
    end

    local function drawEditor()
        dialogLayout(596, 440)
        local title = editingRule and 'Редактировать статью' or 'Добавить статью'
        if imgui.Begin(title..'###gw_editor', articleWindow, imgui.WindowFlags.NoResize+imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoSavedSettings) then
            imgui.TextUnformatted('Раздел')
            imgui.SetNextItemWidth(-1)
            imgui.ComboStr('##editor_section', editorOrg, organizationItems, 8)
            imgui.TextUnformatted('Номер статьи')
            imgui.SetNextItemWidth(180)
            if imgui.IsWindowAppearing() then imgui.SetKeyboardFocusHere() end
            imgui.InputTextWithHint('##article_number', 'Например, 1.4.1', editorNumber, 64)
            imgui.TextUnformatted('Текст статьи')
            imgui.InputTextMultiline('##article_text', editorText, 4096, imgui.ImVec2(-1,math.max(70,imgui.GetContentRegionAvail().y-75)))
            if editorError then failure(editorError) end
            local width = availableWidth()
            if imgui.Button('Отмена', imgui.ImVec2(120,36)) then articleWindow[0] = false end
            imgui.SameLine()
            if primaryButton('Сохранить', math.max(1,width-130), 36) then
                editorError = saveArticle()
                if not editorError then
                    articleWindow[0] = false
                    selectedOrg(editorOrg[0]+1)
                    page, resetScroll = 'rules', true
                    searchInput[0] = 0
                end
            end
        end
        imgui.End()
    end

    local function drawDelete()
        dialogLayout(470, 216)
        if imgui.Begin('Удаление статьи###gw_delete', deleteWindow, imgui.WindowFlags.NoResize+imgui.WindowFlags.NoCollapse+imgui.WindowFlags.NoSavedSettings) then
            heading('Удалить § '..deletion.rule.number..'?')
            muted(deletion.org.name)
            if actionError then failure(actionError) end
            if imgui.Button('Отмена', imgui.ImVec2(125,36)) then deleteWindow[0] = false end
            imgui.SameLine()
            if primaryButton('Удалить статью', 178, 36, imgui.ImVec4(0.67,0.24,0.28,1)) then
                actionError = removeArticle(deletion.org, deletion.rule)
                if not actionError then deleteWindow[0] = false end
            end
        end
        imgui.End()
    end

    closeExtraWindow = function()
        if deleteWindow[0] then deleteWindow[0] = false; return true end
        return false
    end

    imgui.OnFrame(function() return window[0] end, function()
        applyTheme()
        local size = imgui.GetIO().DisplaySize
        local w, h = math.max(1,size.x-16), math.max(1,size.y-16)
        imgui.SetNextWindowSize(imgui.ImVec2(math.min(w,990),math.min(h,671)), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowPos(imgui.ImVec2(size.x/2,size.y/2), imgui.Cond.FirstUseEver,imgui.ImVec2(0.5,0.5))
        imgui.SetNextWindowSizeConstraints(imgui.ImVec2(math.min(w,550),math.min(h,420)),imgui.ImVec2(w,h))
        local modal = idWindow[0] or articleWindow[0] or deleteWindow[0]
        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar
        if modal then flags = flags + imgui.WindowFlags.NoInputs end
        if imgui.Begin('GwarnV1  |  Yuma###gw_workspace_v14',window,flags) then
            local width = availableWidth()
            local tabWidth = math.min(185, math.floor((width-2*gap)/3))
            for i, tab in ipairs(navigation) do
                if i > 1 then imgui.SameLine() end
                local selected = page == tab[1]
                if selected then imgui.PushStyleColor(imgui.Col.Button, accentColor(0.56)) end
                if imgui.Button(tab[2],imgui.ImVec2(tabWidth,39)) then page = tab[1] end
                if selected then
                    imgui.PopStyleColor()
                    local a, z = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                    imgui.GetWindowDrawList():AddRectFilled(imgui.ImVec2(a.x+12,z.y-4),imgui.ImVec2(z.x-12,z.y-2),theme.borderActive,2)
                end
            end
            if width >= 750 then
                local caption = investigation.enabled and 'Авторасследование включено' or ('v'..SCRIPT_VERSION)
                local badgeX = imgui.GetWindowContentRegionMax().x-imgui.CalcTextSize(caption).x
                if badgeX > imgui.GetCursorPosX() + 3*tabWidth + 2*gap then
                    imgui.SameLine(badgeX)
                    imgui.AlignTextToFramePadding()
                    imgui.TextUnformatted(caption)
                end
            end
            imgui.Separator()
            if page == 'rules' then
                if not modal and imgui.GetIO().KeyCtrl and imgui.IsKeyPressed(0x46, false) then searchFocus = true end
                drawRules()
            else
                if imgui.BeginChild('##workspace_'..page,imgui.ImVec2(0,0),true) then
                    if page == 'assistant' then drawAssistant() else drawSettings() end
                end
                imgui.EndChild()
            end
        end
        imgui.End()
        if not window[0] then
            idWindow[0], articleWindow[0], deleteWindow[0] = false, false, false
        elseif idWindow[0] and chosenRule then drawWarning()
        elseif articleWindow[0] then drawEditor()
        elseif deleteWindow[0] and deletion then drawDelete() end
    end)
end
