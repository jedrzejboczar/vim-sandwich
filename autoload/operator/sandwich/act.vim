" act object - editing buffer

" variables "{{{
" null valiables
let s:null_pos   = [0, 0, 0, 0]
let s:null_4pos  = {
      \   'head1': copy(s:null_pos),
      \   'tail1': copy(s:null_pos),
      \   'head2': copy(s:null_pos),
      \   'tail2': copy(s:null_pos),
      \ }

" types
let s:type_str = type('')

" features
let s:has_gui_running = has('gui_running')
"}}}

function! operator#sandwich#act#new() abort "{{{
  return deepcopy(s:act)
endfunction
"}}}

" s:act "{{{
let s:act = {
      \   'cursor' : {},
      \   'modmark': {},
      \   'opt'    : {},
      \   'success': 0,
      \   'added'  : [],
      \ }
"}}}
function! s:act.initialize(cursor, modmark, added, message) dict abort  "{{{
  let self.cursor  = a:cursor
  let self.modmark = a:modmark
  let self.opt     = {}
  let self.added   = a:added
  let self.success = 0
  let self.message = a:message
endfunction
"}}}
function! s:act.add_pair(buns, stuff, undojoin) dict abort "{{{
  let target  = a:stuff.target
  let edges   = a:stuff.edges
  let modmark = self.modmark
  let opt     = self.opt
  let indent  = [0, 0]
  let is_linewise = [0, 0]

  if s:is_valid_4pos(target) && s:is_equal_or_ahead(target.head2, target.head1)
    if target.head2[2] != col([target.head2[1], '$'])
      let target.head2[0:3] = s:get_right_pos(target.head2)
    endif

    let indentopt = s:set_indent(opt)
    try
      let pos = target.head1
      let [is_linewise[0], indent[0], head1, tail1] = s:add_former(a:buns, pos, opt, a:undojoin)
      let pos = s:push1(copy(target.head2), target, a:buns, indent, is_linewise)
      let [is_linewise[1], indent[1], head2, tail2] = s:add_latter(a:buns, pos, opt)
    catch /^Vim\%((\a\+)\)\=:E21/
      call self.message.notice.queue(['Cannot make changes to read-only buffer.', 'WarningMsg'])
      throw 'OperatorSandwichError:ReadOnly'
    finally
      call s:restore_indent(indentopt)
    endtry
    let [mod_head, mod_tail] = s:execute_command(head1, tail2, opt.of('command'))

    if opt.of('highlight', '') >= 3
      call map(self.added, 's:shift_added("s:shift_for_add", v:val, target, a:buns, indent, is_linewise)')
      call add(self.added, {
            \   'head1': head1,
            \   'tail1': s:get_left_pos(tail1),
            \   'head2': head2,
            \   'tail2': s:get_left_pos(tail2),
            \   'linewise': is_linewise
            \ })
    endif

    " update modmark
    if modmark.head == s:null_pos || s:is_ahead(modmark.head, mod_head)
      let modmark.head = mod_head
    endif
    if modmark.tail == s:null_pos
      let modmark.tail = mod_tail
    else
      call s:shift_for_add(modmark.tail, target, a:buns, indent, is_linewise)
      if s:is_ahead(mod_tail, modmark.tail)
        let modmark.tail = mod_tail
      endif
    endif

    " update cursor positions
    call s:shift_for_add(self.cursor.inner_head, target, a:buns, indent, is_linewise)
    call s:shift_for_add(self.cursor.keep,       target, a:buns, indent, is_linewise)
    call s:shift_for_add(self.cursor.inner_tail, target, a:buns, indent, is_linewise)

    " update next target positions
    let edges.head = copy(head1)
    let edges.tail = s:get_left_pos(tail2)

    let self.success = 1
  endif
  return self.success
endfunction
"}}}
function! s:act.delete_pair(stuff, modified) dict abort  "{{{
  let target  = a:stuff.target
  let edges   = a:stuff.edges
  let modmark = self.modmark
  let opt     = self.opt

  if s:is_valid_4pos(target) && s:is_ahead(target.head2, target.tail1)
    let reg = ['"', getreg('"'), getregtype('"')]
    let deletion = ['', '']
    let is_linewise = [0, 0]
    try
      let former_head = target.head1
      let former_tail = target.tail1
      let latter_head = target.head2
      let [deletion[0], is_linewise[0], head] = s:delete_former(former_head, former_tail, latter_head, opt)

      let latter_head = s:pull1(copy(target.head2), target, deletion, is_linewise)
      let latter_tail = s:pull1(copy(target.tail2), target, deletion, is_linewise)
      let [deletion[1], is_linewise[1], tail] = s:delete_latter(latter_head, latter_tail, former_head, opt)
    catch /^Vim\%((\a\+)\)\=:E21/
      call self.message.notice.queue(['Cannot make changes to read-only buffer.', 'WarningMsg'])
      throw 'OperatorSandwichError:ReadOnly'
    finally
      call call('setreg', reg)
    endtry
    let [mod_head, mod_tail] = s:execute_command(head, tail, opt.of('command'))

    " update modmark
    if modmark.head == s:null_pos || s:is_ahead(modmark.head, mod_head)
      let modmark.head = mod_head
    endif
    " NOTE: Probably, there is no possibility to delete breakings along multiple acts.
    if !a:modified
      if modmark.tail == s:null_pos
        let modmark.tail = mod_tail
      else
        call s:shift_for_delete(modmark.tail, target, deletion, is_linewise)
        if mod_tail[1] >= modmark.tail[1]
          let modmark.tail = mod_tail
        endif
      endif
    endif

    " update cursor positions
    call s:shift_for_delete(self.cursor.inner_head, target, deletion, is_linewise)
    call s:shift_for_delete(self.cursor.keep,       target, deletion, is_linewise)
    call s:shift_for_delete(self.cursor.inner_tail, target, deletion, is_linewise)

    " update target positions
    let edges.head = copy(head)
    let edges.tail = s:get_left_pos(tail)

    let self.success = 1
  endif
  return self.success
endfunction
"}}}
function! s:act.replace_pair(buns, stuff, undojoin, modified) dict abort "{{{
  let target  = a:stuff.target
  let edges   = a:stuff.edges
  let modmark = self.modmark
  let opt     = self.opt

  if s:is_valid_4pos(target) && s:is_ahead(target.head2, target.tail1)
    set virtualedit=
    let next_head = s:get_right_pos(target.tail1)
    let next_tail = s:get_left_pos(target.head2)
    set virtualedit=onemore

    let reg         = ['"', getreg('"'), getregtype('"')]
    let deletion    = ['', '']
    let indent      = [0, 0]
    let is_linewise = [0, 0]
    let indentopt   = s:set_indent(opt)
    try
      let within_a_line = target.tail1[1] == target.head2[1]
      let former_head = target.head1
      let former_tail = target.tail1
      let latter_head = copy(target.head2)
      let latter_tail = copy(target.tail2)
      let [deletion[0], is_linewise[0], indent[0], head1, tail1] = s:replace_former(a:buns[0], former_head, former_tail, within_a_line, opt, a:undojoin)

      call s:pull1(latter_head, target, deletion, is_linewise)
      call s:push1(latter_head, target, a:buns, indent, is_linewise)
      call s:pull1(latter_tail, target, deletion, is_linewise)
      call s:push1(latter_tail, target, a:buns, indent, is_linewise)
      let [deletion[1], is_linewise[1], indent[1], head2, tail2] = s:replace_latter(a:buns[1], latter_head, latter_tail, within_a_line, opt)
    catch /^Vim\%((\a\+)\)\=:E21/
      call self.message.notice.queue(['Cannot make changes to read-only buffer.', 'WarningMsg'])
      throw 'OperatorSandwichError:ReadOnly'
    finally
      call call('setreg', reg)
      call s:restore_indent(indentopt)
    endtry
    let [mod_head, mod_tail] = s:execute_command(head1, tail2, opt.of('command'))

    if opt.of('highlight', '') >= 3
      call map(self.added, 's:shift_added("s:shift_for_replace", v:val, target, a:buns, deletion, indent, is_linewise)')
      call add(self.added, {
            \   'head1': head1,
            \   'tail1': s:get_left_pos(tail1),
            \   'head2': head2,
            \   'tail2': s:get_left_pos(tail2),
            \   'linewise': is_linewise
            \ })
    endif

    " update modmark
    if modmark.head == s:null_pos || s:is_ahead(modmark.head, mod_head)
      let modmark.head = copy(mod_head)
    endif
    if !a:modified
      if modmark.tail == s:null_pos
        let modmark.tail = copy(mod_tail)
      else
        call s:shift_for_replace(modmark.tail, target, a:buns, deletion, indent, is_linewise)
        if modmark.tail[1] < mod_tail[1]
          let modmark.tail = copy(mod_tail)
        endif
      endif
    endif

    " update cursor positions
    call s:shift_for_replace(self.cursor.keep, target, a:buns, deletion, indent, is_linewise)
    call s:shift_for_replace(next_head, target, a:buns, deletion, indent, is_linewise)
    call s:shift_for_replace(next_tail, target, a:buns, deletion, indent, is_linewise)
    if self.cursor.inner_head == s:null_pos || target.head1[1] <= self.cursor.inner_head[1]
      let self.cursor.inner_head = copy(next_head)
    endif
    if self.cursor.inner_tail == s:null_pos
      let self.cursor.inner_tail = copy(next_tail)
    else
      call s:shift_for_replace(self.cursor.inner_tail, target, a:buns, deletion, indent, is_linewise)
      if self.cursor.inner_tail[1] <= next_tail[1]
        let self.cursor.inner_tail = copy(next_tail)
      endif
    endif

    " update target positions
    let edges.head = next_head
    let edges.tail = next_tail

    let self.success = 1
  endif
  return self.success
endfunction
"}}}

" private functions
function! s:set_indent(opt) abort "{{{
  let indentopt = {
        \   'autoindent': {
        \     'restore': 0,
        \     'value'  : [&l:autoindent, &l:smartindent, &l:cindent, &l:indentexpr],
        \   },
        \   'indentkeys': {
        \     'restore': 0,
        \     'name'   : '',
        \     'value'  : '',
        \   },
        \ }

  " set autoindent options
  if a:opt.of('autoindent') == 0
    let [&l:autoindent, &l:smartindent, &l:cindent, &l:indentexpr] = [0, 0, 0, '']
    let indentopt.autoindent.restore = 1
  elseif a:opt.of('autoindent') == 1
    let [&l:autoindent, &l:smartindent, &l:cindent, &l:indentexpr] = [1, 0, 0, '']
    let indentopt.autoindent.restore = 1
  elseif a:opt.of('autoindent') == 2
    " NOTE: 'Smartindent' requires 'autoindent'. :help 'smartindent'
    let [&l:autoindent, &l:smartindent, &l:cindent, &l:indentexpr] = [1, 1, 0, '']
    let indentopt.autoindent.restore = 1
  elseif a:opt.of('autoindent') == 3
    let [&l:cindent, &l:indentexpr] = [1, '']
    let indentopt.autoindent.restore = 1
  endif

  " set indentkeys
  if &l:indentexpr !=# ''
    let indentopt.indentkeys.name  = 'indentkeys'
    let indentopt.indentkeys.value = &l:indentkeys
  else
    let indentopt.indentkeys.name  = 'cinkeys'
    let indentopt.indentkeys.value = &l:cinkeys
  endif

  let val = a:opt.of('indentkeys')
  if type(val) == s:type_str
    execute printf('setlocal %s=%s', indentopt.indentkeys.name, val)
    let indentopt.indentkeys.restore = 1
  endif

  let val = a:opt.of('indentkeys+')
  if type(val) == s:type_str && val !=# ''
    execute printf('setlocal %s+=%s', indentopt.indentkeys.name, val)
    let indentopt.indentkeys.restore = 1
  endif

  let val = a:opt.of('indentkeys-')
  if type(val) == s:type_str && val !=# ''
    " It looks there is no way to add ',' itself to 'indentkeys'
    for item in split(val, ',')
      execute printf('setlocal %s-=%s', indentopt.indentkeys.name, item)
    endfor
    let indentopt.indentkeys.restore = 1
  endif
  return indentopt
endfunction
"}}}
function! s:restore_indent(indentopt) abort  "{{{
  " restore indentkeys first
  if a:indentopt.indentkeys.restore
    execute printf('setlocal %s=%s', a:indentopt.indentkeys.name, a:indentopt.indentkeys.value)
  endif

  " restore autoindent options
  if a:indentopt.autoindent.restore
    let [&l:autoindent, &l:smartindent, &l:cindent, &l:indentexpr] = a:indentopt.autoindent.value
  endif
endfunction
"}}}
function! s:add_former(buns, pos, opt, ...) abort  "{{{
  let undojoin_cmd = get(a:000, 0, 0) ? 'undojoin | ' : ''
  let opt_linewise  = a:opt.of('linewise')
  if opt_linewise
    let startinsert = a:opt.of('noremap') ? 'normal! O' : "normal \<Plug>(sandwich-O)"
  else
    let startinsert = a:opt.of('noremap') ? 'normal! i' : "normal \<Plug>(sandwich-i)"
  endif
  call s:add_portion(a:buns[0], a:pos, undojoin_cmd, startinsert)
  return [opt_linewise, indent(line("']")), getpos("'["), getpos("']")]
endfunction
"}}}
function! s:add_latter(buns, pos, opt) abort  "{{{
  let undojoin_cmd = ''
  let opt_linewise = a:opt.of('linewise')
  if opt_linewise
    let startinsert = a:opt.of('noremap') ? 'normal! o' : "normal \<Plug>(sandwich-o)"
  else
    let startinsert = a:opt.of('noremap') ? 'normal! i' : "normal \<Plug>(sandwich-i)"
  endif
  call s:add_portion(a:buns[1], a:pos, undojoin_cmd, startinsert)
  return [opt_linewise, indent(line("']")), getpos("'["), getpos("']")]
endfunction
"}}}
function! s:add_portion(bun, pos, undojoin_cmd, startinsert) abort "{{{
  call setpos('.', a:pos)
  if operator#sandwich#is_in_cmd_window()
    " workaround for a bug in cmdline-window
    call s:paste(a:bun, a:undojoin_cmd)
  else
    execute a:undojoin_cmd . 'silent ' . a:startinsert . a:bun
  endif
endfunction
"}}}
function! s:delete_former(head, tail, latter_head, opt, ...) abort  "{{{
  let is_linewise  = 0
  let opt_linewise = a:opt.of('linewise')
  let undojoin_cmd = get(a:000, 0, 0) ? 'undojoin | ' : ''
  let deletion = s:delete_portion(a:head, a:tail, undojoin_cmd)
  if opt_linewise == 2 || (opt_linewise == 1 && match(getline('.'), '^\s*$') > -1)
    if line('.') != a:latter_head[1]
      .delete
      let is_linewise = 1
    endif
    let head = getpos("']")
  else
    let head = getpos('.')
  endif
  return [deletion, is_linewise, head]
endfunction
"}}}
function! s:delete_latter(head, tail, former_head, opt) abort  "{{{
  let is_linewise  = 0
  let opt_linewise = a:opt.of('linewise')
  let undojoin_cmd = ''
  let deletion = s:delete_portion(a:head, a:tail, undojoin_cmd)
  if opt_linewise == 2 || (opt_linewise == 1 && match(getline('.'), '^\s*$') > -1)
    .delete
    let is_linewise = 1
    let tail = getpos("']")
    if tail[1] != 1 && tail[1] != a:former_head[1]
      let prevline = line("']") - 1
      let tail = [0, prevline, col([prevline, '$']), 0]
    endif
  else
    let tail = getpos("']")
  endif
  return [deletion, is_linewise, tail]
endfunction
"}}}
function! s:delete_portion(head, tail, undojoin_cmd) abort  "{{{
  let cmd = "%ssilent normal! \"\"dv:call setpos('\.', %s)\<CR>"
  call setpos('.', a:head)
  let @@ = ''
  execute printf(cmd, a:undojoin_cmd, 'a:tail')
  return @@
endfunction
"}}}
function! s:replace_former(bun, head, tail, within_a_line, opt, ...) abort "{{{
  let is_linewise  = 0
  let opt_linewise = a:opt.of('linewise')
  let undojoin_cmd = get(a:000, 0, 0) ? 'undojoin | ' : ''
  let deletion = s:delete_portion(a:head, a:tail, undojoin_cmd)

  if operator#sandwich#is_in_cmd_window()
    " workaround for a bug in cmdline-window
    call s:paste(a:bun)
  else
    if opt_linewise == 1 && getline('.') =~# '^\s*$'
      .delete
      let startinsert = a:opt.of('noremap', 'recipe_add') ? 'normal! O' : "normal \<Plug>(sandwich-O)"
      execute 'silent ' . startinsert . a:bun
      let is_linewise = 1
    elseif opt_linewise == 2
      if !a:within_a_line
        .delete
      endif
      let startinsert = a:opt.of('noremap', 'recipe_add') ? 'normal! O' : "normal \<Plug>(sandwich-O)"
      execute 'silent ' . startinsert . a:bun
      let is_linewise = 1
    else
      let startinsert = a:opt.of('noremap', 'recipe_add') ? 'normal! i' : "normal \<Plug>(sandwich-i)"
      execute 'silent ' . startinsert . a:bun
    endif
  endif
  return [deletion, is_linewise, indent(line("']")), getpos("'["), getpos("']")]
endfunction
"}}}
function! s:replace_latter(bun, head, tail, within_a_line, opt) abort "{{{
  let is_linewise  = 0
  let opt_linewise = a:opt.of('linewise')
  let undojoin_cmd = ''
  let deletion = s:delete_portion(a:head, a:tail, undojoin_cmd)

  if operator#sandwich#is_in_cmd_window()
    " workaround for a bug in cmdline-window
    call s:paste(a:bun)
    let head = getpos("'[")
    let tail = getpos("']")
  else
    if opt_linewise == 1 && getline('.') =~# '^\s*$'
      let startinsert = a:opt.of('noremap', 'recipe_add') ? 'normal! o' : "normal \<Plug>(sandwich-o)"
      let current = line('.')
      let fileend = line('$')
      .delete
      if current != fileend
        normal! k
      endif
      execute 'silent ' . startinsert . a:bun
      let head = getpos("'[")
      let tail = getpos("']")
      let is_linewise = 1
    elseif opt_linewise == 2
      let startinsert = a:opt.of('noremap', 'recipe_add') ? 'normal! o' : "normal \<Plug>(sandwich-o)"
      if a:within_a_line
        " exceptional behavior
        let lnum = line('.')
        execute 'silent ' . startinsert . a:bun
        let head = getpos("'[")
        let tail = getpos("']")
        execute lnum . 'delete'
        let head = [0, head[1]-1, head[2], 0]
        let tail = [0, tail[1]-1, tail[2], 0]
      else
        " usual way (same as opt_linewise == 1)
        let current = line('.')
        let fileend = line('$')
        .delete
        if current != fileend
          normal! k
        endif
        execute 'silent ' . startinsert . a:bun
        let head = getpos("'[")
        let tail = getpos("']")
      endif
      let is_linewise = 1
    else
      let startinsert = a:opt.of('noremap', 'recipe_add') ? 'normal! i' : "normal \<Plug>(sandwich-i)"
      execute 'silent ' . startinsert . a:bun
      let head = getpos("'[")
      let tail = getpos("']")
    endif
  endif
  return [deletion, is_linewise, indent(line("']")), head, tail]
endfunction
"}}}
function! s:paste(bun, ...) abort "{{{
  let undojoin_cmd = a:0 > 0 ? a:1 : ''
  let reg = ['"', getreg('"'), getregtype('"')]
  let @@ = a:bun
  if s:has_gui_running
    execute undojoin_cmd . 'normal! ""P'
  else
    let paste  = &paste
    let &paste = 1
    execute undojoin_cmd . 'normal! ""P'
    let &paste = paste
  endif
  call call('setreg', reg)
endfunction
"}}}
function! s:execute_command(head, tail, command_list) abort "{{{
  let mod_head = deepcopy(a:head)
  let mod_tail = deepcopy(a:tail)

  if a:command_list != []
    let before_mod_head = getpos("'[")
    let before_mod_tail = getpos("']")
    call setpos("'[", a:head)
    call setpos("']", a:tail)
    for command in a:command_list
      execute command
    endfor

    let after_mod_head = getpos("'[")
    let after_mod_tail = getpos("']")
    if before_mod_head != after_mod_head || before_mod_tail != after_mod_tail
      let mod_head = after_mod_head
      let mod_tail = after_mod_tail
    endif
  endif
  return [mod_head, mod_tail]
endfunction
"}}}
function! s:shift_for_add(shifted_pos, target, addition, indent, is_linewise) abort "{{{
  call s:push2(a:shifted_pos, a:target, a:addition, a:indent, a:is_linewise)
  call s:push1(a:shifted_pos, a:target, a:addition, a:indent, a:is_linewise)
  return a:shifted_pos
endfunction
"}}}
function! s:shift_for_delete(shifted_pos, target, deletion, is_linewise) abort  "{{{
  call s:pull2(a:shifted_pos, a:target, a:deletion, a:is_linewise)
  call s:pull1(a:shifted_pos, a:target, a:deletion, a:is_linewise)
  return a:shifted_pos
endfunction
"}}}
function! s:shift_for_replace(shifted_pos, target, addition, deletion, indent, is_linewise) abort "{{{
  if s:is_in_between(a:shifted_pos, a:target.head1, a:target.tail1)
    let startpos = copy(a:target.head1)
    let endpos   = copy(startpos)
    call s:push1(endpos, a:target, a:addition, a:indent, a:is_linewise)
    let endpos = s:get_left_pos(endpos)

    if s:is_equal_or_ahead(a:shifted_pos, endpos)
      let a:shifted_pos[0:3] = endpos
    endif
  elseif s:is_in_between(a:shifted_pos, a:target.head2, a:target.tail2)
    let startpos = copy(a:target.head2)
    call s:pull1(startpos, a:target, a:deletion, a:is_linewise)
    call s:push1(startpos, a:target, a:addition, a:indent, a:is_linewise)
    let endpos = copy(startpos)
    let target = copy(s:null_4pos)
    let target.head2 = copy(startpos)
    call s:push2(endpos, target, a:addition, a:indent, a:is_linewise)
    let endpos = s:get_left_pos(endpos)

    call s:pull1(a:shifted_pos, a:target, a:deletion, a:is_linewise)
    call s:push1(a:shifted_pos, a:target, a:addition, a:indent, a:is_linewise)

    if s:is_equal_or_ahead(a:shifted_pos, endpos)
      let a:shifted_pos[0:3] = endpos
    endif
  else
    call s:pull2(a:shifted_pos, a:target, a:deletion, a:is_linewise)
    if a:is_linewise[1]
      let a:target.head2[1] -= 1
    endif
    call s:push2(a:shifted_pos, a:target, a:addition, a:indent, a:is_linewise)
    if a:is_linewise[1]
      let a:target.head2[1] += 1
    endif
    call s:pull1(a:shifted_pos, a:target, a:deletion, a:is_linewise)
    if a:is_linewise[0]
      let a:target.head1[1] -= 1
    endif
    call s:push1(a:shifted_pos, a:target, a:addition, a:indent, a:is_linewise)
    if a:is_linewise[0]
      let a:target.head1[1] += 1
    endif
  endif
  return a:shifted_pos
endfunction
"}}}
function! s:shift_added(func_name, added, ...) abort  "{{{
  for pos in ['head1', 'tail1', 'head2', 'tail2']
    call call(a:func_name, [a:added[pos]] + a:000)
  endfor
  return a:added
endfunction
"}}}
function! s:push1(shifted_pos, target, addition, indent, is_linewise) abort  "{{{
  if a:shifted_pos != s:null_pos
    let shift = [0, 0, 0, 0]
    let head  = a:target.head1

    if a:is_linewise[0] && a:shifted_pos[1] >= head[1]
      " lnum
      let shift[1] += 1
    endif

    if s:is_equal_or_ahead(a:shifted_pos, head) || (a:is_linewise[0] && a:shifted_pos[1] == head[1])
      call s:push(shift, a:shifted_pos, head, a:addition[0], a:indent[0], a:is_linewise[0])
    endif
    let a:shifted_pos[1:2] += shift[1:2]
  endif
  return a:shifted_pos
endfunction
"}}}
function! s:push2(shifted_pos, target, addition, indent, is_linewise) abort  "{{{
  if a:shifted_pos != s:null_pos
    let shift = [0, 0, 0, 0]
    let head  = a:target.head2

    if a:is_linewise[1] && a:shifted_pos[1] > head[1]
      " lnum
      let shift[1] += 1
    endif

    if s:is_equal_or_ahead(a:shifted_pos, head)
      call s:push(shift, a:shifted_pos, head, a:addition[1], a:indent[1], a:is_linewise[1])
    endif
    let a:shifted_pos[1:2] += shift[1:2]
  endif
  return a:shifted_pos
endfunction
"}}}
function! s:push(shift, shifted_pos, head, addition, indent, is_linewise) abort  "{{{
  let addition = split(a:addition, '\n', 1)

  " lnum
  let a:shift[1] += len(addition) - 1
  " column
  if !a:is_linewise && a:head[1] == a:shifted_pos[1]
    let a:shift[2] += strlen(addition[-1])
    if len(addition) > 1
      let a:shift[2] -= a:head[2] - 1
      let a:shift[2] += a:indent - strlen(matchstr(addition[-1], '^\s*'))
    endif
  endif
endfunction
"}}}
function! s:pull1(shifted_pos, target, deletion, is_linewise) abort "{{{
  if a:shifted_pos != s:null_pos
    let shift  = [0, 0, 0, 0]
    let head   = a:target.head1
    let tail   = a:target.tail1

    " lnum
    if a:shifted_pos[1] > head[1]
      if a:shifted_pos[1] <= tail[1]
        let shift[1] -= a:shifted_pos[1] - head[1]
      else
        let shift[1] -= tail[1] - head[1]
      endif
    endif
    " column
    if s:is_ahead(a:shifted_pos, head) && a:shifted_pos[1] <= tail[1]
      if s:is_ahead(a:shifted_pos, tail)
        let shift[2] -= strlen(split(a:deletion[0], '\n', 1)[-1])
        let shift[2] += head[1] != a:shifted_pos[1] ? head[2] - 1 : 0
      else
        let shift[2] -= a:shifted_pos[2]
        let shift[2] += head[2]
      endif
    endif

    let a:shifted_pos[1] += shift[1]

    " the case for linewise action
    if a:is_linewise[0]
      if a:shifted_pos[1] == head[1]
        " col
        let a:shifted_pos[2] = 0
      endif
      if a:shifted_pos[1] > head[1]
        " lnum
        let a:shifted_pos[1] -= 1
      endif
    endif

    if a:shifted_pos[2] == 0
      let a:shifted_pos[2] = 1
    elseif a:shifted_pos[2] == 1/0
      let a:shifted_pos[2]  = col([a:shifted_pos[1], '$']) - 1
      let a:shifted_pos[2] += shift[2]
    else
      let a:shifted_pos[2] += shift[2]
    endif
  endif
  return a:shifted_pos
endfunction
"}}}
function! s:pull2(shifted_pos, target, deletion, is_linewise) abort "{{{
  if a:shifted_pos != s:null_pos
    let shift  = [0, 0, 0, 0]
    let head   = a:target.head2
    let tail   = a:target.tail2

    " lnum
    if a:shifted_pos[1] >= head[1]
      if a:shifted_pos[1] < tail[1]
        let shift[1] -= a:shifted_pos[1] - head[1]
      else
        let shift[1] -= tail[1] - head[1]
      endif
    endif
    " column
    if s:is_equal_or_ahead(a:shifted_pos, head) && a:shifted_pos[1] <= tail[1]
      if s:is_ahead(a:shifted_pos, tail)
        let shift[2] -= strlen(split(a:deletion[1], '\n', 1)[-1])
        let shift[2] += head[1] != a:shifted_pos[1] ? head[2] - 1 : 0
      else
        let shift[2] -= a:shifted_pos[2] + 1
        let shift[2] += head[2]
      endif
    endif
    let a:shifted_pos[1:2] += shift[1:2]

    " the case for linewise action
    if a:is_linewise[1]
      if a:shifted_pos[1] == head[1]
        " col
        let a:shifted_pos[2]  = 1/0
      endif
      if a:shifted_pos[1] >= head[1]
        " lnum
        let a:shifted_pos[1] -= 1
      endif
    endif
  endif
  return a:shifted_pos
endfunction
"}}}

let [s:get_left_pos, s:get_right_pos, s:is_valid_4pos, s:is_ahead, s:is_equal_or_ahead, s:is_in_between]
      \ = operator#sandwich#lib#funcref(['get_left_pos', 'get_right_pos', 'is_valid_4pos', 'is_ahead', 'is_equal_or_ahead', 'is_in_between'])


" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set ts=2 sts=2 sw=2:
