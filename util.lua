--[[--------------------------------------------------------------------------

Some random helper functions for a Lightroom export plugin.
Copyright 2008 Jeffrey Friedl

--]]--------------------------------------------------------------------------

local LrXml       = import 'LrXml'
local LrPathUtils = import 'LrPathUtils'

local util = {}

--
-- Helper function -- given a table of { value = ... } tables, return true
-- if the given value is found in one of the subtable's 'value' entries,
-- false otherwise.
-- 
function util.popupmenu_items_has_value(t, value)
   if not value then
      return false
   end

   for i, set in ipairs(t) do
      if set.value == value then
         return true
      end
   end

   return false
end

--
-- Helper function -- given a table of { title = ...., value = ... } tables, return the 'title'
-- from the table with the given 'value'. Returns nil if not found.
-- 
function util.popupmenu_title_from_value(t, value)
   if not value then
      return nil
   end

   for i, set in ipairs(t) do
      if set.value == value then
         return set.title
      end
   end
   return nil
end

--
-- Popup menu items might have "&amp;", "&lt;", "&gt;" that need to be decoded.
-- Also, all remaining ampersands should be doubled, because LrView strips single ampersands.
--
function util.tidy_popupmenu_items(items)
   for k, v in ipairs(items) do
      local text = v.title
      text = text:gsub('&lt;',  '<')
      text = text:gsub('&gt;',  '>')
      text = text:gsub('&amp;', '&')
      text = text:gsub('&',     '&&')
      v.title = text
   end
end

function util.WinMac(win, mac)
   if WIN_ENV then
      return win
   else
      return mac
   end
end


--
-- Given a string, return the urlencoded version of it
--
function util.urlencode(text)
   return text:gsub('[^-_%w/:.]', function(char)
                                     return string.format ("%%%02X", char:byte())
                                  end)
end


--
-- Given a CSV string where items may appear within quotes (single or
-- double), return a table of the itmes. Blank items (which ostensibly
-- would be created by commas separated by only whitespace, and an empty
-- pair of double-quoted strings) are ignored.
--
-- Return okay == true if things seem okay, okay == false if there's a
-- clear error (embedded doublquote), and okay == nil if it's an error that
-- might be due to an "in progress" state.
--
function util.CsvToTable_NoEmpty(text)

   local list = {}
   local okay = true

   -- strip leading commas/whitespace
   text = text:gsub('^[%s,]+', '',  1)

   while text ~= '' do

      -- Look first for a leading double-quoted string
      local item, len = text:match('^"([^"]*)"[,%s]*()')

      -- Look next for a leading single-quoted string
      if not len then
         item, len = text:match("^'([^']*)'[,%s]*()")
      end

      -- if what remains begins with  a doublequote, consider it
      -- an error and go ahead and take the rest of the entry.
      if not len then
         item, len = text:match('^(".*)()')
         if len then
            okay = nil
         end
      end

      -- Look next for anything...
      if not len then
         item, len = text:match('^([^,]*)[,%s]*()')

         -- if this has an embedded doublequote, consider it an error
         if len and item:match('"') then
            if okay == true then
               okay = false
            end
         end
      end

      if len then
         if item ~= '' then
            table.insert(list, item)
         end

         text = text:sub(len)
      else
         -- This should never happen, so if it does it's because I screwed up,
         -- so we'll bail.
         text = ""
      end
   end
   
   return list, okay
end

--
-- Like CSC, but separated by spaces, not commas
--
function util.SsvToTable_NoEmpty(text)

   local list = {}
   local error_certain  = false
   local error_possible = false


   local okay = true

   -- strip leading whitespace
   text = text:gsub('^%s+', '',  1)

   while text ~= '' do

      -- Look first for a leading double-quoted string
      local item, separating_space, len = text:match('^"([^"]*)"(%s*)()')

      -- Look next for a leading single-quoted string
      if not len then
         item, separating_space, len = text:match("^'([^']*)'(%s*)()")
      end

      -- If what remains begins with a doublequote, consider it
      -- an error and go ahead and take the rest of the entry.
      if not len then
         item, len = text:match('^"(.*)()')
         separating_space = ""
         if len then
            error_possible = true
         end
      end

      -- Look next for anything...
      if not len then
         item, separating_space, len = text:match('^([^%s]*)(%s*)()')

         -- if this has an embedded doublequote, consider it an error
         if len and item:match('"') then
            error_certain = true
         end
      end

      if len then
         if item ~= '' then
            table.insert(list, item)
         end

         text = text:sub(len)
      else
         -- This should never happen, so if it does it's because I screwed up,
         -- so we'll bail.
         text = ""
      end

      if text ~= "" and separating_space == "" then
         error_certain = true
      end
   end
   
   local okay = true
   if error_certain then
      okay = false
   elseif error_possible then
      okay = nil
   end

   return list, okay
end

function util.cook_for_xml(text)
   
   local builder = LrXml.createXmlBuilder(true)
   builder:text(text)
   return builder:serialize()

end

local extension_to_MIME = {
   jpe  = 'image/jpeg',
   jpg  = 'image/jpeg',
   jpeg = 'image/jpeg',
   tif  = 'image/tiff',
   tiff = 'image/tiff',
}

function util.image_mime_type(filename)
   return extension_to_MIME[string.lower(LrPathUtils.extension(filename))]
end

return util
