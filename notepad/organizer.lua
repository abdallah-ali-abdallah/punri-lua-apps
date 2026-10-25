-- Common offline organizer, packaged independently in Todo and Notepad.
-- Keep these two copies identical: apps cannot read outside their own sandbox.
local editor = punri.dofile("text_editor.lua")
local MAGIC = "PUNRI_ORGANIZER_1\n"
local MAX_FILE = 32768
local FILTERS = {"All tasks", "Open tasks", "Done tasks"}

return function(config)
    local tasks = config.tasks
    local max_count = tasks and 80 or 24
    local max_title = tasks and 160 or 80
    local records, visible, page_lines, offsets = {}, {}, {}, {1}
    local selected, active, menu_selected, filter, note_page = 1, 0, 1, 1, 1
    local screen, edit_kind, edit_return, status = "list", "", "list", ""
    local w, h, margin, top, bottom, row_h, per_page, list_top, first = 0, 0, 0, 0, 0, 0, 0, 0, 1
    local note_next, read_error = 1, false
    local actions = tasks and {"Mark done / open", "Edit task", "Delete task", "Back"} or
        {"Edit text", "Rename", "Export .txt", "Delete note", "Back"}

    local function geometry()
        w, h = punri.get_bounds()
        local m = punri.get_metrics()
        margin = math.max(12, m.content_side_padding)
        top = m.top_padding + m.header_height + 12
        bottom = h - m.button_hints_height - 12
        row_h = math.max(48, punri.line_height("ui12") + 20)
        list_top = top + 44
        per_page = math.max(1, math.floor((bottom - list_top - 32) / row_h))
        first = math.floor((selected - 1) / per_page) * per_page + 1
    end

    local function rebuild()
        visible = {0} -- The first row always adds a new item.
        for i, record in ipairs(records) do
            if not tasks or filter == 1 or (filter == 2 and not record.done) or (filter == 3 and record.done) then
                visible[#visible + 1] = i
            end
        end
        selected = math.max(1, math.min(selected, #visible))
    end

    local function encode()
        local pieces = {MAGIC, tostring(#records), "\n"}
        for _, r in ipairs(records) do
            pieces[#pieces + 1] = string.format("%d:%d:%d\n", r.done and 1 or 0, #r.title, #r.body)
            pieces[#pieces + 1] = r.title
            pieces[#pieces + 1] = r.body
            pieces[#pieces + 1] = "\n"
        end
        return table.concat(pieces)
    end

    local function decode(raw)
        if #raw > MAX_FILE or raw:sub(1, #MAGIC) ~= MAGIC or raw:find("%z") then return nil end
        local end_count = raw:find("\n", #MAGIC + 1, true)
        if not end_count then return nil end
        local count_text = raw:sub(#MAGIC + 1, end_count - 1)
        if not count_text:match("^%d+$") then return nil end
        local count = tonumber(count_text)
        if not count or count > max_count then return nil end
        local decoded, at = {}, end_count + 1
        for _ = 1, count do
            local eol = raw:find("\n", at, true)
            if not eol then return nil end
            local done, nt, nb = raw:sub(at, eol - 1):match("^([01]):(%d+):(%d+)$")
            nt, nb = tonumber(nt), tonumber(nb)
            if not done or not nt or not nb or nt < 1 or nt > max_title or nb > 4096 or
                (tasks and nb ~= 0) or (not tasks and done ~= "0") then return nil end
            at = eol + 1
            if at + nt + nb > #raw or raw:sub(at + nt + nb, at + nt + nb) ~= "\n" then return nil end
            local title = raw:sub(at, at + nt - 1)
            local body = raw:sub(at + nt, at + nt + nb - 1)
            if title:find("[\r\n]") or not title:find("%S") or not editor.valid_text(title) or
                not editor.valid_text(body) then return nil end
            decoded[#decoded + 1] = {title = title, body = body, done = done == "1"}
            at = at + nt + nb + 1
        end
        if at ~= #raw + 1 then return nil end
        return decoded
    end

    local function persist()
        local raw = encode()
        if #raw > MAX_FILE then
            status = "Storage limit reached (32 KB)"
            return false
        end
        -- write_file returns a result; save() does not, so use the transactional file API.
        if not punri.write_file("items.dat", raw) then
            status = "SD save failed. Retry before exiting."
            punri.log(config.name .. ": SD save failed")
            return false
        end
        status = "Saved to SD card"
        return true
    end

    local function note_layout()
        geometry()
        local count = math.max(1, math.floor((bottom - list_top - 68) / (punri.line_height("ui12") + 4)))
        page_lines, note_next = editor.lines(records[active].body, w - margin * 2 - 16,
            count, offsets[note_page], "ui12")
    end

    local function open_record(index)
        active, menu_selected = index, 1
        if tasks then
            screen = "menu"
        else
            screen, note_page, offsets = "note", 1, {1}
            note_layout()
        end
    end

    local function start_edit(kind, return_to)
        edit_kind, edit_return, screen, status = kind, return_to, "editor", ""
        local label, initial, cap, multiline = "", "", max_title, false
        if kind == "new" then label = tasks and "New task" or "Note title"
        elseif kind == "title" then label, initial = tasks and "Edit task" or "Rename note", records[active].title
        else label, initial, cap, multiline = "Edit note", records[active].body, 4096, true end
        editor.open(label, initial, cap, multiline)
    end

    local function finish_edit(result, value)
        if result == "cancel" then screen = edit_return; return end
        if result ~= "save" then return end
        if edit_kind ~= "body" then
            value = value:gsub("^%s+", ""):gsub("%s+$", "")
            if value == "" then status = "Enter a title first"; return end
        end
        if edit_kind == "new" then
            records[#records + 1] = {title = value, body = "", done = false}
            if not persist() then records[#records] = nil; return end
            active = #records
            rebuild()
            if tasks then screen = "list"
            else note_page, offsets = 1, {1}; start_edit("body", "note") end
        else
            local r = records[active]
            local field = edit_kind == "body" and "body" or "title"
            local old = r[field]
            if value ~= old then
                r[field] = value
                if not persist() then r[field] = old; return end
            end
            screen = edit_return
        end
        if screen == "note" then note_page, offsets = 1, {1}; note_layout() end
    end

    local function activate_menu()
        if tasks then
            if menu_selected == 1 then
                local r = records[active]
                r.done = not r.done
                if not persist() then r.done = not r.done; return end
                screen = "list"
                rebuild()
            elseif menu_selected == 2 then start_edit("title", "menu")
            elseif menu_selected == 3 then screen, menu_selected = "delete", 1
            else screen = "list" end
        else
            if menu_selected == 1 then start_edit("body", "note")
            elseif menu_selected == 2 then start_edit("title", "note")
            elseif menu_selected == 3 then
                -- Pick an unused numeric name: exporting/deleting never replaces an older export.
                local path
                for i = 1, 999 do
                    local candidate = string.format("exports/note_%03d.txt", i)
                    if not punri.file_exists(candidate) then path = candidate; break end
                end
                if not path then status = "Export limit reached (999 files)"; return end
                local r = records[active]
                if punri.write_file(path, r.title .. "\n\n" .. r.body .. "\n") then
                    status = "Exported: " .. path
                else
                    status = "SD export failed. Retry."
                    punri.log(config.name .. ": SD export failed")
                end
            elseif menu_selected == 4 then screen, menu_selected = "delete", 1
            else screen = "note"; note_layout() end
        end
    end

    local function delete_record()
        local old = table.remove(records, active)
        if not persist() then table.insert(records, active, old); return end
        active, screen = 0, "list"
        rebuild()
    end

    local function move(delta, count)
        menu_selected = (menu_selected - 1 + delta) % count + 1
    end

    local function turn_page(delta)
        if delta < 0 and note_page > 1 then note_page = note_page - 1; note_layout()
        elseif delta > 0 and note_next <= #records[active].body then
            offsets[note_page + 1] = note_next
            note_page = note_page + 1
            note_layout()
        end
    end

    local function draw_row(y, label, chosen)
        punri.rounded_rect(margin, y + 2, w - margin * 2, row_h - 4, 6, chosen)
        punri.text(margin + 12, y + 10, editor.clip(label, w - margin * 2 - 24),
            "ui12", "regular", "left", not chosen)
    end

    function on_init()
        geometry()
        local raw = punri.read_file("items.dat", MAX_FILE + 1)
        if raw ~= nil then
            local decoded = decode(raw)
            if decoded then records = decoded else read_error = true end
        elseif punri.file_exists("items.dat") then
            read_error = true
        end
        if read_error then
            status = "Cannot read saved data. File left untouched."
            punri.log(config.name .. ": invalid or unreadable items.dat; refusing to overwrite")
        end
        rebuild()
    end

    function on_draw()
        geometry()
        if screen == "editor" then
            editor.draw()
            if status ~= "" then punri.popup(status) end
            return
        end
        punri.clear()
        punri.header(config.name, tasks and tostring(#records) .. "/80" or tostring(#records) .. "/24")
        local label_x = margin
        if punri.has_touch() then
            punri.rounded_rect(margin, top, 80, 34, 4, false)
            punri.text(margin + 40, top + 5, screen == "list" and "Exit" or "Back", "ui10", "regular", "center")
            label_x = margin + 92
        end
        if read_error then
            punri.centered_text(top + 40, "Saved data unavailable", "ui12", "bold")
            punri.centered_text(top + 80, "Back up items.dat and check the SD card.", "small")
            punri.centered_text(top + 112, "The app will not replace your data.", "small")
            punri.button_hints("Exit", "", "", "")
            return
        end
        if screen == "list" then
            local label = tasks and FILTERS[filter] .. (punri.has_touch() and " (tap to filter)" or " (side: filter)") or
                "Select a note to read or edit"
            punri.text(label_x, top + 6, editor.clip(label, w - margin - label_x, "small"), "small")
            for i = first, math.min(#visible, first + per_page - 1) do
                local index = visible[i]
                local label = tasks and "+ Add task" or "+ New note"
                if index ~= 0 then
                    local r = records[index]
                    label = tasks and ((r.done and "[x] " or "[ ] ") .. r.title) or r.title
                end
                draw_row(list_top + (i - first) * row_h, label, i == selected)
            end
            if #visible == 1 then
                punri.centered_text(list_top + row_h + 18, tasks and "No tasks in this view" or "No notes yet", "small")
            end
            punri.button_hints("Exit", "Select", "Up", "Down")
        elseif screen == "note" then
            note_layout()
            if punri.has_touch() then
                punri.rounded_rect(w - margin - 100, top, 100, 34, 4, false)
                punri.text(w - margin - 50, top + 5, "Actions", "ui10", "regular", "center")
            end
            punri.text(margin, list_top, editor.clip(records[active].title, w - margin * 2, "ui12"), "ui12", "bold")
            local line_h = punri.line_height("ui12") + 4
            if #page_lines == 0 then page_lines[1] = "Empty note. Select Actions to edit." end
            for i, line in ipairs(page_lines) do punri.text(margin + 8, list_top + 36 + (i - 1) * line_h, line, "ui12") end
            punri.button_hints("Back", "Actions", "Prev", "Next")
        else
            punri.text(label_x, top + 6, editor.clip(records[active].title, w - margin - label_x), "ui12", "bold")
            if screen == "delete" then
                draw_row(list_top, "Keep it", menu_selected == 1)
                draw_row(list_top + row_h, "Delete permanently", menu_selected == 2)
            else
                for i, label in ipairs(actions) do
                    if tasks and i == 1 then label = records[active].done and "Mark open" or "Mark done" end
                    draw_row(list_top + (i - 1) * row_h, label, i == menu_selected)
                end
            end
            punri.button_hints("Back", "Select", "Up", "Down")
        end
        local footer = status
        if footer == "" then
            footer = screen == "note" and ("Page " .. tostring(note_page)) or
                ("Page " .. tostring(math.floor((selected - 1) / per_page) + 1) .. "/" ..
                tostring(math.ceil(#visible / per_page)))
        end
        punri.text(margin, bottom - 20, editor.clip(footer, w - margin * 2, "small"), "small")
    end

    function on_button(btn, pressed)
        if not pressed then return end
        if read_error then if btn == "back" then punri.exit() end; return end
        status = ""
        if screen == "editor" then
            finish_edit(editor.button(btn))
        elseif screen == "list" then
            if btn == "back" then punri.exit()
            elseif btn == "confirm" then
                if visible[selected] == 0 then
                    if #records >= max_count then status = "Item limit reached. Delete an item first."
                    else start_edit("new", "list") end
                else open_record(visible[selected]) end
            elseif btn == "left" then selected = (selected - 2) % #visible + 1
            elseif btn == "right" then selected = selected % #visible + 1
            elseif btn == "up" or btn == "page_back" then
                if tasks then filter = (filter - 2) % 3 + 1; selected = 1; rebuild()
                else selected = math.max(1, selected - per_page) end
            elseif btn == "down" or btn == "page_forward" then
                if tasks then filter = filter % 3 + 1; selected = 1; rebuild()
                else selected = math.min(#visible, selected + per_page) end
            end
        elseif screen == "note" then
            if btn == "back" then screen = "list"
            elseif btn == "confirm" then screen, menu_selected = "menu", 1
            elseif btn == "left" or btn == "up" or btn == "page_back" then turn_page(-1)
            elseif btn == "right" or btn == "down" or btn == "page_forward" then turn_page(1) end
        else
            local count = screen == "delete" and 2 or #actions
            if btn == "back" then
                if screen == "delete" then screen, menu_selected = "menu", 1
                else screen = tasks and "list" or "note" end
            elseif btn == "left" or btn == "up" or btn == "page_back" then move(-1, count)
            elseif btn == "right" or btn == "down" or btn == "page_forward" then move(1, count)
            elseif btn == "confirm" then
                if screen == "delete" then
                    if menu_selected == 2 then delete_record() else screen, menu_selected = "menu", 1 end
                else activate_menu() end
            end
        end
        punri.request_update()
    end

    function on_tap(x, y)
        geometry()
        -- Firmware owns button hints and the reserved Back swipe; do not add hidden footer targets.
        if screen ~= "editor" and punri.has_touch() and punri.in_rect(x, y, margin, top, 80, 34) then
            on_button("back", true)
            return
        end
        if read_error or y < top or y >= bottom then return end
        status = ""
        if screen == "editor" then
            finish_edit(editor.tap(x, y))
        elseif screen == "list" then
            if tasks and y < list_top and x >= margin and x < w - margin then filter = filter % 3 + 1; selected = 1; rebuild()
            elseif x >= margin and x < w - margin and y >= list_top then
                local i = first + math.floor((y - list_top) / row_h)
                if i <= #visible and i < first + per_page then selected = i; on_button("confirm", true) end
            end
        elseif screen == "note" then
            if y >= list_top + 36 then turn_page(x < w / 2 and -1 or 1)
            elseif punri.in_rect(x, y, w - margin - 100, top, 100, 34) then screen, menu_selected = "menu", 1 end
        elseif x >= margin and x < w - margin and y >= list_top then
            local i = math.floor((y - list_top) / row_h) + 1
            local count = screen == "delete" and 2 or #actions
            if i <= count then menu_selected = i; on_button("confirm", true) end
        end
        punri.request_update()
    end

    function on_swipe(direction)
        if read_error or screen == "editor" then return end
        if screen == "list" then
            if direction == "up" then selected = math.min(#visible, selected + per_page)
            elseif direction == "down" then selected = math.max(1, selected - per_page) end
        elseif screen == "note" then
            if direction == "left" then turn_page(1)
            elseif direction == "right" then turn_page(-1) end
        end
        punri.request_update()
    end

    function on_exit()
        -- Committed changes are already synced. Never overwrite state on exit,
        -- especially after a failed read or while an uncommitted editor is open.
    end
end
