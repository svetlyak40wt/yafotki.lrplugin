--
-- Adobe Photoshop Lightroom export plugin for Yandex.Fotki
-- Copyright 2008 Alexander Artemenko
--
-- http://svetlyak.ru/blog/lightroom-plugins/
--
local PluginVersion      = '0.2.0'
local PluginContactName  = 'Alexander Artemenko'
local PluginContactEmail = 'svetlyak.40wt@gmail.com'
local PluginUrl          = 'http://svetlyak.ru/blog/lightroom-plugins/'

local isDebug = true

-- imports
local LrHttp
if isDebug then
    LrHttp = require 'LrHttpDebug' { logging = true, trapping = true}
else
    LrHttp = import 'LrHttp'
end

local LrLogger = import 'LrLogger'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'
local LrView = import 'LrView'
local LrDialogs = import 'LrDialogs'
local LrErrors = import 'LrErrors'
local LrMD5 = import 'LrMD5'

local logger = LrLogger('YaFotki')
logger:enable('print')
local debug, info, warn, err, trace = logger:quick( 'debug', 'info', 'warn', 'err', 'trace' )

local YaFotki = {}

local postUrl = 'http://up.fotki.yandex.ru/upload'
local authUrl = 'https://passport.yandex.ru/passport?mode=auth&login=%s&passwd=%s&twoweeks=yes'
local albumsUrl = 'http://fotki.yandex.ru/users/%s/albums/'
local uploadRetPath = 'http://fotki.yandex.ru/actions/ajax_upload_fotka.xml'

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
    trace('YaFotki.cookiesObserver')
    debug('cookiesObserver: ' .. table2string(newValue))
    if type(newValue) == 'table' and #newValue > 0 then
        local login = ''
        for i, c in ipairs(newValue) do
            trace('Cookie value: ' .. c.value)
            local parsed = YaFotki.parseCookie(c.value)
            if parsed.yandex_login ~= nil then
                login = parsed.yandex_login
                break
            end
        end

        LrFunctionContext.postAsyncTaskWithContext('get_albums', function(context)
            LrDialogs.attachErrorDialogToFunctionContext(context)
            YaFotki.get_albums(properties)
        end)

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
    return LrFunctionContext.callWithContext('exportDialog', function(context)
        LrDialogs.attachErrorDialogToFunctionContext(context)
        trace('YaFotki.exportDialog')
        local bind = LrView.bind
        local f = viewFactory

        propertyTable.albumsLoaded = false
        propertyTable.albums = {}

        YaFotki.dropCookiesIfNeeded(propertyTable)
        YaFotki.cookiesObserver(propertyTable, 'ya_cookies', propertyTable.ya_cookies)
        propertyTable:addObserver('ya_cookies', YaFotki.cookiesObserver)
        propertyTable:addObserver('selectedAlbum', function (props, key, new_value)
            debug('selectedAlbum=' .. new_value)
         end)

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
                f:row {
                    f:static_text {
                        title = 'Upload to album:'
                    },
                    f:popup_menu {
                        value = bind('selectedAlbum'),
                        items = bind('albums'),
                        width_in_chars = 30,
                    },
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
--                            f:checkbox { title = 'Publish on ya.ru', value = bind('ya_post2yaru') },
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
                            LrHttp.openUrlInBrowser('http://svetlyak.ru/count/r/1/')
                        end,
                    },
                },
            }
        }
    end)
end

function YaFotki.search_album(albums, album_id)
    for i, a in ipairs(albums) do
        if a.value == album_id then
            return a
        end
    end
end

function YaFotki.get_albums(p)
    local albums = {}

    if p.albumsLoaded == false then
        local url = string.format(albumsUrl, p.ya_login)
        local body, headers = LrHttp.get(url, p.ya_cookies)

        if isDebug then
            debug('Writing album list on the disk to /tmp/album-list.xml')
            local f = io.open('/tmp/album-list.xml', 'wt')
            f:write(body)
            f:close()
        end

        if headers.status == 200 then
            for id, title in body:gmatch('album/(%d+)/" title="([^"]*)"') do
                albums[#albums+1] = {title=title, value=id}
            end
            p.albums = albums
            local albums_count = #albums
            if albums_count > 0 then
                if YaFotki.search_album(p.albums, p.selectedAlbum) == nil then
                    p.selectedAlbum = p.albums[1].value
                end
            else
                LrDialogs.message('Can\'t to fetch an album list.', 'You don\'t have any albums or an account at the http://fotki.yandex.ru.\n\nPlease, go and create some albums (http://fotki.yandex.ru/users/' .. p.ya_login .. '/albums/add/) or register at http://fotki.yandex.ru/oferta.xml.', 'info')
            end
        else
            err('Error during retriving album list HTTP status: ' .. tostring(headers.status))
        end
    end
end

function YaFotki.uploadOld(exportContext, path, photo)
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
                { name = 'retpage', value = uploadRetPath },
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
--            if p.selectedAlbum ~= nil then table.insert(mimeChunks, { name = 'album', value = tostring(p.selectedAlbum) }) end

            debug( 'Upload data: ' .. table2string(mimeChunks) )

            debug('Uploading')
            local result, headers = LrHttp.postMultipart(postUrl, mimeChunks, p.ya_cookies)
            if isDebug then
                debug('Writing result on the disk')
                local f = io.open('/tmp/upload.html', 'wt')
                f:write(result)
                f:close()
            end
            if headers.status ~= 200 then
                err( 'Error during upload, HTTP response: ' .. tostring(headers.status) )
            end
        else
            debug('No cookies. Are you logged in?')
        end
    end)
end

function YaFotki.generateSid()
    local result = ''
    for i = 1, 13 do
        result = result .. tostring(math.random(9))
    end
    return result
end

function YaFotki.upload(exportContext, path, photo)
    LrFunctionContext.callWithContext('upload', function(context)
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

            local sid = YaFotki.generateSid()
            local url = postUrl .. '?post_id=' .. p.ya_login .. '.' .. sid
            local source = io.open(path, 'rb')
            local md5 = LrMD5.digest(source:read('*a'))
            local file_size = source:seek()

            local tmp_path = LrPathUtils.getStandardFilePath('temp')
            tmp_path = '/tmp/'
            local xml_path = LrFileUtils.chooseUniqueFileName( LrPathUtils.child(tmp_path, 'data.xml') )
            local frag_path = LrFileUtils.chooseUniqueFileName( LrPathUtils.child(tmp_path, 'frag.bin') )
            local piece_size = 64000
            if file_size < piece_size then
                piece_size = file_size
            end

            local client_xml = '<?xml version="1.0" encoding="utf-8"?>' ..
            '<client-upload md5="' .. md5 .. '" cookie="' .. md5 .. sid .. '">' ..
            '<filename>' .. fileName .. '</filename>' ..
            '<title>' .. title .. '</title>' ..
            '<albumId>' .. tostring(p.selectedAlbum) .. '</albumId>' ..
            '<copyright>0</copyright>' ..
            '<tags>' .. tags .. '</tags>' ..
--            '<post2yaru>' .. tostring(p.ya_post2yaru) .. '</post2yaru>' ..
            '<xxx>' .. tostring(p.ya_mxxx) .. '</xxx>' ..
            '<disable_comments>' .. tostring(p.ya_disable_comments) .. '</disable_comments>' ..
            '<hide_orig>' .. tostring(p.ya_mhide_orig) .. '</hide_orig>' ..
            '<no_more_participation>' .. tostring(p.ya_no_more_participation) .. '</no_more_participation>' ..
            '<access>' .. tostring(p.ya_access) .. '</access>' ..
            '</client-upload>'

            debug('client-xml: ' .. client_xml)

            local xml = io.open(xml_path, 'wb')
            xml:write(client_xml)
            xml:flush()

            -- PHOTO-START
            local mimeChunks = {
                { name = 'query-type', value = 'photo-start' },
                { name = 'piece-size', value = tostring(piece_size) },
                { name = 'file-size', value = tostring(file_size) },
                { name = 'checksum', value = md5 },
                { name = 'client-xml', fileName = 'data.xml', filePath = xml_path, contentType = 'text/xml' },
            }
            debug( 'photo-start: ' .. table2string(mimeChunks) )
            debug( 'photo-start: ' .. table2string(p.ya_cookies) )

            local result, headers = LrHttp.postMultipart(url, mimeChunks, p.ya_cookies)
            if headers and headers.status ~= 200 then
                err( 'Error during upload, HTTP response: ' .. tostring(headers.status) )
            end
            debug('photo-start: ' .. result)
            cookie = result:match('cookie = "(%x+)"')
            debug('photo-start: cookie=' .. tostring(cookie))

            if isDebug then
                debug('Writing result on the disk')
                local f = io.open(LrPathUtils.child(tmp_path, 'upload-start.html'), 'wt')
                f:write(result)
                f:close()
            end

            xml:close()

            -- PHOTO-PIECES
            mimeChunks = {
                { name = 'query-type', value = 'photo-piece' },
                { name = 'offset', value = '0' },
                { name = 'cookie', value = cookie },
                { name = 'fragment', fileName = 'frag.bin', filePath = frag_path },
            }
            current_offset = 0
            source:seek('set')
            local piece_num = 1
            while current_offset < file_size do
                mimeChunks[2].value = tostring(current_offset)
                local data = source:read(piece_size)
                if data == nil then
                    break
                end

                local frag = io.open(frag_path, 'wb')
                frag:write(data)
                frag:close()

                debug( 'photo-piece: ' .. table2string(mimeChunks) )
                local result, headers = LrHttp.postMultipart(url, mimeChunks, p.ya_cookies)
                if headers and headers.status ~= 200 then
                    err( 'Error during upload, HTTP response: ' .. tostring(headers.status) )
                end
                debug('photo-piece: ' .. result)

                if isDebug then
                    debug('Writing result on the disk')
                    local f = io.open(LrPathUtils.child(tmp_path, 'upload-piece-' .. tostring(piece_num + 1) .. '.html'), 'wt')
                    f:write(result)
                    f:close()
                end
                current_offset = current_offset + #data
                debug('new offset is: ' .. tostring(current_offset))
                piece_num = piece_num + 1
            end

            -- PHOTO-CHECKSUM
            mimeChunks = {
                { name = 'query-type', value = 'photo-checksum' },
                { name = 'cookie', value = cookie },
                { name = 'size', value = tostring(piece_size) },
            }
            debug( 'photo-checksum: ' .. table2string(mimeChunks) )
            local result, headers = LrHttp.postMultipart(url, mimeChunks, p.ya_cookies)
            if headers and headers.status ~= 200 then
                err( 'Error during upload, HTTP response: ' .. tostring(headers.status) )
            end
            debug('photo-checksum: ' .. result)

            if isDebug then
                debug('Writing result on the disk')
                local f = io.open(LrPathUtils.child(tmp_path, 'upload-checksum.html'), 'wt')
                f:write(result)
                f:close()
            end

            -- PHOTO-FINISH
            mimeChunks = {
                { name = 'query-type', value = 'photo-finish' },
                { name = 'cookie', value = cookie },
            }
            debug( 'photo-finish: ' .. table2string(mimeChunks) )
            local result, headers = LrHttp.postMultipart(url, mimeChunks, p.ya_cookies)
            if headers and headers.status ~= 200 then
                err( 'Error during upload, HTTP response: ' .. tostring(headers.status) )
            end
            debug('photo-finish: ' .. result)

            if isDebug then
                debug('Writing result on the disk')
                local f = io.open(LrPathUtils.child(tmp_path, 'upload-finish.html'), 'wt')
                f:write(result)
                f:close()
            end

            -- CLEAN UP
            LrFileUtils.delete(xml_path)
            LrFileUtils.delete(frag_path)
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

function strip(text, chars)
    local tmp = text:gsub('^['..chars..']+', '', 1)
    return tmp:gsub('['..chars..']+$', '', 1)
end

function split(text, sep)
    local result = {}
    for part in text:gmatch('[^' .. sep ..']+') do
        result[#result+1] = part
    end
    return result
end

function partition(text, sep)
    local result = {}
    pos = text:find(sep, 1, true)
    if pos == nil then
        return text, nil
    else
        return text:sub(1, pos-1), text:sub(pos+1)
    end
    return result
end

function YaFotki.parseCookie(cookie)
    local result = {}
    name_value = split(cookie, ';')
    for i, v in ipairs(name_value) do
        name, value = partition(strip(v, ' '), '=')
        result[name] = value
    end
    return result
end

function YaFotki.extractCookie(headers)
    local cookies = {}
    local cookie = ''
    if headers then
        for k, v in pairs(headers) do
            if type(v) == 'table' and v.field == 'Set-Cookie' then
                if #v.value == 22 then
                    cookies[#cookies] = cookies[#cookies] .. ' ' .. v.value
                    local parsed = YaFotki.parseCookie(cookies[#cookies])

                    for name, value in pairs(parsed) do
                        local lower_name = name:lower()
                        if      lower_name ~= 'path'
                                and lower_name ~= 'domain'
                                and lower_name ~= 'expires' then

                            if type(value) == 'boolean' and value == true then
                                value = ''
                            end
                            if cookie == '' then
                                cookie = name .. '=' .. tostring(value)
                            else
                                cookie = cookie .. '; ' .. name .. '=' .. tostring(value)
                            end
                        end
                    end
                else
                    cookies[#cookies + 1] = v.value
                end
            end
        end
    end
    debug('extractCookie: ' .. cookie)
    return {{field = 'Cookie', value = cookie},}
end

function YaFotki.auth(login, password)
    debug('Trying to authentificate')
    local url = string.format(authUrl, login, password)
    local body, headers = LrHttp.get(url)
    if isDebug then
        local f = io.open('/tmp/ya-auth.html', 'wt')
        f:write(body)
        f:close()
    end

    cookie = YaFotki.extractCookie(headers)

    if #cookie[1].value > 0 then
        return cookie
    else
        LrErrors.throwUserError( LOC "$$$/Yandex/Auth/Error/Failed=Can't login in with this username and password.^r^nPlease, try again!")
    end
end

function YaFotki.postProcess(functionContext, exportContext)
    trace('YaFotki.postProcess')
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
    hideSections = {
        'exportLocation',
        'postProcessing',
    },
    hidePrintResolution = true,
    exportPresetFields = {
        {key = 'ya_login', default = 'You login'},
        {key = 'ya_access', default = 'public'},
--        {key = 'ya_post2yaru', default = false},
        {key = 'ya_disable_comments', default = false},
        {key = 'ya_mxxx', default = false},
        {key = 'ya_mhide_orig', default = true},
        {key = 'ya_no_more_participation', default = false},
        {key = 'ya_cookies', default = nil},
        {key = 'ya_remember', default = false},
        {key = 'selectedAlbum', default = nil},
    },
    processRenderedPhotos = YaFotki.postProcess,
    sectionsForTopOfDialog = YaFotki.exportDialog,
}

