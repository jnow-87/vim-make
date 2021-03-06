if exists('g:loaded_make') || &compatible
	finish
endif

let g:loaded_make = 1

" get own script ID
nmap <c-f11><c-f12><c-f13> <sid>
let s:sid = "<SNR>" . maparg("<c-f11><c-f12><c-f13>", "n", 0, 1).sid . "_"
nunmap <c-f11><c-f12><c-f13>


""""
"" global variables
""""
"{{{
let g:make_win_title = get(g:, "make_win_title", "make")
let g:make_win_height = get(g:, "make_win_height", 7)
let g:make_key_select = get(g:, "make_key_select", "<cr>")
"}}}

""""
"" local variables
""""
"{{{
let s:make_active = 0

let s:err_cnt = 0
let s:err_idx = -1
let s:warn_cnt = 0
let s:warn_idx = -1

"}}}

""""
"" local functions
""""
"{{{
" \brief	parse given line, extracting 'file', 'line' and 'message'
"
" \param	line	line to parse
"
" \return	[ 'file', 'line', 'message' ]
function s:parse_line(line)
	let lst = split(a:line, ':')

	if len(lst) >= 5
		" at least 5 elements expected (file, line, column, message type, message)
		return [ lst[0], lst[1], join(lst[4:]) ]

	elseif  len(lst) == 4
		" 4 elements expected (file, line, message type, message)
		return [ lst[0], lst[1], lst[3] ]
	endif

	return [ "plugin error", 0, "parsing line: \\\"" . a:line . "\\\"" ]
endfunction
"}}}

""""
"" global functions
""""
"{{{
" \brief	open/close the make buffer window
"
" \param	show	0 - close the make window
" 					1 - show the make window
function s:make_show(show)
	if a:show
		let s:make_active = 1

		" open make buffer if not already shown
		if bufwinnr("^" . g:make_win_title . "$") == -1
			exec "botright ". g:make_win_height ." split " . g:make_win_title
		endif
	else
		let s:make_active = 0

		" switch to window and close it
		if util#window#focus_window(bufwinnr("^" . g:make_win_title . "$"), -1, 0) == 0
			quit
		endif
	endif
endfunction
"}}}

"{{{
" \brief	select a line within the make window, jumping to 
function s:make_select()
	" read current line, filtering <file>:<line>
	let line = substitute(getline('.'), '^\s*\(\S*\).*', '\1', '')

	" extract filename and line number
	try
		let [ sfile, slnum ] = split(line, ':')
	catch
		return
	endtry

	" store current make window line
	let lnum = line('.')

	" make sure the make window is shown and focused
	call s:make_show(1)
	call util#window#focus_window(bufwinnr("^" . g:make_win_title . "$"), -1, 0)
	
	" highlight selected line in make buffer
	match none
	exec 'match make_select /\%' . lnum . 'l[^ \t].*/'

	" jump to selected file and line
	call util#window#focus_file(sfile, slnum, 1)

	" enter insert mode
"	call feedkeys('i')
endfunction
"}}}

"{{{
" \brief	show make window if active, keeping focus on current window
function s:make_switch_tab()
	let win = winnr()

	call s:make_show(s:make_active)
	
	if win != winnr()
		wincmd W
	endif
endfunction
"}}}

"{{{
" \brief	execute make, update and show make buffer
"
" \param	...		optional make target
function s:make_run(...)
	let s:err_cnt = 0
	let s:warn_cnt = 0
	let sys_cnt = 0

	let s:err_idx = -1
	let s:warn_idx = -1

	" execute make
	let out = system("make " . (a:0 ? a:1 : ""))

	" show and focus make window 
	call s:make_show(1)
	call util#window#focus_window(bufwinnr("^" . g:make_win_title . "$"), -1, 0)

	" reset/init buffer
	setlocal noreadonly
	setlocal modifiable

	match none
	exec "0,$delete"

	" parse make output, filtering errors, warnings and make messages
	for line in split(out, '[\r\n]')
		if stridx(line, 'error:') != -1 || stridx(line, 'Error:') != -1
			let [ file, line, msg ] = s:parse_line(line)
			call append(s:err_cnt, "\t" . file . ":" . line . "\t" . msg)
			let s:err_cnt += 1

		elseif stridx(line, 'warning:') != -1
			let [ file, line, msg ] = s:parse_line(line)
			call append(s:err_cnt + s:warn_cnt, "\t" . file . ":" . line . "\t" . msg)
			let s:warn_cnt += 1

		elseif stridx(line, 'make:') != -1 && stridx(line, '***') != -1
			let msg = split(line, '\*\*\*')[1]
			call append(s:err_cnt + s:warn_cnt + sys_cnt, "\t" . msg )
			let sys_cnt += 1
		endif
	endfor

	" put individual section headers to make buffer
	silent! 0,$foldopen
	exec "0put =' error (" . s:err_cnt . ")'"

	silent! 0,$foldopen
	exec s:err_cnt + 1 . "put =''"
	exec s:err_cnt + 2 . "put =' warnings (" . s:warn_cnt . ")'"

	silent! 0,$foldopen
	exec s:err_cnt + s:warn_cnt + 3 . "put =''"
	exec s:err_cnt + s:warn_cnt + 4 . "put =' system (" . sys_cnt . ")'"

	exec 0
	silent! 0,$foldclose
	silent! 2foldopen

	" disable make buffer modification
	setlocal readonly
	setlocal nomodifiable

	" hide make buffer if nothing to show
	if s:err_cnt + s:warn_cnt + sys_cnt == 0
		call s:make_show(0)
		echom "make succeed"
	endif
endfunction
"}}}

"{{{
" \brief	cycle through error and warning messages
"
" \param	type	message type (e: error, w: warning)
" \param	dir		direction to cycle (p: backward, n: forward)
function s:make_cycle(type, dir)
	let idx = 0

	if a:type == 'e'
		if a:dir == 'p'
			if s:err_idx > 0
				let s:err_idx -= 1
			else
				let s:err_idx = s:err_cnt - 1
			endif
		else
			if s:err_idx < s:err_cnt - 1
				let s:err_idx += 1
			else
				let s:err_idx = 0
			endif
		endif

		let idx = s:err_idx + 2

	elseif a:type == 'w'
		if a:dir == 'p'
			if s:warn_idx > 0
				let s:warn_idx -= 1
			else
				let s:warn_idx = s:warn_cnt - 1
			endif
		else
			if s:warn_idx < s:warn_cnt - 1
				let s:warn_idx += 1
			else
				let s:warn_idx = 0
			endif
		endif

		let idx = s:warn_idx + 4 + s:err_cnt
	endif

	if s:err_cnt + s:warn_cnt != 0
		call s:make_show(1)
		call util#window#focus_window(bufwinnr("^" . g:make_win_title . "$"), idx, 1)
		call s:make_select()
	endif
endfunction
"}}}

""""
"" autocommands
""""
"{{{
" init make buffer local settings
exec 'autocmd BufWinEnter ' . g:make_win_title . ' silent
	\ set filetype=makelog |
	\ setlocal noswapfile |
	\ setlocal readonly |
	\ setlocal nomodifiable |
	\ setlocal bufhidden=hide |
	\ setlocal nowrap |
	\ setlocal buftype=nofile |
	\ setlocal nobuflisted |
	\ setlocal colorcolumn=0 |
	\ setlocal foldmethod=syntax |
	\ syntax region make_content start="^\t" end="^$"me=s-1 skip="\t" fold |
	\ syntax match make_header "^ \zs\w*\ze ([0-9]*)"|
	\ call util#map#n("<insert>", "<esc>", "<buffer>")|
	\ call util#map#n("i", "<esc>", "<buffer>")|
	\ call util#map#n(g:make_key_select, ":call " . s:sid . "make_select()<cr>", "<buffer>")
	\ '

" close make buffer if its the last in the current tab
exec 'autocmd BufEnter ' . g:make_win_title . ' silent if winnr("$") == 1 | quit | endif'

" deactivate make once leaving the buffer
exec 'autocmd BufWinLeave ' . g:make_win_title . ' silent let s:make_active = 0'

" check make buffer when entering another tab
autocmd TabEnter * silent call s:make_switch_tab()
"}}}

""""
"" commands
""""
"{{{
command -nargs=? Make			call s:make_run(<f-args>)
command -nargs=0 MakeToggle		silent call s:make_show(!s:make_active)
command -nargs=+ MakeCycle		silent call s:make_cycle(<f-args>)
"}}}

""""
"" highlighting
""""
"{{{
highlight default make_header ctermfg=6
highlight default make_select ctermfg=255 ctermbg=31
"}}}
