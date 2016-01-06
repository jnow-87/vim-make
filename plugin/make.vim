" funcions
" 	main
"		make(target)					execute shell make, parse the output and open makeBufWindow
"		gotoFile()						read line under cursor and jump to file and line
"		makeTabSwitch()					on TabEnter check makeBufWindow status
"		makeToggle(reset)				open/close the makeBufwindow, if reset is "1" then reread the window content
"		makeCloseIfLast()				when a window is closed, close makeBufWindow if it's last remaining window in current tabpage
"
"	utils
"		parseline(line)					parse line, extract filename and linenumber
"		highlightLine(winNr, lineNr)	mark line lineNr in window winNr
"		switchWindow(bufNr)				switch to window that displays buffer bufNr if it exists
"		switchFile(filename, lineNr)	switch top line lineNr in file filename, if not displayed in any window open it
"		makeRun(target)					execute shell make with target
"
"	debug
"		makeDebugShow()					display debug messages for current vim seassion
"		makeDebug(msg)					add a message to debuglog

if exists('loaded_make')
	finish
endif

command! -nargs=? Make call s:make(<f-args>)
command! -nargs=0 MakeToggle silent call s:makeToggle(0)
"command! -nargs=0 MakeDebug silent call s:makeDebugShow()

autocmd TabEnter * silent call s:makeTabSwitch()
autocmd BufWinLeave * silent call s:makeCloseIfLast()
autocmd WinLeave * silent let lastActiveBuffer = winbufnr(0) 		" monitor each switch between windows and safe bufnr for the leaved window (used to jump back to it)
autocmd BufWinLeave __Make__ silent let s:makeIsActive = 0

highlight def link MakeHighlight mblue

let loaded_make = 1
let lastActiveBuffer = -1
let s:tmpfile = "/tmp/out"
let s:parsefile = "/tmp/parse"
let s:makeTitle = "__Make__"
let s:makeWinHeight = 7
let s:makeIsActive = 0

" debugging stuff
let s:makeDebugFile = "/tmp/make.debug"
let s:makeDebugMsg = ""
"silent! exe "!rm " . s:makeDebugFile

"function! s:makeDebugShow()
"    new makeDebug.txt
"    silent! %delete _
"    silent! 0put =s:makeDebugMsg
"    normal! gg
"	setlocal buftype=nofile
"	setlocal bufhidden=hide
"	setlocal noswapfile
"	setlocal buflisted
"endfunction

function! s:makeDebug(msg)
	if s:makeDebugFile != ""
		exe "redir >> " . s:makeDebugFile
		silent echo strftime('%H:%M:%S') . ': ' . a:msg
		redir END
	endif

	if strlen(s:makeDebugMsg) > 3000
		let s:makeDebugMsg = strpart(s:makeDebugMsg, strlen(s:makeDebugMsg) - 3000)
	endif

	let s:makeDebugMsg = s:makeDebugMsg . strftime('%H:%M:%S') . ': ' . a:msg . "\n"
endfunction

" run make for given target and display output
"
" 	call makeToggle with "1" to read the parsefile again
function! s:make(...)
"	call s:makeDebug("make()")

	if a:0 == 0
		call s:makeRun("all")
	else
		call s:makeRun(a:1)
	endif

	call s:makeToggle(1)
endfunction

" wrapper function that is called when a line is seleceted via <CR>
"
"	read, parse and highlight the current line and jump to file if necessary
" 	mappings set in makeToggle()
function! s:gotoFile()
"	call s:makeDebug("gotoFile()")

	let e = s:parseline(getline('.'))
	let curLineNr = line('.')

	if e != [-1]
		call s:highlightLine(winnr(), curLineNr)
		if s:switchFile(e[0], e[1]) == 1
			call s:makeToggle(0)
		endif

		call s:highlightLine(bufwinnr(bufnr(s:makeTitle)), curLineNr)
	endif
endfunction

" function to display makeBuffer when switching to another tabpage
" 
" 	if make is active and buffer is not displayed open them
" 	called via autocmd
function! s:makeTabSwitch()
"	call s:makeDebug("makeTabSwitch()")

	if bufwinnr(bufnr(s:makeTitle)) == -1
		if s:makeIsActive == 0
			return
		endif

		call s:makeToggle(0)
	else
		if s:makeIsActive == 1
			return
		endif

		call s:switchWindow(bufnr(s:makeTitle))
		quit
	endif
endfunction

" toggle the make buffers display mode
"
" 	if buffer is not display open a window
" 	if window already exist switch into or close if already in
" 	if reset is "1" reread buffer content (s:parsefile)
function! s:makeToggle(reset)
"	call s:makeDebug("makeToggle()")

	let makeBufNr = bufnr(s:makeTitle)

	if makeBufNr == -1
		exe "botright ". s:makeWinHeight ." split " . s:makeTitle
		silent! let text = readfile(s:parsefile)
		if text != []
			silent! 0put =text
			silent! :0
			silent! exe "!rm -f ". s:parsefile
		endif
		
		setlocal buftype=nofile
		setlocal bufhidden=hide
		setlocal noswapfile
		setlocal buflisted
		setlocal nomodifiable

		nnoremap <buffer> <silent> <CR> :call <SID>gotoFile()<CR>
		inoremap <buffer> <silent> <CR> :call <SID>gotoFile()<CR><insert>
		nnoremap <buffer> <silent> <INSERT> :call <SID>switchWindow(g:lastActiveBuffer)<CR>

		syntax match MakeHighlight '^\t\w*'

		let s:makeIsActive = 1
	else
		let r = s:switchWindow(makeBufNr)

		if r == 1 && a:reset == 0
			quit

			let s:makeIsActive = 0
		elseif r == -1
			exe "botright ". s:makeWinHeight . " split +buffer" . makeBufNr

			let s:makeIsActive = 1
		endif

		if a:reset == 1
			setlocal modifiable
			silent! %delete _
			silent! 0put =readfile(s:parsefile)
			silent! :0
			exe "silent! !rm -f " . s:parsefile
			setlocal nomodifiable
		endif
	endif
endfunction

" parse a line from makeBuffer
"
"	check if given line has format 'file:line msg'
" 	if yes return [file, line]
" 	if no return [-1]
function! s:parseline(line)
"	call s:makeDebug("parseline()")

" V1 with regex
"	if a:line =~ "[Error .]"
"		let subline = substitute(a:line, "[\t ][Error [0-9]*][\t ]", "", "g")
"		echo "err" . a:line . subline
"	elseif a:line =~ "[Warn .]"
"		let subline = substitute(a:line, "[\t ][Warn [0-9]*][\t ]", "", "g")
"		echo "warn" . a:line . subline
"	else
"		return
"	endif

"	let idx = stridx(subline, ':')
"	let filename = strpart(subline, 0, idx)
"	let lineNr = strpart(subline, idx+1, stridx(subline, ' ')-idx+1)

" V2 with split
	if a:line == ""
		return [-1]
	endif

	let linelst = split(a:line, " ")
	if get(linelst, 1, -1) != -1
		let linelst = split(linelst[0], "\t")
		let linelst = split(linelst[0], ":")

		if get(linelst, 1, -1) != -1
			return [linelst[0], linelst[1]]
	endif

	return [-1]
endfunction

" close makeBufWin if it is the last in tabpage
function! s:makeCloseIfLast()
"	call s:makeDebug("makeCloseIfLast()")

	if winnr('$') == 2
		let makeWinNr = bufwinnr(bufnr(s:makeTitle))

		if makeWinNr != -1 && makeWinNr != winnr()
			bdelete
			quit
		endif
	endif
endfunction

" highlight line lineNr in window winNr
function! s:highlightLine(winNr, lineNr)
"	call s:makeDebug("highlightLine()")

	let curWinNr = winnr()

	if a:winNr != curWinNr
		exe a:winNr . "wincmd w"
		match none
		let pat = '/\%' . a:lineNr . 'l.*/'
		exe 'match Search ' . pat
		exe curWinNr . "wincmd w"
	else
		match none
		let pat = '/\%' . a:lineNr . 'l.*/'
		exe 'match Search ' . pat
		exe ":" . a:lineNr
	endif
endfunction

" switch to window that displays buffer bufNr
" 	return	0	all ok
" 			1	current window is target window 
" 			-1	buffer not displayed in any window
function! s:switchWindow(bufNr)
"	call s:makeDebug("switchWindow()")

	let winNr = bufwinnr(a:bufNr)

	" buffer not displayed
	if winNr == -1
		return -1
	endif

	" switch to window winnr if not already in
	if winNr == winnr()
		return 1
	endif

	exe winNr . "wincmd w"
	return 0
endfunction

" switch cursor to line lineNr in  file filename
" 	return 0 if tabpage with file was already displayed
" 	return 1 if created new tabpage with file
function! s:switchFile(filename, lineNr)
"	call s:makeDebug("switchFile()")

	let bufNr = bufnr(a:filename)

	" check if buffer with file already present
	if bufNr == -1
		" no buffer present
		" so create new one
		exe "tabnew " . a:filename
		exe ":" . a:lineNr
		return 1
	else
		" buffer present
		" so check if it's displayed in one of the tabpages
		" first try to switch to window with the buffer
		if s:switchWindow(bufNr) == -1
			" no window with buffer present
			" so check all tabpages
			let i = 1
			while i <= tabpagenr('$')
                if index(tabpagebuflist(i), bufNr) != -1
					" buffer found in tabpage i
					" so first switch to tabpage i and
					" second to according window
					exe "tabnext " . i
					call s:switchWindow(bufNr)
					exe ":" . a:lineNr
					return 0
				endif

				let i += 1
			endwhile

			" if buffer not displayed in any tabpage
			" create new tab and load buffer
			if i > tabpagenr('$')
				exe "tabnew +buffer" . bufNr
				exe ":" . a:lineNr
				return 1
			endif
		endif

		exe ":" . a:lineNr
		return 0
	endif
endfunction

" run the shell make command with target an write output
" to file filename
function! s:makeRun(target)
"	call s:makeDebug("makeRun()")

	" shell script
	let script =
		\'rm -f ' . s:tmpfile . '  ' . s:parsefile . ';'
		\.'if [ \! -e Makefile ];then'
		\.'	echo -e "\tsystem (1)\n\t\tno Makefile available" > ' . s:parsefile . ';'
		\.'	exit;'
		\.'else'
		\.'	make ' . a:target . ' 1>>  ' . s:tmpfile . ' 2>> ' . s:tmpfile . ' 3>> ' . s:tmpfile . ';'
		\.'fi;'
		\
		\.'err="";'
		\.'warn="";'
		\.'sys="";'
		\.'errcnt=0;'
		\.'warncnt=0;'
		\.'syscnt=0;'
		\.'lasterrnr=0;'
		\.'lastwarnnr=0;'
		\.'lastsysnr=0;'
		\.'nlines=$(cat ' . s:tmpfile . ' | wc -l);'
		\
		\.'for (( i=1; $i<=$nlines; i++ ));do'
		\.'	line=$(more +$i ' . s:tmpfile . ' | head -n 1);'
		\
		\.'	if [ "$(echo $line | grep error)" \!= "" ] ;then'
		\.'		file=$(echo $line |cut -d ":" -f 1);'
		\.'		linenr=$(echo $line | cut -d ":" -f 2);'
		\
		\.'		if [ "$(echo $line | cut -d ":" -f 3 | tr -d " ")" == "error" ];then'
		\.'			msg=$(echo $line | cut -d ":" -f 4);'
		\.'			let errcnt=$errcnt+1;'
		\.'		else'
		\.'			errnr=$(echo $line | cut -d ":" -f 3);'
		\.'			if [ \! $lasterrnr -eq $errnr ];then'
		\.'				errcnt=$errcnt+1;'
		\.'				let lasterrnr=$errnr;'
		\.'			fi;'
		\
		\.'			text=$(echo $line | cut -d ":" -f 5);'
		\.'		fi;'
		\
		\.'		err=$err"\t\t$file:$linenr $msg\n";'
		\
		\.'	elif [ "$(echo $line | grep warning)" \!= "" ] ;then'
		\.'		file=$(echo $line | cut -d ":" -f 1);'
		\.'		linenr=$(echo $line | cut -d ":" -f 2);'
		\.'		if [ "$(echo $line |  cut -d ":" -f 3 | tr -d " ")" == "warning" ];then'
		\.'			msg=$(echo $line | cut -d ":" -f 4);'
		\.'			let warncnt=$warncnt+1;'
		\.'		else'
		\.'			warnnr=$(echo $line | cut -d ":" -f 3);'
		\.'			if [ \! $lastwarnnr -eq $warnnr ] ;then'
		\.'				let warncnt=$warncnt+1;'
		\.'				lastwarnnr=$warnnr;'
		\.'			fi;'
		\
		\.'			msg=$(echo $line | cut -d ":" -f 5);'
		\.'		fi;'
		\
		\.'		warn=$warn"\t\t$file:$linenr $msg\n";'
		\
		\.'	elif [ "$(echo "$line" | grep make)" \!= "" ];then'
		\.'		let syscnt=$syscnt+1;'
		\.'		msg=$(echo "$line" | cut -d ":" -f 2- |  tr -d "*" | tr -s " ");'
		\
		\.'		sys=$sys"\t\t"$msg"\n";'
		\.'	fi;'
		\.'done;'
		\
		\.'if [ "$err" \!= "" ];then'
		\.'	echo -e "\terror ("$errcnt")\n"$err >> ' . s:parsefile . ';'
		\.'fi;'
		\
		\.'if [ "$warn" \!= "" ];then'
		\.'	echo -e "\twarning ("$warncnt")\n"$warn >> ' . s:parsefile . ';'
		\.'fi;'
		\
		\.'if [ "$sys" \!= "" ];then'
		\.'	echo -e "\tsystem ("$syscnt")\n"$sys >> ' . s:parsefile . ';'
		\.'fi;'
		\
		\.'rm -f /tmp/out'

	exe "!" . script
endfunction
