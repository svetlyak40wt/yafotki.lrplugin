--
-- Copyright 2008 Jeffrey Friedl
-- http://regex.info/blog/
--

local LrDialogs         = import 'LrDialogs'
local LrLogger          = import 'LrLogger'
local LrHttp            = import 'LrHttp'
local LrDate            = import 'LrDate'
local LrView            = import 'LrView'
local LrFunctionContext = import 'LrFunctionContext'

local util              = require 'util'

local LrHttpDebug = {
   logging = false,
   trapping = false,
   trapped_count = 0,
}

local logger
local function log(...)
   if not logger then
      logger = LrLogger('LrHttp-Debug')
      logger:enable('print')
   end
   logger:debug(...)
end

local function _cook_url(url)

   url = tostring(url)
   url = url:gsub('Password=[^&]+',     'Password=XXXXX')
   url = url:gsub('EmailAddress=[^&]+', 'EmailAddress=XXXXX')
   url = url:gsub('api_sig=[^&]+',      'api_sig==XXXXX')
   url = url:gsub('auth_token=[^&]+',   'auth_token=XXXXX')
   return url

end

local function __dump_one(item)
   if item == nil then
      return "<nil>"
   elseif type(item) == 'string' then
      return '"' .. item .. '"'
   else
      return "["..tostring(item).."]"
   end
end

local tables_dumped = {}
local function _dump(level, item)

   if type(item) == 'string' then
      return '"' .. item .. '"\n'
   end

   if #level > 30 then
      return "(LEVEL TOO LARGE)"
   end

   if type(item) == "table" then
      if tables_dumped[item] ~= nil then
         return tostring(item)
      else
         tables_dumped[item] = true
         
         local string = ""
         for k,v in pairs(item) do

            if level ~= "" then
               string = string .. level .. "| "
            end
            if type(k) == "string" then
               string = string .. k .. " = "
               if k == "_WinClass" then
                  v = "(table)"
               end
            elseif type(k) == "number" then
               string = string .. tostring(k) .. " = "
            else
               string = string .. "{" .. _dump("KEY|" .. level, k) .. "} = "
            end
          
            if type(v) == "table" then
               string = string .. tostring(v)
               string = string .. ":\n" .. _dump(level .. "   ", v)
            elseif type(v) == "function" then
               string = string .. "function\n"
            elseif type(v) == 'string' then
               string = string .. '"' .. v .. '"\n'
            else
               string = string .. tostring(v) .. "\n"
            end

            if # string > 20000 then
               string = string .. "\n---BREAK--"
               break
            end
         end

         return string
      end
   end

   if type(item) == "number" then
      return tostring(item)
   end

   if type(item) == "nil" then
      return tostring(item)
   end

   if type(item) == "boolean" then
      return tostring(item)
   end

   return "unknown[" .. type(item) .. "]\n"
end

function __dump_headers(note, item)
   if item == nil then
      log("    " .. note .. ": <nil>")
   else
      return log("\n" .. _dump(note, item))
   end
end

local function __report_results(StartTime, ReturnBody, ReturnHeaders)
   local DeltaTime = LrDate.currentTime() - StartTime
   log(string.format("Call time: %.4f sec", DeltaTime))
   if ReturnBody == nil then
      log("nil body returned")
   else
      log(string.format("returned body %d bytes long", #ReturnBody))
   end
   __dump_headers("    return header", ReturnHeaders)
   if ReturnHeaders == nil or ReturnHeaders.status ~= 200 then
      log(ReturnBody)
   end
end


local function __execute(func)

   if not LrHttpDebug.trapping then
      return func()
   end

   local Success, ResultBody, ResultHeaders = LrFunctionContext.pcallWithContext('trapped call', func)

   if LrHttpDebug.logging then
      log("trapped call successful: " .. tostring(Success))
   end

   if not Success and ResultBody:match('FormatMessageW') then
      if LrHttpDebug.logging then
         log("NOTE: 'FormatMessageW' bug detected")
      end
      ResultBody = "TRAPPED ERROR"

      LrHttpDebug.trapped_count = LrHttpDebug.trapped_count + 1
   end

   return ResultBody, ResultHeaders

end


function LrHttpDebug.get(url, headers)

   local StartTime
   if LrHttpDebug.logging then
      log("\n\n---------------------------------------------------------------------\n\n")
      log("LrHttp.get(" .. _cook_url(url) .. ")")
      __dump_headers("    call header", headers)
      StartTime = LrDate.currentTime()
   end

   local ReturnBody, ReturnHeaders = __execute(function()
                                                  return LrHttp.get(url, headers)
                                               end)

   if LrHttpDebug.logging then
      __report_results(StartTime, ReturnBody, ReturnHeaders)
   end

   return ReturnBody, ReturnHeaders
end


function LrHttpDebug.openUrlInBrowser(url)

   LrHttp.openUrlInBrowser(url)

end

function LrHttpDebug.parseCookie (cookie, decodeUrlEncoding)

   local Result = LrHttp.parseCookie (cookie, decodeUrlEncoding)

   return Result
end


function LrHttpDebug.post(url, postBody, headers, method)

   local StartTime
   if LrHttpDebug.logging then
      log("\n\n---------------------------------------------------------------------\n\n")
      log("LrHttp.post(" .. _cook_url(url) .. ")")
      if postBody == nil then
         log("  post body is nil")
      elseif type(postBody) == 'string' then
         log(string.format("  body length is #%d bytes", #postBody))
      else
         log("  body: " .. __dump_one(postBody))
      end
      log("  method: " .. __dump_one(method))      
      __dump_headers("    call header", headers)
      StartTime = LrDate.currentTime()
   end

   local ReturnBody, ReturnHeaders = __execute(function()
                                                  return LrHttp.post(url, postBody, headers, method)
                                               end)

   if LrHttpDebug.logging then
      __report_results(StartTime, ReturnBody, ReturnHeaders)
   end

   return ReturnBody, ReturnHeaders
end


function LrHttpDebug.postMultipart (url, content, headers)

   local StartTime
   if LrHttpDebug.logging then
      log("\n\n---------------------------------------------------------------------\n\n")
      log("LrHttp.postMultipart(" .. _cook_url(url) .. ")")
      __dump_headers("    call content", content)
      __dump_headers("    call header",  headers)
      StartTime = LrDate.currentTime()
   end

   local ReturnBody, ReturnHeaders = __execute(function()
                                                  return LrHttp.postMultipart(url, content, headers)
                                               end)

   if LrHttpDebug.logging then
      __report_results(StartTime, ReturnBody, ReturnHeaders)
   end

   return ReturnBody, ReturnHeaders
end


function LrHttpDebug.exportPresetFields()

   return {
      { key = 'httpdebug_logging',         default = false },
      { key = 'httpdebug_trapping',        default = false },
   }

end


function LrHttpDebug.dialog_section(state, v)

   local function update_status()

      LrHttpDebug.logging  = state.httpdebug_logging
      LrHttpDebug.trapping = state.httpdebug_trapping

   end
   state:addObserver('httpdebug_logging',   update_status)
   state:addObserver('httpdebug_trapping',  update_status)

   update_status()


   local folder = util.WinMac(LOC("$$$/Folder/MyDocuments=MyDocuments"), LOC("$$$/Folder/Documents=Documents"))

   return v:group_box {
      title = LOC("$$$/276=debugging options"),

      v:view {
         place = 'horizontal',
         v:checkbox {
            title = "",
            value = LrView.bind 'httpdebug_logging',
         },
         v:static_text { title = LOC("$$$/390=Enable HTTP Logging: writes HTTP log to 'LrHttp-Debug.log' in your '^1' folder", folder) },
      },
      v:view {
         place = 'horizontal',
         v:checkbox {
            title = "",
            value = LrView.bind 'httpdebug_trapping',
         },
         v:static_text { title = LOC("$$$/391=Enable HTTP Error trapping, for Windows users getting the 'FormatMessageW failed' error.") },
      },
      v:view {
         margin_top = 0,
         margin_left = 17,
         v:static_text {
            title = LOC("$$$/392=Trapping causes the error to be ignored, perhaps allowing uploading to work.^nHowever, some features (such as 'delete previous uploads') may no longer work,^nand some uploads may silently fail.^n")
         }
      }
   }

end

function LrHttpDebug.IssueWarning()

   if LrHttpDebug.trapped_count > 0 then

      LrDialogs.message("Warning", "Some HTTP errors were trapped and ignored.\nSome uploads may have silently failed. Some functionality may have been disabled.")

   end
   LrHttpDebug.trapped_count = 0

end



return function (options)
          if options.logging ~= nil then
             LrHttpDebug.logging = options.logging
          end
          if options.trapping ~= nil then
             LrHttpDebug.trapping = options.trapping
          end
          return LrHttpDebug
       end
