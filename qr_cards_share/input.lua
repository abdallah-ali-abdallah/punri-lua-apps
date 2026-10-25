-- One input path per action: main.lua deliberately registers on_tap only.
-- LuaAppActivity invokes both on_tap() and on_touch(..., "tap") for one touch.
-- Defining on_tap alone prevents the same action from running twice.

local Input = {}

local function redraw()
    if punri.request_update then punri.request_update() end
end

local function set_sleep(enabled)
    if punri.has_feature and punri.has_feature("prevent_sleep") and punri.prevent_sleep then punri.prevent_sleep(enabled) end
end

local function leave_qr(app)
    app.qr = nil
    set_sleep(false)
    collectgarbage("collect")
end

local function copy_cards(cards)
    local result = {}
    for i, card in ipairs(cards) do result[i] = Cards.copy(card) end
    return result
end

local function save_cards(app, next_cards)
    local ok, message = Storage.save(next_cards)
    if not ok then
        app.notice = message
        return false
    end
    app.cards = next_cards
    app.data_error = nil
    app.notice = "Saved to the SD card."
    return true
end

local function selected_card(app) return app.cards[app.selection] end

local function normalise_selection(app)
    if #app.cards == 0 then app.selection = 1 else app.selection = math.max(1, math.min(#app.cards, app.selection)) end
end

local function enter_preview(app)
    if #app.cards == 0 then app.notice = "Create a card first."; return end
    normalise_selection(app)
    app.screen = "preview"
    app.notice = nil
end

local function begin_form(app, kind, source)
    if not punri.has_feature or not punri.has_feature("keyboard") or not punri.keyboard then
        app.notice = "This app needs firmware keyboard support to edit cards."
        return
    end
    app.draft = source and Cards.copy(source) or Cards.new(kind)
    app.edit_index = source and app.selection or nil
    app.form_index, app.pending_field = 1, nil
    app.screen = "form"
    app.notice = nil
end

local function show_qr(app)
    local card = selected_card(app)
    if not card then return end
    local ok, message, payload = Cards.validate(card, QR)
    if not ok then app.notice = message; return end
    if not payload then app.notice = "This emergency card has no QR contact yet."; return end
    if card.type == "wifi" then
        app.screen = "wifi_privacy"
        app.notice = nil
        return
    end
    local code, error = QR.encode(payload)
    if not code then app.notice = error; return end
    app.qr, app.screen, app.notice = code, "qr", nil
    set_sleep(true)
end

local function finish_wifi_share(app)
    local payload = Cards.payload(selected_card(app))
    local code, error = payload and QR.encode(payload) or nil, "No Wi-Fi payload"
    if not code then app.notice = error; app.screen = "preview"; return end
    app.qr, app.screen, app.notice = code, "qr", nil
    set_sleep(true)
end

local function save_draft(app)
    local valid, message = Cards.validate(app.draft, QR)
    if not valid then app.notice = message; return end
    app.draft.modified = Cards.modified_now()
    local next = copy_cards(app.cards)
    if app.edit_index then next[app.edit_index] = Cards.copy(app.draft) else next[#next + 1] = Cards.copy(app.draft) end
    if #next > Cards.MAX_CARDS then app.notice = "The library limit is 12 cards."; return end
    if save_cards(app, next) then
        if not app.edit_index then app.selection = #next end
        app.draft, app.edit_index, app.pending_field = nil, nil, nil
        app.screen = "preview"
    end
end

local function delete_selected(app)
    if not app.confirm_delete then
        app.screen = app.return_screen or "preview"
        app.notice = "Kept the card."
        return
    end
    local next = copy_cards(app.cards)
    table.remove(next, app.selection)
    if save_cards(app, next) then
        normalise_selection(app)
        app.confirm_delete, app.return_screen = false, nil
        leave_qr(app)
        app.screen = "library"
    end
end

local function action(app, index)
    local card = selected_card(app)
    if index == 1 then enter_preview(app)
    elseif index == 2 then app.screen = "type"; app.notice = nil
    elseif index == 3 then if card then begin_form(app, card.type, card) else app.notice = "Select a card first." end
    elseif index == 4 then
        if card then app.confirm_delete, app.return_screen, app.screen, app.notice = false, "actions", "confirm_delete", nil end
    elseif index == 5 or index == 6 then
        if not card then app.notice = "Select a card first."; return end
        local other = index == 5 and app.selection - 1 or app.selection + 1
        if other < 1 or other > #app.cards then app.notice = "Card is already at that end."; return end
        local next = copy_cards(app.cards)
        next[app.selection], next[other] = next[other], next[app.selection]
        if save_cards(app, next) then app.selection = other end
    elseif index == 7 then app.screen, app.notice = "privacy", nil
    else app.screen, app.notice = "library", nil end
end

local function keyboard_for_current_field(app)
    local fields = Cards.field_names(app.draft.type)
    local field = fields[app.form_index]
    if not field then return end
    local title = Cards.display_field(field)
    if not punri.keyboard(title, app.draft.fields[field], Cards.field_limit(field), false) then
        app.notice = "Could not open the keyboard. Try again."
        return
    end
    app.pending_field = field
    app.notice = nil
end

function Input.keyboard_result(app, value, cancelled)
    local field = app.pending_field
    app.pending_field = nil
    if app.screen ~= "form" or not field then return end
    if cancelled then app.notice = "Edit cancelled; the draft was not changed."
    elseif not Cards.valid_field(field, value) then app.notice = "That value is too long or contains unsupported characters."
    else
        app.draft.fields[field] = value
        local total = #Cards.field_names(app.draft.type)
        if app.form_index < total then app.form_index = app.form_index + 1 end
        app.notice = nil
    end
    redraw()
end

local function handle_target(app, target)
    if not target then return end
    local kind, value = target:match("^([^:]+):?(.*)$")
    if kind == "open" then app.selection = tonumber(value); enter_preview(app)
    elseif kind == "new" then app.screen, app.notice = "type", nil
    elseif kind == "actions" then app.screen, app.notice = "actions", nil
    elseif kind == "type" then begin_form(app, value)
    elseif kind == "action" then app.action_selection = tonumber(value); action(app, app.action_selection)
    elseif kind == "show_qr" then show_qr(app)
    elseif kind == "field" then app.form_index = tonumber(value); keyboard_for_current_field(app)
    elseif kind == "keep" then app.confirm_delete = false; delete_selected(app)
    elseif kind == "delete" then app.confirm_delete = true; delete_selected(app)
    elseif kind == "privacy_continue" then finish_wifi_share(app)
    elseif kind == "done_qr" then leave_qr(app); app.screen, app.notice = "preview", nil end
    redraw()
end

function Input.tap(app, x, y)
    handle_target(app, UI.hit(x, y))
end

function Input.button(app, button)
    if app.screen == "library" then
        if button == "back" then punri.exit(); return end
        if button == "confirm" then enter_preview(app)
        elseif button == "left" or button == "page_back" then app.selection = app.selection - 1; normalise_selection(app)
        elseif button == "right" or button == "page_forward" then app.selection = app.selection + 1; normalise_selection(app)
        elseif button == "up" then app.screen = "actions"
        elseif button == "down" then app.screen = "type"; app.notice = nil end
    elseif app.screen == "type" then
        if button == "back" then app.screen = "library"
        elseif button == "left" or button == "up" or button == "page_back" then app.type_selection = math.max(1, app.type_selection - 1)
        elseif button == "right" or button == "down" or button == "page_forward" then app.type_selection = math.min(#Cards.types, app.type_selection + 1)
        elseif button == "confirm" then begin_form(app, Cards.types[app.type_selection].id) end
    elseif app.screen == "actions" then
        if button == "back" then app.screen = "library"
        elseif button == "left" or button == "up" or button == "page_back" then app.action_selection = math.max(1, app.action_selection - 1)
        elseif button == "right" or button == "down" or button == "page_forward" then app.action_selection = math.min(8, app.action_selection + 1)
        elseif button == "confirm" then action(app, app.action_selection) end
    elseif app.screen == "preview" then
        if button == "back" then app.screen = "library"
        elseif button == "confirm" then show_qr(app)
        elseif button == "left" then begin_form(app, selected_card(app).type, selected_card(app))
        elseif button == "right" or button == "up" then app.screen = "actions" end
    elseif app.screen == "form" then
        local total = #Cards.field_names(app.draft.type)
        if button == "back" then app.draft, app.pending_field, app.screen, app.notice = nil, nil, "library", "Draft discarded."
        elseif button == "confirm" then keyboard_for_current_field(app)
        elseif button == "left" or button == "up" or button == "page_back" then app.form_index = math.max(1, app.form_index - 1)
        elseif button == "right" or button == "down" or button == "page_forward" then
            if app.form_index < total then app.form_index = app.form_index + 1 else save_draft(app) end
        end
    elseif app.screen == "confirm_delete" then
        if button == "back" then app.screen = app.return_screen or "preview"; app.notice = "Kept the card."
        elseif button == "left" or button == "page_back" then app.confirm_delete = false
        elseif button == "right" or button == "page_forward" then app.confirm_delete = true
        elseif button == "confirm" then delete_selected(app) end
    elseif app.screen == "privacy" then
        if button == "back" or button == "confirm" then app.screen = "actions" end
    elseif app.screen == "wifi_privacy" then
        if button == "back" then app.screen = "preview" elseif button == "confirm" then finish_wifi_share(app) end
    elseif app.screen == "qr" then
        if button == "back" or button == "confirm" then leave_qr(app); app.screen = "preview"
        elseif button == "left" and selected_card(app).type == "wifi" then app.confirm_delete, app.return_screen, app.screen = false, "qr", "confirm_delete" end
    end
    redraw()
end

return Input
