if exists('g:loaded_make') || &compatible
	finish
endif

let g:loaded_make = 1

""""
"" global variables
""""
"{{{
let g:make_win_title = get(g:, "make_win_title", "make")
let g:make_win_height = get(g:, "make_win_height", 7)
"}}}

""""
"" local variables
""""
"{{{
let s:make_active = 0
"}}}

""""
"" helper functions
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
"" main functions
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

	" jump to selected file and line
	call util#window#focus_file(sfile, -1, 0)

	" make sure the make window is shown and focused
	call s:make_show(1)
	call util#window#focus_window(bufwinnr("^" . g:make_win_title . "$"), -1, 0)
	
	" highlight selected line in make buffer
	match none
	exec 'match Search /\%' . lnum . 'l.*/'

	" switch back previous window and select respective line
	exec "wincmd W"
	exec slnum

	" enter insert mode
	call feedkeys('i')
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
	let err_cnt = 0
	let warn_cnt = 0
	let sys_cnt = 0

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
			call append(err_cnt, "\t" . file . ":" . line . "\t" . msg)
			let err_cnt += 1

		elseif stridx(line, 'warning:') != -1
			let [ file, line, msg ] = s:parse_line(line)
			call append(err_cnt + warn_cnt, "\t" . file . ":" . line . "\t" . msg)
			let warn_cnt += 1

		elseif stridx(line, 'make:') != -1 && stridx(line, '***') != -1
			let msg = split(line, '\*\*\*')[1]
			call append(err_cnt + warn_cnt + sys_cnt, "\t" . msg )
			let sys_cnt += 1
		endif
	endfor

	" put individual section headers to make buffer
	silent! 0,$foldopen
	exec "0put =' error (" . err_cnt . ")'"

	silent! 0,$foldopen
	exec err_cnt + 1 . "put =''"
	exec err_cnt + 2 . "put =' warnings (" . warn_cnt . ")'"

	silent! 0,$foldopen
	exec err_cnt + warn_cnt + 3 . "put =''"
	exec err_cnt + warn_cnt + 4 . "put =' system (" . sys_cnt . ")'"

	exec 0
	silent! 0,$foldclose
	silent! 2foldopen

	" disable make buffer modification
	setlocal readonly
	setlocal nomodifiable

	" hide make buffer if nothing to show
	if err_cnt + warn_cnt + sys_cnt == 0
		call s:make_show(0)
		echom "make succeed"
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
	\ nnoremap <buffer> <silent> <insert> <esc>|
	\ nnoremap <buffer> <silent> i <esc>|
	\ nnoremap <buffer> <silent> <cr> :call <sid>make_select()<cr>|
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
"}}}

""""
"" highlighting
""""
"{{{
highlight default make_header ctermfg=6
"}}}
