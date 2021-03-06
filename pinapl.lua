--[[

PINAPL (pronounced "Pineapple") is the PIcaso Nano Application Platform in Lua

Presently PINAPL is a tiny application building platform for use with the gen4-uLCD-24PT
display made by 4D Systems. (Its main chip is called Picaso, hence the name.)

PINAPL depends on the 4D-Picaso.lua library by the same author to talk to the display.

Using PINAPL, you can very quickly make tiny apps in Lua that browse, view and edit
files, show menus and listboxes, use an on-screen keyboard, show dialog boxes and more.
You can opt to only use PINAPL to make things happen on the display, or you can at 
various points in your code use the commands from the display library to talk to the
display directly.

To use, make sure luars232.so, 4D-Picaso.lua and pinapl.lua are somewhere Lua can find
them

	#!/usr/bin/lua

	d = require("4D-Picaso")
	p = require("pinapl")

	p.init(d)
	
	p.dialog("Guess what?", "Hello World...", {"OK"})

]]--

-- Dependencies from global scope
local string = string
local math = math
local assert = assert
local print = print
local tostring = tostring
local tonumber = tonumber
local os = os
local ipairs = ipairs
local type = type
local io = io
local unpack = unpack
local table = table

-- We need socket.gettime() to get sub-second precision for longpress in getkeypress
--
-- If you comment this out, things will still work but longpress will take between 1 and
-- 2 seconds to register, using the one-second resolution from os.clock()
local socket = require("socket")


module(...)

--
-- Global vars. Don't change these here, you should change these defaults in your code,
-- e.g. "pinapl.scr_mode = 2" before calling pinapl.init() to start in portrait mode
--

standbytimer 	= 600		-- puts display to sleep after 10 minutes in getkeypress()
background		= "#000000"	-- black, screen background colour
scr_mode		= 0			-- Landscape orientation

-- header (Line printed in top left of screen)
hdr_height		= 30
hdr_fg			= "#FFFFFF" -- white
hdr_font 		= 2
hdr_xscale 		= 1
hdr_yscale 		= 2

-- buttons
but_fg			= "#000000" 	-- black
but_bg			= "#FFFFFF" 	-- white
but_disabled	= "#E0E0E0" 	-- light grey
but_font		= 2
but_xscale		= 1
but_yscale		= 2

-- input()
i_kbd_y			= 70			-- pixels from top keys start
i_fg			= "#00FF00"		-- green
--	i_bg			= "#000000"		-- defaults to screen background if not set
i_warn_cursor	= "#FF0000" 	-- red
i_shift_c 		= "#A0A0A0"		-- grey
i_caps_c  		= "#FFA0A0"		-- red-grey
i_font			= 2
i_xscale		= 1
i_yscale		= 2

-- list()
l_fg			= "#000000"
l_bg			= "#FFFFFF"
l_but_chrs		= 4		-- Buttons next to listbox are fixed width
l_up_txt 		= " Up "
l_dn_txt 		= "Down"

-- dialog()
d_font			= 2
d_xscale		= 1
d_yscale		= 2
d_ygap			= 0
d_fg			= "#FFFFFF"		-- white

-- viewfile() 
vf_fg		= "#FFFFFF"
vf_past_fg	= "#FFFF00"
-- vf_bg		= "#000000"		-- defaults to screen background if not set

keyboards = {}
keyboards['Normal'] = { 
	{    '1',-1,'2',-1,'3',-1,'4',-1,'5',-1,'6',-1,'7',-1,'8',-1,'9',-1,'0','<-'},
	{10, 'Q','W','E','R','T','Y','U','I','O','P'},
	{20, 'A','S','D','F','G','H','J','K','L'},
	{30, 'Z','X','C','V','B','N','M',',','.'},
	{0,  'Shift', ' |                     ', 'Sym', 'Done'} }
keyboards['Sym'] = {
	{'<','>','#','$','%','&','^','_',40,'<-'},
	{'[',']','+','-','*','=','/','\\'},
	{'{','}','`','~','|','@','.',','},
	{'(',')','"','\'',';',':','!','?'},
	{260, 'Back'} }
keyboards['Num'] = {
	{0},
	{30,'1','2','3',60,'<-| <- '},
	{30,'4','5','6'},
	{30,'7','8','9'},
	{60,'0','.', 60, 'Done'} }
keyboards['Vertical'] = {
	{    '1','2','3','4','5','6',30,'<-'},
	{    '7','8','9','0', 30,'A','B','C'},
	{    'D','E','F','G','H','I','J','K'},
	{    'L','M','N','O','P','Q','R','S'},
	{    'T','U','V','W','X','Y','Z'},
	{    '-','"',"'",'@','?','!','.',','},
	{    'Shift', ' |           ', 'Vert_Sym|Sym', 'Done'} }
keyboards['Vert_Sym'] = {
	{    '<','>','#','$','%','&',30,'<-'},
	{    '[',']','+','-','*','='},
	{    '{','}','`','~','|','@'},
	{    '(',')','"',"'",';',':'},
	{    '\\','/','_','^', 70, 'Back'} }
	
--
-- Below are the main functions for setting up the display and 
-- showing the main interface elements.
--

----------------------------------------------------------------------------------------
--	Initialise port, set display to working speed.
--	If you want to start up in portrait orientation, use "pinapl.scr_mode = 2"
--	before making the call to init
--
--	display:		a pointer to screen (as provided by 4D-Picaso.lua)
function init(display, port, initial_speed, working_speed)
	d = display
	port = port or "/dev/ttyS0"
	initial_speed = initial_speed or 9600
	working_speed = working_speed or 115200
	d.init(port, initial_speed)
	if working_speed ~= initial_speed then d.setbaudWait(working_speed) end
	d.touch_Set(0)						-- Turn on touch screen
	return screenmode(scr_mode)
end
-- returns nil

----------------------------------------------------------------------------------------
--	Tilt the screen to new mode:
--		0 = landscape
--		1 = landscape reverse
--		2 = portrait
--		3 = portrait reverse
function screenmode(mode)
	d.gfx_ScreenMode(mode)				
	scr_w  = d.gfx_Get(0) + 1			-- X_MAX
	scr_h = d.gfx_Get(1) + 1			-- Y_MAX
	scr_mode = mode
	d.gfx_Cls()
end
-- returns nil

----------------------------------------------------------------------------------------
-- Shows an input field and returns what the user types. By default, it will present a
-- QWERTY keyboard in horiz mode and an alphabetic vertical keyboard in vertical.
-- If you use 'Num' as the keyboard, a simple numeric pad will show. fixed_scale can be
-- set to always show at a given width. By default, the keyboard will show a wide
-- (xscale: 2) font when text fits and then switch to narrow (1) font when the text gets
-- too big. The user can scroll in the text by touching the left or right of the display
-- and place the cursor accordingly. The 'password' field, if set to true, makes input
-- replace typed text with stars.
function input(header, defaulttext, keyboard, maxlen, fixed_xscale, password)

	clearscreen()
	i_bg = i_bg or background
	local shifted = 1 			-- normal, no shift  (2 = shift, 3 = capslock)
	local shiftcolours = {but_bg, i_shift_c, i_caps_c}
	local txtbuf = defaulttext or ""
	local cursor = #txtbuf + 1
	local offset = -1 	-- special value that means "show last part"
	local maxlen = maxlen or 4096
	local keyboard = keyboard
	if scr_w > scr_h then
		keyboard = keyboard or "Normal"
	else
		keyboard = keyboard or "Vertical"
	end
	local previous_keyboard
	local kbd_buttons, shiftkeydata = drawkeyboard(keyboard)
	local redrawbuffer = true
	local xscale = fixed_xscale or i_xscale
	local smallfontwidth = scr_w / d.x_FontWidth(i_font)
	local windowwidth
	
	if header and #header ~= 0 then printheader(header) end

	drawcancelbutton()

	while true do

		-- Redraw text buffer if needed
		--
		if redrawbuffer then
			d.gfx_RectangleFilled(0, hdr_height, scr_w - 1, i_kbd_y - 5, i_bg)
			local text
			
			if not password then
				text = txtbuf
			else
				-- Special handling for the password stars
				text = ""
				for n = 1, #txtbuf - 1 do 
					text = text .. "*"
				end
				if defaulttext then
					text = text .. "*"
				else
					text = text .. txtbuf:sub(#txtbuf)
				end
			end
			
			text = text .. " " -- Add the space for the cursor in case it's at the end
			
			if not fixed_xscale then
				-- Auto width handling
				if #text > smallfontwidth / 2 then xscale = 1 else xscale = 2 end
			end
			windowwidth = smallfontwidth / xscale
			
			-- Handle special -1 offset when first called to at least show the end
			-- of the input. (In case of a long defaulttext) 
			if offset == -1 then 
				offset = cursor - windowwidth
				if offset < 0 then offset = 0 end
			end
			
			-- Always display the whole thing if it fits.
			if #txtbuf < windowwidth then offset = 0 end
			
			-- Do the actual output of the line
			text = text:sub(offset + 1, offset + windowwidth)
			d.gfx_MoveTo(0,35)
			d.txt_Width(xscale)
			d.txt_Height(i_yscale)
			d.txt_FontID(i_font)
			d.txt_Ygap(3) -- to make underline visible
			if defaulttext and password then
				d.txt_FGcolour(i_bg)
				d.txt_BGcolour(i_fg)
				d.putstr(text:sub(1, #text - 1))
			else
				local relcursor = cursor - offset
				local before = text:sub(1, relcursor - 1)
				local undercursor = text:sub(relcursor, relcursor)
				local after = text:sub(relcursor + 1)
				if before ~= "" then
					d.txt_FGcolour(i_fg)
					d.txt_BGcolour(i_bg)
					if offset > 0 then
						d.txt_Underline(1)
						d.putstr(before:sub(1,1))
						d.txt_Underline(0)
						before = before:sub(2)
					end
					d.putstr(before)
				end
				
				-- Text under cursor in reverse 
				d.txt_FGcolour(i_bg)
				if #txtbuf < maxlen then
					d.txt_BGcolour(i_fg)
				else
					d.txt_BGcolour(i_warn_cursor)
				end
				d.putstr(undercursor)

				if after ~= "" then 
					d.txt_FGcolour(i_fg)
					d.txt_BGcolour(i_bg)
					if offset + windowwidth < #txtbuf then
						d.putstr(after:sub(1,#after-1))
						d.txt_Underline(1)
						d.putstr(after:sub(#after))
						d.txt_Underline(0)
					else
						d.putstr(after)
					end
				end
				d.txt_Ygap(0)
			end
			
			redrawbuffer = nil
		end

		key, x, y = getkeypress (kbd_buttons)

		-- if .. elseif .. elseif .. end handling any keypresses
		--
		if keyboards[key] then
			-- If key points to new keyboard layout, show it
			shifted = 1
			previous_keyboard = keyboard
			kbd_buttons, shiftkeydata = drawkeyboard(key)
			
		elseif key == 'Back' then
			-- Return to previous keyboard, if any
			shifted = 1
			kbd_buttons, shiftkeydata = drawkeyboard(previous_keyboard)
			previous_keyboard = nil

		elseif key == 'Shift' then
			newshift = shifted + 1
			if newshift > 3 then newshift = 1 end

		elseif key == '<-' then
			if cursor > 1 then
				if shifted == 1 and not (defaulttext and password) then
					-- No shift: delete one char
					-- (But only allow this if it's not a password from defaulttext)
					txtbuf = txtbuf:sub(1, cursor-2) .. txtbuf:sub(cursor)
					cursor = cursor - 1	
					if offset > 0 then
						-- scroll if end of txtbuf in window
						if offset + windowwidth > #txtbuf then
							offset = offset - 1
						end
						-- or if on the left of screen 
						if cursor < offset + (10 * xscale) then
							offset = offset - 1
						end
					end
				else
					-- Shift-Backspace and hitting backspace on a defaulttext pw
					-- deletes everything left of cursor
					txtbuf = txtbuf:sub(cursor)
					cursor = 1
					offset = 0
					newshift = 1
					defaulttext = nil
				end
				redrawbuffer = true
			end

		elseif key == 'inwindow' then
			if not password then
				local pushed = math.floor(x / (8 * xscale))
				cursor = offset + pushed + 1
				if cursor > #txtbuf + 1 then cursor = #txtbuf + 1 end
				if pushed < 10 or pushed > windowwidth - 10 then
					offset = cursor - (windowwidth / 2)
				end
				if offset > #txtbuf + 1 - windowwidth then
					offset =  #txtbuf + 1 - windowwidth
				end
				if offset < 0 then offset = 0 end
				redrawbuffer = true
			end
						
		elseif key == 'Done' then
			if shifted == 1 then
				return txtbuf
			else
				-- on shift-Done, return the cursor position also, for line splitting etc
				return txtbuf, cursor
			end

		elseif key == 'Cancel' then
			return nil

		else
			
			-- Anything typed will delete the existing defaulttext password
			if defaulttext and password then
				txtbuf = ""
				cursor = 1
				offset = 0
				defaulttext = nil
			end
		
			if shifted == 1 then key = key:lower() end	-- lower case normally
			if shifted == 2 then newshift = 1 end		-- normal shift only for one key

			-- Add key to buffer
			for n = 1, #key do
				-- Add multi-letter keys one char at a time because maxlen
				local keyltr = key:sub(n, n)
				if #txtbuf < maxlen then
					txtbuf = txtbuf:sub(1, cursor - 1) .. keyltr .. txtbuf:sub(cursor)
					cursor = cursor + 1
					-- if cursor walks off screen, scroll along
					if cursor > offset + windowwidth then
						offset = offset + 1
					end
					redrawbuffer = true
				end
			end

		end

		-- Redraw the shift button if needed
		if newshift and shiftkeydata then
			d.gfx_Button(1, shiftkeydata[1], shiftkeydata[2], shiftcolours[newshift],
			 but_fg, 2, 1, 2, shiftkeydata[3])
			shifted = newshift
			newshift = nil
		end

	end
end

function dialog(header, text, buttons, font, xscale, yscale, ygap)

	clearscreen()

	local font = font or d_font
	local xscale = xscale or d_xscale
	local yscale = yscale or d_yscale
	local ygap = ygap or d_ygap
	
	
	-- Text
	--
	local lineheight = d.x_FontHeight(font) * yscale + ygap
	local charwidth = d.x_FontWidth(font) * xscale
	local wrapwidth = scr_w / charwidth

	local textlines = wordwrap(text, wrapwidth)
	local numlines = #textlines
	
	-- See if we can wrap a narrower block without increasing number of lines
	-- so text centers nicely
	local w = wrapwidth
	while true do
		w = w - 1
		local narrower = wordwrap(text, w)
		if #narrower <= numlines then
			textlines = narrower
		else
			break
		end
	end
	
	
	local textheight = #textlines * lineheight

	if header then printheader(header) end
		
	d.txt_FontID(font)
	d.txt_Width(xscale)
	d.txt_Height(yscale)
	d.txt_FGcolour(d_fg)
	d.txt_BGcolour(background)	
	
	-- center text vertically, around 1/2 of way down
	local y = math.floor( (scr_h / 2) - (textheight / 2) ) - lineheight
	
	for n = 1, #textlines do
		-- center each line horizontally
		local x = math.floor((wrapwidth - #textlines[n]) / 2) * charwidth
		
		d.gfx_MoveTo(x, y)
		d.putstr(textlines[n])
		y = y + lineheight
	end


	if buttons then
		-- Buttons
		--
		local buts = {}

		local but_area = scr_w / #buttons		-- max width of area for one button
		local y = math.floor(3 * (scr_h / 4))	-- buttons at 3/4 of way down
		for n = 1, #buttons do
	
			local but_width = d.x_ButtonWidth(#buttons[n], but_font, but_xscale)
			-- center each button in its own area
			x = math.floor( ( (n -1) * but_area ) + (but_area / 2) - (but_width / 2) )
	
			w, h = drawbutton(x,y,but_bg,but_fg,but_font,but_xscale,but_yscale,buttons[n])
		
			table.insert(buts, {x, y, x + w, y + h, buttons[n]})
		
		end
	
		return getkeypress(buts)
	end	

end

function listbox(header, options, longpress_time, offset,
		extra_button, no_cancel, xmargin, font, xscale, yscale, ygap)

	clearscreen()

	local xmargin = xmargin or 10
	
	local font = font or 2
	local xscale = xscale or 1
	local yscale = yscale or 2
	local ygap = ygap or 9
	local offset = offset or 1	

	local b_width = d.x_ButtonWidth(l_but_chrs, but_font, but_xscale)
	local b_height = d.x_ButtonWidth(but_font, but_yscale)
	local b_left = scr_w - b_width - 6
	local b_ex_y = scr_h - b_height - 10
	local b_dn_y = b_ex_y - b_height - 30
	local b_up_y = b_dn_y - b_height - 10

	local box_top = hdr_height
	local box_right = b_left - 6
	local avail_width = box_right - xmargin
	local avail_height = scr_h - hdr_height
	local lineheight = (d.x_FontHeight(font) * yscale) + ygap
	local screencols = math.floor( avail_width / (d.x_FontWidth(font) * xscale) )
	local screenrows = math.floor( avail_height / lineheight )
	
	-- parse the options
	local printed, returned, colour = {}, {}, {}
	for n = 1, #options do
		local o = options[n]
		if type(o) == "string" then
			printed[n] = o
			returned[n] = o
			colour[n] = l_fg
		elseif type(o) == "table" then
			printed[n] = o[2]
			returned[n] = o[3] or o[2]
			colour[n] = o[1] or l_fg
		end
	end		
	
	local y_leftover = avail_height - ( screenrows * lineheight)
	-- center lines vertically by adding half of the leftover pixels
	local ystart = math.floor( box_top + ( y_leftover / 2 ) + ( ygap / 2) )

	local redraw = true

	if header and #header ~= 0 then printheader(header) end	

	d.txt_Height(yscale)
	d.txt_Width(xscale)
	d.txt_FontID(font)
	d.txt_BGcolour(l_bg)
	local cur_fg = ""
	
	local buts = {}
	table.insert(buts, {0, box_top, box_right, scr_h - 1, 'inwindow'})

	if #options > screenrows then	
		table.insert(buts, {b_left, b_up_y, b_left + b_width, b_up_y + b_height, 'Up'})
		table.insert(buts, {b_left, b_dn_y, b_left + b_width, b_dn_y + b_height, 'Down'})
	end

	if extra_button then
		table.insert(buts, {b_left, b_ex_y, b_left + b_width, b_ex_y + b_height,
																		extra_button})
	end
	
	if not no_cancel then
		drawcancelbutton()
		table.insert(buts, {scr_w - 20, 0, scr_w - 1, 20, 'Cancel'})
	end

	while true do

		if redraw then	
			-- List box
			d.gfx_RectangleFilled(0, hdr_height, box_right, scr_h - 1, l_bg)
			local n
			for n = 0, screenrows - 1 do
				local v = offset + n
				if options[v] then
					d.gfx_MoveTo(xmargin, ystart + (n * lineheight))
					if colour[v] ~= cur_fg then
						d.txt_FGcolour(colour[v])
						cur_fg = colour[v]
					end
					d.putstr(printed[v]:sub(1, screencols) )
				end
			end
			
			-- Up/Down buttons
			if #options > screenrows then
				local up_fg, dn_fg
				if offset > 1 then up_fg = but_fg else up_fg = but_disabled end
				drawbutton (b_left, b_up_y, but_bg, up_fg, but_font, but_xscale,
																	but_yscale, l_up_txt)
				if options[offset + screenrows] then 
					dn_fg = but_fg 
				else
					dn_fg = but_disabled
				end
				drawbutton (b_left, b_dn_y, but_bg, dn_fg, but_font, but_xscale,
																	but_yscale, l_dn_txt)
			end
			
			-- extra_button
			if extra_button then
				local ex_txt = rightpad(extra_button:sub(1, l_but_chrs), " ", l_but_chrs)
				drawbutton (b_left, b_ex_y, but_bg, but_fg, but_font, but_xscale,
																	but_yscale,	 ex_txt)
			end
			
			redraw = nil
		end

		-- Parse button presses
		local key, x, y, longpress = getkeypress(buts, longpress_time)
		if key == "Cancel" then
			return
			
		elseif key == "Up" and offset > 1 then
			offset = offset - screenrows
			if offset < 1 then offset = 1 end
			redraw = true
			
		elseif key == "Down" and options[offset + screenrows] then
			offset = offset + screenrows
			redraw = true
			
		elseif key == "inwindow" then
			local selected = math.floor( (y - ystart) / lineheight)
			if selected < 0 then selected = 0 end
			if returned[offset + selected] then
				return returned[offset + selected], longpress, offset + selected, offset
			end
			
		elseif key == extra_button then
			return extra_button, longpress, 0, offset
			
		end
		
	end	
	
end

function browsefile(header, dir, longpress_time, capture, extra_button)

	local header = header or ""

	local dir = dir or "/"
	if dir:sub(#dir) ~= "/" then dir = dir .. "/" end	-- make sure dir ends in /

	local capture = capture or "/"
	if capture == true then capture = dir end

	local dispdir = dir
	if #capture > 1 then dispdir = dir:sub(#capture + 1) end
	
	while true do
	
		local d = {}
		if dir ~= capture then d[1] = {"#0000FF", ".."} end
		local ls = io.popen('ls -Ap "' .. dir  .. '"')
		for filename in ls:lines() do
			-- Make directries blue in the listbox
			if filename:sub(#filename) == "/" then
				table.insert(d, {"#0000FF", filename})
			else 
				table.insert(d, filename)
			end
		end
		ls:close()

		local filename, longpress, ptr, offset =
						listbox(header .. dispdir, d, longpress_time, nil, extra_button)
		
		-- Cancel pressed
		if not filename then return end
		
		-- extra_button pressed
		if ptr == 0 then
			return dir, nil, true
		end 
											
		
		local path
		if filename == ".." then
			-- Strip off last part
			path = dir:sub(1, dir:find("/[^/]*/$"))
		else
			path = dir .. filename
		end
		
		if path:sub(#path) == "/" and not longpress then
			return browsefile(header, path, longpress_time, capture, extra_button)
		else
			return path, true, nil
		end
	end
end

function viewfile(filename, wrapfunction, logmode, font, xscale, yscale, ygap)

	local wrapfunction = wrapfunction or wrap
	vf_bg = vf_bg or background
	clearscreen(vf_bg)

	local font = font or 2
	local xscale = xscale or 1
	local yscale = yscale or 1
	local ygap = ygap or 2
	
	d.txt_FontID(font)
	d.txt_Width(xscale)
	d.txt_Height(yscale)
	
	local lineheight = (d.x_FontHeight(font) * yscale) + ygap
	local charwidth = d.x_FontWidth(font) * xscale
	local screencols = math.floor(scr_w / charwidth )
	local screenrows = math.floor(scr_h / lineheight)

	d.txt_BGcolour(vf_bg)

	local buts = {}
	table.insert(buts, {scr_w - 20, 0, scr_w - 1, 20, 'Cancel'})
	table.insert(buts, {0, 0, scr_w - 20, scr_h / 3, 'Up'})
	table.insert(buts, {0, 2 * (scr_h / 3), scr_w - 20, scr_h - 1, 'Down'})
	
	local lines = {}
	local redraw = nil
	
	local liveview = true
	local bottomline
	local initial_done = nil	-- Do not start updating screen until all the
								-- initial lines are read (display is slooooow)
	keytimer = os.time()

	local fh = assert(io.open(filename))

	while true do
	
		-- Add new log entries to lines table, wrapped to screen width 
		local line = fh:read()
		
		if line then
			wrappedlines = wrapfunction(line, screencols)		
			if #wrappedlines > 0 then
				for n = 1, #wrappedlines do
					table.insert(lines, wrappedlines[n]:sub(1, screencols))
				end	
				if liveview then
					bottomline = #lines
					redraw = true
				end
			end
						
		else
			initial_done = true
		end
		
		-- Do the actual screen update if needed
		if redraw and initial_done then
			redraw = nil

			clearscreen(vf_bg)

			if liveview then
				d.txt_FGcolour(vf_fg)
			else
				d.txt_FGcolour(vf_past_fg)
			end
			
			local n			
			for n = screenrows - 1, 0, -1 do
				local v = bottomline - screenrows + 1 + n
				if v > 0 then
					d.gfx_MoveTo(0, n * lineheight)
					d.putstr(lines[v])
				end
			end
			drawcancelbutton()
		end
		
		-- Parse button presses
		local key, x, y = getkeypress(buts, 0, true)
		
		if key == "Cancel" then
			return
			
		elseif key == 'Up' then
			if bottomline > screenrows then
				bottomline = bottomline - screenrows
				if bottomline < screenrows then bottomline = screenrows end
				liveview = nil
				redraw = true
			end
			
		elseif key == 'Down' then
			if not liveview then
				bottomline = bottomline + screenrows
				if bottomline >= #lines then 
					bottomline = #lines
					liveview = true
				end
				redraw = true
			end
		end
		
	end
end

function editfile(filename)
	if not filename then return end
	local extra_button = nil
	local offset = 1
	local t = {}
    local file, err = io.open(filename)
    if not file then
    	dialog("Error", "Cannot read " .. err, {"OK"})
    	return
    end
    
    for line in file:lines() do
        table.insert (t, line)
    end
    file:close()
    while true do
    	local txt, ptr, longpress
	    txt, longpress, ptr, offset = 
	     listbox("Editing " .. basename(filename), t, true, offset, extra_button, nil, 2)
	    if ptr == nil then		-- Cancel pressed
	    	return
		elseif ptr == 0 then	-- extra_button ("Save") pressed
			-- Save the file
	    	local file, err = io.open(filename, "w")
			if not file then
				dialog("Error", "Cannot write to " .. err, {"OK"})
				return
			end
	    	local index, value
	    	for index, value in ipairs(t) do
	    		file:write(value .. "\n")
	    	end
	    	file:close()
	    	return true
	    else					-- A line is selected
			if longpress then
				-- show line context menu
				linecontext = listbox("#" .. ptr .. ": " .. t[ptr], 
					{"delete this line",
					"insert blank line before",
					"insert blank line after"})
				if linecontext == "delete this line" then
					local fragment = t[ptr]
					if #fragment > 30 then fragment = fragment:sub(1,30) .. "..." end
					if dialog("Delete line?", "About to delete line #" .. ptr .. ": " 
											.. fragment, {"Yes", "No"}) == "Yes" then
						table.remove(t, ptr)
						extra_button = "Save"
					end
				elseif linecontext == "insert blank line before" then
					table.insert(t, ptr, "")
					extra_button = "Save"
				elseif linecontext == "insert blank line after" then
					table.insert(t, ptr + 1, "")
					extra_button = "Save"
				end			
			else
				local tmp, split = input(basename(filename) .. " at #" .. ptr, t[ptr])
				if tmp then
					if not split then
						t[ptr] = tmp
					else
						t[ptr] = tmp:sub(1, split - 1)
						table.insert(t, ptr + 1, tmp:sub(split))
					end
					extra_button = "Save"
				end
			end
	    end
	end
end

function getkeypress(buttons, longpress_time, do_not_block)
	local buttons = buttons or {{0, 0, scr_w - 1, scr_h - 1, "OK"}}
	if longpress_time == true then
		if socket.gettime then longpress_time = 1 else longpress_time = 2 end
	end
	local longpress_time = longpress_time or 0
	
	if not do_not_block then keytimer = time() end
	
	repeat
		local longpress = nil
		if standbytimer and keytimer and time() > keytimer + standbytimer then
			sleep()
			keytimer = time()
			repeat until d.touch_Get(0) == 0	-- debounce so wake-up doesn't
			repeat until d.touch_Get(0) == 1	-- become a keypress
		end
		if d.touch_Get(0) == 1 then
			local x = d.touch_Get(1)
			local y = d.touch_Get(2)
			keytimer = time()
			
			if longpress_time > 0 then
				while d.touch_Get(0) ~= 2 do
					if time() - keytimer > longpress_time then
						longpress = true
						break
					end
				end
			end
			
			for i = 1, #buttons do
				local b = buttons[i]
				if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then
					return b[5], x, y, longpress
				end
			end
		end
	until do_not_block
end
-- Returns button_name, x, y, longpress

function sleep()
	repeat
		local timeleft = d.sys_Sleep(65535)
	until timeleft ~= 0
end

function clearscreen(colour)
	colour = colour or background
	d.gfx_RectangleFilled(0, 0, scr_w - 1, scr_h - 1, background)
end

function backlight(state)
	if state == false or state == 0 then
		d.pin_Lo(6)
	else
		d.pin_Hi(6)
	end
end

function drawcancelbutton()
	-- Cancel button top right
	d.gfx_CircleFilled(scr_w - 12, 10, 15, background)
	d.gfx_CircleFilled(scr_w - 12, 10, 10, but_bg)
	d.gfx_Line(scr_w - 18,  6, scr_w - 7, 15, but_fg)
	d.gfx_Line(scr_w - 18, 14, scr_w - 7,  5, but_fg)
	d.gfx_Line(scr_w - 17,  6, scr_w - 6, 15, but_fg)
	d.gfx_Line(scr_w - 17, 14, scr_w - 6,  5, but_fg)
end

function printheader(header)
	local maxlen = math.floor( (scr_w - 30) / (d.x_FontWidth(hdr_font) * hdr_xscale) )
	d.gfx_MoveTo(0,0)
	d.txt_Height(hdr_yscale)
	d.txt_Width(hdr_xscale)
	d.txt_FontID(hdr_font)
	d.txt_FGcolour(hdr_fg)
	d.txt_BGcolour(background)	
	d.putstr( header:sub(1,maxlen) )
end

function drawkeyboard(keyboard)

	d.gfx_RectangleFilled(0, i_kbd_y, scr_w - 1, scr_h - 1, background)
	local kbd = keyboards[keyboard]
	local buts = {}
	local shiftkeydata = nil	-- Location and text of Shift key
								-- te enable special handling of it
	local y = i_kbd_y				-- Start of keyboard on screen
	local r
	for r = 1, #kbd do
		local x = 0
		local i
		local h = 30
		for i = 1, #kbd[r] do
			local w, key, text
			key = kbd[r][i]
			if type(key) == "number" then
				-- Numbers are used for horiz spacing before/between keys 
				x = x + key
			else
				-- Look for keys in format "X|text" where X is returned and text printed
				local pipesign = key:find("|")
				if #key > 1 and pipesign then
					text = key:sub(pipesign + 1)
					key = key:sub(1, pipesign - 1)
				else
					text = key
				end
			
				-- If key text > 1 char, condense the writing on the key
				if #text == 1 then wscale = 2 else wscale = 1 end

				-- Store location of and text on Shift key
				-- for special case in key handling
				if key == 'Shift' then
					shiftkeydata = {x, y, text}
				end

				-- Draw button
				w, h = drawbutton(x, y, but_bg, but_fg, 2, wscale, 2, text)
				
				-- Register button in key array to be returned
				table.insert(buts, {x, y, x + w, y + h, key})

				x = x + w
			end
		end
		y = y + h
	end
	
	table.insert(buts, {0,  hdr_height, scr_w - 1, i_kbd_y - 5, 'inwindow'})
	table.insert(buts, {scr_w - 20, 0, scr_w - 1, 20, 'Cancel'})
	
	return buts, shiftkeydata
end

function drawbutton(x, y, bgcol, fgcol, font, xscale, yscale, text)
	d.gfx_Button(1, x, y, bgcol, fgcol, font, xscale, yscale, text)
	local width  = d.x_ButtonWidth(#text, font, xscale)
	local height = d.x_ButtonHeight(font, yscale)
	return width, height
end

function wordwrap(str, limit)
	local lines = {}
	local done = false
	repeat
		for n = limit + 1, 1, -1 do
			if str:sub(n,n) == " " then
				table.insert(lines, str:sub(1, n - 1))
				str = str:sub(n + 1)
				done = true
				break
			end
		end
		if not done then
			table.insert(lines, str:sub(1, limit))
			str = str:sub(limit + 1)
		end
		done = false
	until #str <= limit
	if #str > 0 then table.insert(lines, str) end
	return lines
end

function wrap(str, limit)
	local lines = {}
	repeat
		table.insert(lines, str:sub(1, limit))
		str = str:sub(limit + 1)
	until str == ""
	return lines
end

function cut(str, limit)
	return { str:sub(1, limit) }
end

function rightpad(string, padchar, width)
	while #string < width do
		string = string .. padchar
	end
	return string
end

function basename(path)
	return path:sub(path:find("/[^/]*$") + 1)
end

-- Returns time is seconds since epoch. In higher precision if socket library available
function time()
	if socket.gettime then
		return socket.gettime()
	else
		return os.time()
	end
end