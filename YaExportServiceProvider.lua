--
-- Adobe Photoshop Lightroom export plugin for Yandex.Fotki
-- Copyright 2008 Alexander Artemenko
--
-- http://svetlyak.ru/blog/lightroom-plugins/
--
local PluginVersion      = '0.1.0'
local PluginContactName  = 'Alexander Artemenko'
local PluginContactEmail = 'svetlyak.40wt@gmail.com'
local PluginUrl          = 'http://svetlyak.ru/blog/lightroom-plugins/'

-- imports
local LrLogger = import 'LrLogger'
local LrHttp = import 'LrHttp'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrView = import 'LrView'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'

local isDebug = false

local logger = LrLogger('YaFotki')
logger:enable('print')
local debug, info, warn, err, trace = logger:quick( 'debug', 'info', 'warn', 'err', 'trace' )

local YaFotki = {}

local postUrl = 'http://img.fotki.yandex.ru/modify'
local authUrl = 'https://passport.yandex.ru/passport?mode=auth&login=%s&passwd=%s&twoweeks=yes'

function YaFotki.signupDialog(propertyTable)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local p = propertyTable

    local contents = f:column {
        spacing = f:control_spacing(),
        bind_to_object = propertyTable,
        f:row {
            f:static_text { title = 'Login', width = LrView.share('sign_label') },
            f:edit_field {value = bind('ya_login') },
        },
        f:row {
            f:static_text { title = 'Password', width = LrView.share('sign_label') },
            f:password_field {value = bind('ya_password') },
        },
        f:row {
            f:static_text { title = 'Remember', width = LrView.share('sign_label') },
            f:checkbox {value = bind('ya_remember') },
        },
    }
    local result = LrDialogs.presentModalDialog{
        title = 'Signup to fotki.yandex.ru',
        contents = contents,
    }
    if result == 'ok' then
        LrFunctionContext.postAsyncTaskWithContext('YandexAuth', function(context)
            LrDialogs.attachErrorDialogToFunctionContext(context)
            context:addFailureHandler(function()
                err('Authentication failed')
                p.loginText = 'Error, authentication failed!'
                p.loginButtonEnabled = true
             end)

            p.loginText = 'Waiting for response from yandex...'
            p.loginButtonEnabled = false
--            local cookies = {[1] = {field = 'Set-Cookie', value = 'yandex_login=svetlyak40wt'}}
            local cookies = YaFotki.auth(p.ya_login, p.ya_password)
            if cookies == nil then
                debug('cookies dropped because "auth failed?"')
            end
            p.ya_cookies = cookies
        end)
    end
end

function YaFotki.cookiesObserver(properties, key, newValue)
    if type(newValue) == 'table' and #newValue > 0 then
        local login = ''
        for i, c in ipairs(newValue) do
            local parsed = LrHttp.parseCookie(c.value)
            if parsed.yandex_login ~= nil then
                login = parsed.yandex_login
                break
            end
        end
        properties.loginText = 'Logged in as ' .. login
        properties.loginButtonText = 'Log out'
        properties.loginButtonAction = function(button)
            debug('cookies dropped because "logout action"')
            properties.ya_cookies = nil
        end
        properties.LR_canExport = true
    else
        properties.loginText = 'Not logged in'
        properties.loginButtonText = 'Log in'
        properties.loginButtonAction = function(button)
            LrFunctionContext.callWithContext('signupDialog', function( context ) 
                LrDialogs.attachErrorDialogToFunctionContext(context)
                YaFotki.signupDialog(properties)
            end )
        end
        properties.LR_canExport = false
    end
    properties.loginButtonEnabled = true
--    debug( "Wow, new cookies! - " .. table2string(newValue))
end

function YaFotki.exportDialog(viewFactory, propertyTable)
    local bind = LrView.bind
    local f = viewFactory

    YaFotki.dropCookiesIfNeeded(propertyTable)
    YaFotki.cookiesObserver(propertyTable, 'ya_cookies', propertyTable.ya_cookies)
    propertyTable:addObserver('ya_cookies', YaFotki.cookiesObserver)

    return {
        {
            title ='fotki.yandex.ru',
            synopsis = bind { key = 'loginText', object = propertyTable },
            f:group_box {
                title = 'Auth',
                fill = 1,
                f:row {
                    f:static_text { title = bind('loginText'), fill = 1 },
                    f:push_button {
                        title = bind('loginButtonText'),
                        action = bind('loginButtonAction'),
                        enabled = bind('loginButtonEnabled'),
                    },
                }
            },
            f:group_box {
                title = 'Access settings',
                fill = 1,
                f:row {
                    f:column {
                        spacing = f:control_spacing(),
                        f:row {
                            f:static_text {
                                title = 'Will be visible to',
                            },
                            f:popup_menu {
                                value = bind('ya_access'),
                                items = {
                                    { title = 'All', value='public' },
                                    { title = 'Friends', value='friends' },
                                    { title = 'Only I am', value='private' },
                                },
                            },
                        },
                        f:checkbox { title = 'Hide original and disable printing', value = bind('ya_mhide_orig') },
                        f:checkbox { title = 'Dont show in "new" and "best" sections', value = bind('ya_no_more_participation') },
                    },
                    f:column {
                        spacing = f:control_spacing(),
                        f:checkbox { title = 'Publish on ya.ru', value = bind('ya_post2yaru') },
                        f:checkbox { title = 'Disable comments', value = bind('ya_disable_comments') },
                        f:checkbox { title = 'Amateur content', value = bind('ya_mxxx') },
                    },
                },
            },
            f:row {
                f:static_text {
                    title = LOC '$$$/Yandex/Upload/PluginInfo/Title=Yandex.Fotki Export Plugin for Lightroom',
                    font = '<system/bold>',
                },
                f:static_text {
                    title = LOC('$$$/Yandex/Upload/PluginInfo/Version=version ^1', PluginVersion)
                },
                f:static_text {
                    title = LOC('$$$/Yandex/Upload/PluginInfo/By=by ^1', PluginContactName),
                    tooltip = PluginContactEmail,
                },
            },
            f:row {
                f:push_button {
                    size = "small",
                    title = PluginUrl,
                    action = function(button)
                        LrHttp.openUrlInBrowser(PluginUrl)
                    end,
                },
            },
        }
    }
end

function YaFotki.upload(exportContext, path, photo)
    LrFunctionContext.callWithContext('signupDialog', function(context)
        LrDialogs.attachErrorDialogToFunctionContext(context)

        local fileName = LrPathUtils.leafName(path)
        local p = exportContext.propertyTable
        debug('Uploading ' .. path .. ' to the fotki.yandex.ru')

        if p.ya_cookies then
            debug('Preparing upload data')

            local title, description, tags

            photo.catalog:withCatalogDo( function()
                title = photo:getFormattedMetadata('title')
                if not title or #title == 0 then
                    title = fileName
                end
                description = photo:getFormattedMetadata('caption')
                tags = photo:getFormattedMetadata('keywordTags')
            end )

            local mimeChunks = {
                { name = 'image_source', fileName = fileName, filePath = path, contentType = 'application/octet-stream' },
                { name = 'retpage', value = 'http://fotki.yandex.ru/actions/upload-status.xml' },
                { name = 'title', value = title },
                { name = 'description', value = description },
                { name = 'tags', value = tags },

                -- settings from the export dialog
                { name = 'access', value = p.ya_access },
            }
            if p.ya_post2yaru == true then table.insert(mimeChunks, { name = 'post2yaru', value = 'on' }) end
            if p.ya_disable_comments == true then table.insert(mimeChunks, { name = 'disable_comments', value = 'on' }) end
            if p.ya_mxxx == true then table.insert(mimeChunks, { name = 'mxxx', value = 'on' }) end
            if p.ya_mhide_orig == true then table.insert(mimeChunks, { name = 'mhide_orig', value = 'on' }) end
            if p.ya_no_more_participation == true then table.insert(mimeChunks, { name = 'no_more_participation', value = 'on' }) end

            debug('Uploading')
            local result = LrHttp.postMultipart(postUrl, mimeChunks, p.ya_cookies)
            if isDebug then
                debug('Writing result on the disk')
                local f = io.open('/tmp/upload.html', 'wt')
                f:write(result)
                f:close()
            end
        else
            debug('No cookies. Are you logged in?')
        end
    end)
end

function table2string(t)
    if type(t) == 'table' then
        local result = '{'
        for k, v in pairs(t) do
            if type(v) == 'table' then
                result = result .. ' ' .. tostring(k) .. ' = ' .. table2string(v) .. ' , '
            else
                result = result .. ' ' .. tostring(k) .. ' = ' .. tostring(v) .. ' , '
            end
        end
        result = result .. '}'
        return result
    else
        return tostring(t)
    end
end

function YaFotki.auth(login, password)
    debug('Trying to authentificate')
    local url = string.format(authUrl, login, password)
    body, headers = LrHttp.get(url)
    if isDebug then
        local f = io.open('/tmp/ya-auth.html', 'wt')
        f:write(body)
        f:close()
    end

    local cookies = {}
    for k, v in pairs(headers) do
        if type(v) == 'table' and v.field == 'Set-Cookie' then
            table.insert(cookies, v)
        end
    end

    if #cookies > 0 then
        return cookies
    else
        LrErrors.throwUserError( LOC "$$$/Yandex/Auth/Error/Failed=Can't login in with this username and password.^r^nPlease, try again!")
    end
end

function YaFotki.postProcess(functionContext, exportContext)
    local session = exportContext.exportSession
    local nPhotos = session:countRenditions()
    local p = exportContext.propertyTable

    local progress = exportContext:configureProgress {
        title = nPhotos > 1
            and LOC('$$$/Yandex/Upload/Progress=Uploading ^1 photos to Yandex.Fotki', nPhotos)
            or  LOC('$$$/Yandex/Upload/Progress/One=Uploading one photo to Yandex.Fotki')
        }

    for i, rendition in exportContext:renditions{stopIfCanceled = true} do
        local photo = rendition.photo
        local success, pathOrMessage = rendition:waitForRender()

        if progress:isCanceled() then break end

        if success then
            YaFotki.upload(exportContext, pathOrMessage, photo)
        else
            error(pathOrMessage)
        end

        LrFileUtils.delete(pathOrMessage)
    end

end

function YaFotki.dropCookiesIfNeeded(propertyTable)
    local p = propertyTable
    if p.ya_remember == false then
        p.ya_cookies = nil
        p.ya_password = ''
        debug('Cookies dropped because "user don\'t want to remember login"')
    end
end

return {
    exportPresetFields = {
        {key = 'ya_login', default = 'You login'},
        {key = 'ya_access', default = 'public'},
        {key = 'ya_post2yaru', default = false},
        {key = 'ya_disable_comments', default = false},
        {key = 'ya_mxxx', default = false},
        {key = 'ya_mhide_orig', default = true},
        {key = 'ya_no_more_participation', default = false},
        {key = 'ya_cookies', default = nil},
        {key = 'ya_remember', default = false},
    },
    processRenderedPhotos = YaFotki.postProcess,
    sectionsForTopOfDialog = YaFotki.exportDialog,
}
