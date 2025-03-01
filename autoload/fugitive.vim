" Location:     autoload/fugitive.vim
" Maintainer:   Tim Pope <http://tpo.pe/>

if exists('g:autoloaded_fugitive')
  finish
endif
let g:autoloaded_fugitive = 1

if !exists('g:fugitive_git_executable')
  let g:fugitive_git_executable = 'git'
endif

" Section: Utility

function! s:function(name) abort
  return function(substitute(a:name,'^s:',matchstr(expand('<sfile>'), '<SNR>\d\+_'),''))
endfunction

function! s:sub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'')
endfunction

function! s:gsub(str,pat,rep) abort
  return substitute(a:str,'\v\C'.a:pat,a:rep,'g')
endfunction

function! s:Uniq(list) abort
  let i = 0
  let seen = {}
  while i < len(a:list)
    let str = string(a:list[i])
    if has_key(seen, str)
      call remove(a:list, i)
    else
      let seen[str] = 1
      let i += 1
    endif
  endwhile
  return a:list
endfunction

function! s:winshell() abort
  return has('win32') && &shellcmdflag !~# '^-'
endfunction

function! s:shellesc(arg) abort
  if type(a:arg) == type([])
    return join(map(copy(a:arg), 's:shellesc(v:val)'))
  elseif a:arg =~ '^[A-Za-z0-9_/:.-]\+$'
    return a:arg
  elseif s:winshell()
    return '"'.s:gsub(s:gsub(a:arg, '"', '""'), '\%', '"%"').'"'
  else
    return shellescape(a:arg)
  endif
endfunction

let s:fnameescape = " \t\n*?[{`$\\%#'\"|!<"
function! s:fnameescape(file) abort
  if type(a:file) == type([])
    return join(map(copy(a:file), 's:fnameescape(v:val)'))
  elseif exists('*fnameescape')
    return fnameescape(a:file)
  else
    return escape(a:file, s:fnameescape)
  endif
endfunction

function! s:throw(string) abort
  throw 'fugitive: '.a:string
endfunction

function! s:DirCheck(...) abort
  if empty(a:0 ? s:Dir(a:1) : s:Dir())
    return 'return ' . string('echoerr "fugitive: not a Git repository"')
  endif
  return ''
endfunction

function! s:Mods(mods, ...) abort
  let mods = substitute(a:mods, '\C<mods>', '', '')
  let mods = mods =~# '\S$' ? mods . ' ' : mods
  if a:0 && mods !~# '\<\%(aboveleft\|belowright\|leftabove\|rightbelow\|topleft\|botright\|tab\)\>'
    let mods = a:1 . ' ' . mods
  endif
  return substitute(mods, '\s\+', ' ', 'g')
endfunction

function! s:Slash(path) abort
  if exists('+shellslash')
    return tr(a:path, '\', '/')
  else
    return a:path
  endif
endfunction

function! s:PlatformSlash(path) abort
  if exists('+shellslash') && !&shellslash
    return tr(a:path, '/', '\')
  else
    return a:path
  endif
endfunction

function! s:Resolve(path) abort
  let path = resolve(a:path)
  if has('win32')
    let path = s:PlatformSlash(fnamemodify(fnamemodify(path, ':h'), ':p') . fnamemodify(path, ':t'))
  endif
  return path
endfunction

function! s:cpath(path, ...) abort
  if exists('+fileignorecase') && &fileignorecase
    let path = s:PlatformSlash(tolower(a:path))
  else
    let path = s:PlatformSlash(a:path)
  endif
  return a:0 ? path ==# s:cpath(a:1) : path
endfunction

function! s:Cd(...) abort
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd' : exists(':tcd') && haslocaldir(-1) ? 'tcd' : 'cd'
  if !a:0
    return cd
  endif
  let cwd = getcwd()
  if s:cpath(cwd, a:1)
    return ''
  endif
  exe cd s:fnameescape(a:1)
  return cd . ' ' . s:fnameescape(cwd)
endfunction

let s:executables = {}

function! s:executable(binary) abort
  if !has_key(s:executables, a:binary)
    let s:executables[a:binary] = executable(a:binary)
  endif
  return s:executables[a:binary]
endfunction

let s:nowait = v:version >= 704 ? '<nowait>' : ''

function! s:map(mode, lhs, rhs, ...) abort
  let flags = (a:0 ? a:1 : '') . (a:rhs =~# '<Plug>' ? '' : '<script>')
  let head = a:lhs
  let tail = ''
  let keys = get(g:, a:mode.'remap', {})
  if type(keys) == type([])
    return
  endif
  while !empty(head)
    if has_key(keys, head)
      let head = keys[head]
      if empty(head)
        return
      endif
      break
    endif
    let tail = matchstr(head, '<[^<>]*>$\|.$') . tail
    let head = substitute(head, '<[^<>]*>$\|.$', '', '')
  endwhile
  if flags !~# '<unique>' || empty(mapcheck(head.tail, a:mode))
    exe a:mode.'map <buffer>' flags head.tail a:rhs
    if a:0 > 1
      let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe') .
            \ '|sil! exe "' . a:mode . 'unmap <buffer> ' . head.tail . '"'
    endif
  endif
endfunction

" Section: Quickfix

function! s:QuickfixGet(nr, ...) abort
  if a:nr < 0
    return call('getqflist', a:000)
  else
    return call('getloclist', [a:nr] + a:000)
  endif
endfunction

function! s:QuickfixSet(nr, ...) abort
  if a:nr < 0
    return call('setqflist', a:000)
  else
    return call('setloclist', [a:nr] + a:000)
  endif
endfunction

function! s:QuickfixCreate(nr, opts) abort
  if has('patch-7.4.2200')
    call s:QuickfixSet(a:nr, [], ' ', a:opts)
  else
    call s:QuickfixSet(a:nr, [], ' ')
  endif
endfunction

function! s:QuickfixStream(nr, title, cmd, first, callback, ...) abort
  call s:QuickfixCreate(a:nr, {'title': a:title})
  let winnr = winnr()
  exe a:nr < 0 ? 'copen' : 'lopen'
  if winnr != winnr()
    wincmd p
  endif

  let buffer = []
  let lines = split(s:SystemError(s:shellesc(a:cmd))[0], "\n")
  for line in lines
    call extend(buffer, call(a:callback, a:000 + [line]))
    if len(buffer) >= 20
      call s:QuickfixSet(a:nr, remove(buffer, 0, -1), 'a')
      redraw
    endif
  endfor
  call s:QuickfixSet(a:nr, extend(buffer, call(a:callback, a:000 + [0])), 'a')

  if a:first && len(s:QuickfixGet(a:nr))
    call s:BlurStatus()
    return a:nr < 0 ? 'cfirst' : 'lfirst'
  else
    return 'exe'
  endif
endfunction

" Section: Git

function! s:UserCommandList(...) abort
  let git = split(get(g:, 'fugitive_git_command', g:fugitive_git_executable), '\s\+')
  let dir = a:0 ? s:Dir(a:1) : ''
  if len(dir)
    let tree = s:Tree(dir)
    if empty(tree)
      call add(git, '--git-dir=' . dir)
    elseif len(tree) && s:cpath(tree) !=# s:cpath(getcwd())
      if fugitive#GitVersion(1, 8, 5)
        call extend(git, ['-C', tree])
      else
        throw 'fugitive: Git 1.8.5 or higher required to change directory'
      endif
    endif
  endif
  return git
endfunction

function! s:UserCommand(...) abort
  return s:shellesc(call('s:UserCommandList', a:000))
endfunction

let s:git_versions = {}
function! fugitive#GitVersion(...) abort
  if !has_key(s:git_versions, g:fugitive_git_executable)
    let s:git_versions[g:fugitive_git_executable] = matchstr(system(g:fugitive_git_executable.' --version'), '\d[^[:space:]]\+')
  endif
  if !a:0
    return s:git_versions[g:fugitive_git_executable]
  endif
  let components = split(s:git_versions[g:fugitive_git_executable], '\D\+')
  if empty(components)
    return -1
  endif
  for i in range(len(a:000))
    if a:000[i] > +get(components, i)
      return 0
    elseif a:000[i] < +get(components, i)
      return 1
    endif
  endfor
  return a:000[i] ==# get(components, i)
endfunction

let s:commondirs = {}
function! fugitive#CommonDir(dir) abort
  if empty(a:dir)
    return ''
  endif
  if !has_key(s:commondirs, a:dir)
    if getfsize(a:dir . '/HEAD') < 10
      let s:commondirs[a:dir] = ''
    elseif filereadable(a:dir . '/commondir')
      let dir = get(readfile(a:dir . '/commondir', 1), 0, '')
      if dir =~# '^/\|^\a:/'
        let s:commondirs[a:dir] = dir
      else
        let s:commondirs[a:dir] = simplify(a:dir . '/' . dir)
      endif
    else
      let s:commondirs[a:dir] = a:dir
    endif
  endif
  return s:commondirs[a:dir]
endfunction

function! s:Dir(...) abort
  return a:0 ? FugitiveGitDir(a:1) : FugitiveGitDir()
endfunction

function! s:Tree(...) abort
  return a:0 ? FugitiveWorkTree(a:1) : FugitiveWorkTree()
endfunction

function! s:HasOpt(args, ...) abort
  let args = a:args[0 : index(a:args, '--')]
  let opts = copy(a:000)
  if type(opts[0]) == type([])
    if empty(args) || index(opts[0], args[0]) == -1
      return 0
    endif
    call remove(opts, 0)
  endif
  for opt in opts
    if index(args, opt) != -1
      return 1
    endif
  endfor
endfunction

function! s:PreparePathArgs(cmd, dir, literal) abort
  let literal_supported = fugitive#GitVersion(1, 9)
  if a:literal && literal_supported
    call insert(a:cmd, '--literal-pathspecs')
  endif
  let split = index(a:cmd, '--')
  if split < 0
    return a:cmd
  endif
  for i in range(split + 1, len(a:cmd) - 1)
    if type(a:cmd[i]) == type(0)
      let a:cmd[i] = fugitive#Path(bufname(a:cmd[i]), './', a:dir)
    elseif a:literal
      let a:cmd[i] = fugitive#Path(a:cmd[i], './', a:dir)
    elseif !literal_supported
      let a:cmd[i] = substitute(a:cmd[i], '^:\%(/\|([^)]*)\)\=:\=', './', '')
    endif
  endfor
  return a:cmd
endfunction

let s:prepare_env = {
      \ 'sequence.editor': 'GIT_SEQUENCE_EDITOR',
      \ 'core.editor': 'GIT_EDITOR',
      \ 'core.askpass': 'GIT_ASKPASS',
      \ }
function! fugitive#PrepareDirEnvArgv(...) abort
  if a:0 && type(a:1) ==# type([])
    let cmd = a:000[1:-1] + a:1
  else
    let cmd = copy(a:000)
  endif
  let env = {}
  let i = 0
  while i < len(cmd)
    if cmd[i] =~# '^$\|[\/.]' && cmd[i] !~# '^-'
      let dir = remove(cmd, 0)
    elseif cmd[i] =~# '^--git-dir='
      let dir = remove(cmd, 0)[10:-1]
    elseif type(cmd[i]) ==# type(0)
      let dir = s:Dir(remove(cmd, i))
    elseif cmd[i] ==# '-c' && len(cmd) > i + 1
      let key = matchstr(cmd[i+1], '^[^=]*')
      if has_key(s:prepare_env, tolower(key)) || key !~# '\.'
        let var = get(s:prepare_env, tolower(key), key)
        let val = matchstr(cmd[i+1], '=\zs.*')
        let env[var] = val
      endif
      if fugitive#GitVersion(1, 8) && cmd[i+1] =~# '\.'
        let i += 2
      else
        call remove(cmd, i, i + 1)
      endif
    elseif cmd[i] =~# '^--.*pathspecs$'
      let explicit_pathspec_option = 1
      if fugitive#GitVersion(1, 9)
        let i += 1
      else
        call remove(cmd, i)
      endif
    elseif cmd[i] !~# '^-'
      break
    else
      let i += 1
    endif
  endwhile
  if !exists('dir')
    let dir = s:Dir()
  endif
  let tree = s:Tree(dir)
  call s:PreparePathArgs(cmd, dir, !exists('explicit_pathspec_option'))
  return [dir, env, cmd]
endfunction

function! s:BuildShell(dir, env, args) abort
  let cmd = copy(a:args)
  let tree = s:Tree(a:dir)
  let pre = ''
  for [var, val] in items(a:env)
    if s:winshell()
      let pre .= 'set ' . var . '=' . s:shellesc(val) . '& '
    else
      let pre = (len(pre) ? pre : 'env ') . var . '=' . s:shellesc(val) . ' '
    endif
  endfor
  if empty(tree) || index(cmd, '--') == len(cmd) - 1
    call insert(cmd, '--git-dir=' . a:dir)
  elseif fugitive#GitVersion(1, 8, 5)
    call extend(cmd, ['-C', tree], 'keep')
  else
    let pre = 'cd ' . s:shellesc(tree) . (s:winshell() ? '& ' : '; ') . pre
  endif
  return pre . g:fugitive_git_executable . ' ' . join(map(cmd, 's:shellesc(v:val)'))
endfunction

function! fugitive#Prepare(...) abort
  let [dir, env, argv] = call('fugitive#PrepareDirEnvArgv', a:000)
  return s:BuildShell(dir, env, argv)
endfunction

function! s:SystemError(cmd, ...) abort
  try
    let out = call('system', [type(a:cmd) ==# type([]) ? fugitive#Prepare(a:cmd) : a:cmd] + a:000)
    return [out, v:shell_error]
  catch /^Vim\%((\a\+)\)\=:E484:/
    let opts = ['shell', 'shellcmdflag', 'shellredir', 'shellquote', 'shellxquote', 'shellxescape', 'shellslash']
    call filter(opts, 'exists("+".v:val) && !empty(eval("&".v:val))')
    call map(opts, 'v:val."=".eval("&".v:val)')
    call s:throw('failed to run `' . a:cmd . '` with ' . join(opts, ' '))
  endtry
endfunction

function! s:ChompError(...) abort
  let [out, exec_error] = s:SystemError(call('fugitive#Prepare', a:000))
  return [s:sub(out, '\n$', ''), exec_error]
endfunction

function! s:ChompDefault(default, ...) abort
  let [out, exec_error] = call('s:ChompError', a:000)
  return exec_error ? a:default : out
endfunction

function! s:LinesError(...) abort
  let [out, exec_error] = call('s:ChompError', a:000)
  return [len(out) && !exec_error ? split(out, "\n", 1) : [], exec_error]
endfunction

function! s:NullError(...) abort
  let [out, exec_error] = s:SystemError(call('fugitive#Prepare', a:000))
  return [exec_error ? [] : split(out, "\1"), exec_error ? out : '', exec_error]
endfunction

function! s:TreeChomp(...) abort
  let cmd = call('fugitive#Prepare', a:000)
  let [out, exec_error] = s:SystemError(cmd)
  let out = s:sub(out, '\n$', '')
  if !exec_error
    return out
  endif
  throw 'fugitive: error running `' . cmd . '`: ' . out
endfunction

function! fugitive#Head(...) abort
  let dir = a:0 > 1 ? a:2 : s:Dir()
  if empty(dir) || !filereadable(fugitive#Find('.git/HEAD', dir))
    return ''
  endif
  let head = readfile(fugitive#Find('.git/HEAD', dir))[0]
  if head =~# '^ref: '
    return substitute(head, '\C^ref: \%(refs/\%(heads/\|remotes/\|tags/\)\=\)\=', '', '')
  elseif head =~# '^\x\{40,\}$'
    let len = a:0 ? a:1 : 0
    return len < 0 ? head : len ? head[0:len-1] : ''
  else
    return ''
  endif
endfunction

function! fugitive#RevParse(rev, ...) abort
  let [hash, exec_error] = s:ChompError([a:0 ? a:1 : s:Dir(), 'rev-parse', '--verify', a:rev, '--'])
  if !exec_error && hash =~# '^\x\{40,\}$'
    return hash
  endif
  call s:throw('rev-parse '.a:rev.': '.hash)
endfunction

function! s:ConfigTimestamps(dir, dict) abort
  let files = ['/etc/gitconfig', '~/.gitconfig',
        \ len($XDG_CONFIG_HOME) ? $XDG_CONFIG_HOME . '/git/config' : '~/.config/git/config']
  if len(a:dir)
    call add(files, fugitive#Find('.git/config', a:dir))
  endif
  call extend(files, get(a:dict, 'include.path', []))
  return join(map(files, 'getftime(expand(v:val))'), ',')
endfunction

let s:config = {}
function! fugitive#Config(...) abort
  let dir = s:Dir()
  let name = ''
  if a:0 >= 2 && type(a:2) == type({})
    let name = substitute(a:1, '^[^.]\+\|[^.]\+$', '\L&', 'g')
    return len(a:1) ? get(get(a:2, name, []), 0, '') : a:2
  elseif a:0 >= 2
    let dir = a:2
    let name = a:1
  elseif a:0 == 1 && type(a:1) == type({})
    return a:1
  elseif a:0 == 1 && a:1 =~# '^[[:alnum:]-]\+\.'
    let name = a:1
  elseif a:0 == 1
    let dir = a:1
  endif
  let name = substitute(name, '^[^.]\+\|[^.]\+$', '\L&', 'g')
  let key = len(dir) ? dir : '_'
  if has_key(s:config, key) && s:config[key][0] ==# s:ConfigTimestamps(dir, s:config[key][1])
    let dict = s:config[key][1]
  else
    let dict = {}
    let [lines, message, exec_error] = s:NullError([dir, 'config', '--list', '-z'])
    if exec_error
      return {}
    endif
    for line in lines
      let key = matchstr(line, "^[^\n]*")
      if !has_key(dict, key)
        let dict[key] = []
      endif
      call add(dict[key], strpart(line, len(key) + 1))
    endfor
    let s:config[dir] = [s:ConfigTimestamps(dir, dict), dict]
    lockvar! dict
  endif
  return len(name) ? get(get(dict, name, []), 0, '') : dict
endfunction

function! s:Remote(dir) abort
  let head = FugitiveHead(0, a:dir)
  let remote = len(head) ? fugitive#Config('branch.' . head . '.remote') : ''
  let i = 10
  while remote ==# '.' && i > 0
    let head = matchstr(fugitive#Config('branch.' . head . '.merge'), 'refs/heads/\zs.*')
    let remote = len(head) ? fugitive#Config('branch.' . head . '.remote') : ''
    let i -= 1
  endwhile
  return remote =~# '^\.\=$' ? 'origin' : remote
endfunction

function! fugitive#RemoteUrl(...) abort
  let dir = a:0 > 1 ? a:2 : s:Dir()
  let remote = !a:0 || a:1 =~# '^\.\=$' ? s:Remote(dir) : a:1
  if !fugitive#GitVersion(2, 7)
    return fugitive#Config('remote.' . remote . '.url')
  endif
  return s:ChompDefault('', [dir, 'remote', 'get-url', remote, '--'])
endfunction

" Section: Repository Object

function! s:add_methods(namespace, method_names) abort
  for name in a:method_names
    let s:{a:namespace}_prototype[name] = s:function('s:'.a:namespace.'_'.name)
  endfor
endfunction

let s:commands = []
function! s:command(definition, ...) abort
  if a:0
    call add(s:commands, a:definition . ' execute s:' . a:1 . "Command(<line1>, <line2>, +'<range>', <count>, <bang>0, '<mods>', <q-reg>, <q-args>, [<f-args>])")
  else
    call add(s:commands, a:definition)
  endif
endfunction

function! s:define_commands() abort
  for command in s:commands
    exe 'command! -buffer '.command
  endfor
endfunction

let s:repo_prototype = {}
let s:repos = {}

function! fugitive#repo(...) abort
  let dir = a:0 ? s:Dir(a:1) : (len(s:Dir()) ? s:Dir() : FugitiveExtractGitDir(expand('%:p')))
  if dir !=# ''
    if has_key(s:repos, dir)
      let repo = get(s:repos, dir)
    else
      let repo = {'git_dir': dir}
      let s:repos[dir] = repo
    endif
    return extend(repo, s:repo_prototype, 'keep')
  endif
  call s:throw('not a Git repository')
endfunction

function! s:repo_dir(...) dict abort
  return join([self.git_dir]+a:000,'/')
endfunction

function! s:repo_tree(...) dict abort
  let dir = s:Tree(self.git_dir)
  if dir ==# ''
    call s:throw('no work tree')
  else
    return join([dir]+a:000,'/')
  endif
endfunction

function! s:repo_bare() dict abort
  if self.dir() =~# '/\.git$'
    return 0
  else
    return s:Tree(self.git_dir) ==# ''
  endif
endfunction

function! s:repo_find(object) dict abort
  return fugitive#Find(a:object, self.git_dir)
endfunction

function! s:repo_translate(rev) dict abort
  return s:Slash(fugitive#Find(substitute(a:rev, '^/', ':(top)', ''), self.git_dir))
endfunction

function! s:repo_head(...) dict abort
  return fugitive#Head(a:0 ? a:1 : 0, self.git_dir)
endfunction

call s:add_methods('repo',['dir','tree','bare','find','translate','head'])

function! s:repo_prepare(...) dict abort
  return call('fugitive#Prepare', [self.git_dir] + a:000)
endfunction

function! s:repo_git_command(...) dict abort
  let git = s:UserCommand() . ' --git-dir='.s:shellesc(self.git_dir)
  return git.join(map(copy(a:000),'" ".s:shellesc(v:val)'),'')
endfunction

function! s:repo_git_chomp(...) dict abort
  let git = g:fugitive_git_executable . ' --git-dir='.s:shellesc(self.git_dir)
  let output = git . join(map(copy(a:000),'" ".s:shellesc(v:val)'),'')
  return s:sub(system(output), '\n$', '')
endfunction

function! s:repo_git_chomp_in_tree(...) dict abort
  let cdback = s:Cd(self.tree())
  try
    return call(self.git_chomp, a:000, self)
  finally
    execute cdback
  endtry
endfunction

function! s:repo_rev_parse(rev) dict abort
  return fugitive#RevParse(a:rev, self.git_dir)
endfunction

call s:add_methods('repo',['prepare','git_command','git_chomp','git_chomp_in_tree','rev_parse'])

function! s:repo_superglob(base) dict abort
  return map(fugitive#CompleteObject(a:base, self.git_dir), 'substitute(v:val, ''\\\(.\)'', ''\1'', "g")')
endfunction

call s:add_methods('repo',['superglob'])

function! s:repo_config(name) dict abort
  return fugitive#Config(a:name, self.git_dir)
endfunction

function! s:repo_user() dict abort
  let username = self.config('user.name')
  let useremail = self.config('user.email')
  return username.' <'.useremail.'>'
endfunction

call s:add_methods('repo',['config', 'user'])

" Section: File API

function! s:DirCommitFile(path) abort
  let vals = matchlist(s:Slash(a:path), '\c^fugitive:\%(//\)\=\(.\{-\}\)\%(//\|::\)\(\x\{40,\}\|[0-3]\)\(/.*\)\=$')
  if empty(vals)
    return ['', '', '']
  endif
  return vals[1:3]
endfunction

function! s:DirRev(url) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  return [dir, (commit =~# '^.$' ? ':' : '') . commit . substitute(file, '^/', ':', '')]
endfunction

function! s:Owner(path, ...) abort
  let dir = a:0 ? a:1 : s:Dir()
  if empty(dir)
    return ''
  endif
  let actualdir = fugitive#Find('.git/', dir)
  let [pdir, commit, file] = s:DirCommitFile(a:path)
  if s:cpath(dir, pdir)
    if commit =~# '^\x\{40,\}$'
      return commit
    elseif commit ==# '2'
      return 'HEAD^{}'
    endif
    if filereadable(actualdir . 'MERGE_HEAD')
      let merge_head = 'MERGE_HEAD'
    elseif filereadable(actualdir . 'REBASE_HEAD')
      let merge_head = 'REBASE_HEAD'
    else
      return ''
    endif
    if commit ==# '3'
      return merge_head . '^{}'
    elseif commit ==# '1'
      return s:TreeChomp('merge-base', 'HEAD', merge_head, '--')
    endif
  endif
  let path = fnamemodify(a:path, ':p')
  if s:cpath(actualdir, strpart(path, 0, len(actualdir))) && a:path =~# 'HEAD$'
    return strpart(path, len(actualdir))
  endif
  let refs = fugitive#CommonDir(dir) . '/refs'
  if s:cpath(refs . '/', path[0 : len(refs)]) && path !~# '[\/]$'
    return strpart(path, len(refs) - 4)
  endif
  return ''
endfunction

function! fugitive#Real(url) abort
  if empty(a:url)
    return ''
  endif
  let [dir, commit, file] = s:DirCommitFile(a:url)
  if len(dir)
    let tree = s:Tree(dir)
    return s:PlatformSlash((len(tree) ? tree : dir) . file)
  endif
  let pre = substitute(matchstr(a:url, '^\a\a\+\ze:'), '^.', '\u&', '')
  if len(pre) && pre !=? 'fugitive' && exists('*' . pre . 'Real')
    let url = {pre}Real(a:url)
  else
    let url = fnamemodify(a:url, ':p' . (a:url =~# '[\/]$' ? '' : ':s?[\/]$??'))
  endif
  return s:PlatformSlash(empty(url) ? a:url : url)
endfunction

function! fugitive#Path(url, ...) abort
  if empty(a:url)
    return ''
  endif
  let dir = a:0 > 1 ? a:2 : s:Dir()
  let tree = s:Tree(dir)
  if !a:0
    return fugitive#Real(a:url)
  elseif a:1 =~# '\.$'
    let path = s:Slash(fugitive#Real(a:url))
    let cwd = getcwd()
    let lead = ''
    while s:cpath(tree . '/', (cwd . '/')[0 : len(tree)])
      if s:cpath(cwd . '/', path[0 : len(cwd)])
        if strpart(path, len(cwd) + 1) =~# '^\.git\%(/\|$\)'
          break
        endif
        return a:1[0:-2] . (empty(lead) ? './' : lead) . strpart(path, len(cwd) + 1)
      endif
      let cwd = fnamemodify(cwd, ':h')
      let lead .= '../'
    endwhile
    return a:1[0:-2] . path
  endif
  let url = a:url
  if has_key(get(s:temp_files, s:cpath(url), {}), 'bufnr')
    let url = bufname(s:temp_files[s:cpath(url)].bufnr)
  endif
  let url = s:Slash(fnamemodify(url, ':p'))
  if url =~# '/$' && s:Slash(a:url) !~# '/$'
    let url = url[0:-2]
  endif
  let [argdir, commit, file] = s:DirCommitFile(a:url)
  if len(argdir) && s:cpath(argdir) !=# s:cpath(dir)
    let file = ''
  elseif len(dir) && s:cpath(url[0 : len(dir)]) ==# s:cpath(dir . '/')
    let file = '/.git'.url[strlen(dir) : -1]
  elseif len(tree) && s:cpath(url[0 : len(tree)]) ==# s:cpath(tree . '/')
    let file = url[len(tree) : -1]
  elseif s:cpath(url) ==# s:cpath(tree)
    let file = '/'
  endif
  if empty(file) && a:1 =~# '^$\|^[.:]/$'
    return s:Slash(fugitive#Real(a:url))
  endif
  return substitute(file, '^/', a:1, '')
endfunction

function! s:Relative(...) abort
  return fugitive#Path(@%, a:0 ? a:1 : ':(top)', a:0 > 1 ? a:2 : s:Dir())
endfunction

function! fugitive#Find(object, ...) abort
  if type(a:object) == type(0)
    let name = bufname(a:object)
    return s:PlatformSlash(name =~# '^$\|^/\|^\a\+:' ? name : getcwd() . '/' . name)
  elseif a:object =~# '^[~$]'
    let prefix = matchstr(a:object, '^[~$]\i*')
    let owner = expand(prefix)
    return s:PlatformSlash((len(owner) ? owner : prefix) . strpart(a:object, len(prefix)))
  elseif s:Slash(a:object) =~# '^$\|^/\|^\%(\a\a\+:\).*\%(//\|::\)' . (has('win32') ? '\|^\a:/' : '')
    return s:PlatformSlash(a:object)
  elseif s:Slash(a:object) =~# '^\.\.\=\%(/\|$\)'
    return s:PlatformSlash(simplify(getcwd() . '/' . a:object))
  endif
  let dir = a:0 ? a:1 : s:Dir()
  if empty(dir)
    let file = matchstr(a:object, '^\%(:\d:\|[^:]*:\)\zs.*', '', '')
    let dir = FugitiveExtractGitDir(file)
    if empty(dir)
      return fnamemodify(len(file) ? file : a:object, ':p')
    endif
  endif
  let rev = s:Slash(a:object)
  let tree = s:Tree(dir)
  let base = len(tree) ? tree : 'fugitive://' . dir . '//0'
  if rev ==# '.git'
    let f = len(tree) ? tree . '/.git' : dir
  elseif rev =~# '^\.git/'
    let f = substitute(rev, '^\.git', '', '')
    let cdir = fugitive#CommonDir(dir)
    if f =~# '^/\.\./\.\.\%(/\|$\)'
      let f = simplify(len(tree) ? tree . f[3:-1] : dir . f)
    elseif f =~# '^/\.\.\%(/\|$\)'
      let f = base . f[3:-1]
    elseif cdir !=# dir && (
          \ f =~# '^/\%(config\|hooks\|info\|logs/refs\|objects\|refs\|worktrees\)\%(/\|$\)' ||
          \ f !~# '^/\%(index$\|index\.lock$\|\w*MSG$\|\w*HEAD$\|logs/\w*HEAD$\|logs$\|rebase-\w\+\)\%(/\|$\)' && getftime(dir . f) < 0 && getftime(cdir . f) >= 0)
      let f = simplify(cdir . f)
    else
      let f = simplify(dir . f)
    endif
  elseif rev ==# ':/'
    let f = base
  elseif rev =~# '^\.\%(/\|$\)'
    let f = base . rev[1:-1]
  elseif rev =~# '^::\%(/\|\a\+\:\)'
    let f = rev[2:-1]
  elseif rev =~# '^::\.\.\=\%(/\|$\)'
    let f = simplify(getcwd() . '/' . rev[2:-1])
  elseif rev =~# '^::'
    let f = base . '/' . rev[2:-1]
  elseif rev =~# '^:\%([0-3]:\)\=\.\.\=\%(/\|$\)\|^:[0-3]:\%(/\|\a\+:\)'
    let f = rev =~# '^:\%([0-3]:\)\=\.' ? simplify(getcwd() . '/' . matchstr(rev, '\..*')) : rev[3:-1]
    if s:cpath(base . '/', (f . '/')[0 : len(base)])
      let f = 'fugitive://' . dir . '//' . +matchstr(rev, '^:\zs\d\ze:') . '/' . strpart(f, len(base) + 1)
    else
      let altdir = FugitiveExtractGitDir(f)
      if len(altdir) && !s:cpath(dir, altdir)
        return fugitive#Find(a:object, altdir)
      endif
    endif
  elseif rev =~# '^:[0-3]:'
    let f = 'fugitive://' . dir . '//' . rev[1] . '/' . rev[3:-1]
  elseif rev ==# ':'
    if $GIT_INDEX_FILE =~# '/[^/]*index[^/]*\.lock$' && s:cpath(fnamemodify($GIT_INDEX_FILE,':p')[0:strlen(dir)]) ==# s:cpath(dir . '/') && filereadable($GIT_INDEX_FILE)
      let f = fnamemodify($GIT_INDEX_FILE, ':p')
    else
      let f = fugitive#Find('.git/index', dir)
    endif
  elseif rev =~# '^:(\%(top\|top,literal\|literal,top\|literal\))'
    let f = matchstr(rev, ')\zs.*')
    if f=~# '^\.\.\=\%(/\|$\)'
      let f = simplify(getcwd() . '/' . f)
    elseif f !~# '^/\|^\%(\a\a\+:\).*\%(//\|::\)' . (has('win32') ? '\|^\a:/' : '')
      let f = base . '/' . f
    endif
  elseif rev =~# '^:/\@!'
    let f = 'fugitive://' . dir . '//0/' . rev[1:-1]
  else
    if rev =~# 'HEAD$\|^refs/' && rev !~# ':'
      let cdir = rev =~# '^refs/' ? fugitive#CommonDir(dir) : dir
      if filereadable(cdir . '/' . rev)
        let f = simplify(cdir . '/' . rev)
      endif
    endif
    if !exists('f')
      let commit = substitute(matchstr(rev, '^[^:]\+\|^:.*'), '^@\%($\|[~^]\|@{\)\@=', 'HEAD', '')
      let file = substitute(matchstr(rev, '^[^:]\+\zs:.*'), '^:', '/', '')
      if file =~# '^/\.\.\=\%(/\|$\)\|^//\|^/\a\+:'
        let file = file =~# '^/\.' ? simplify(getcwd() . file) : file[1:-1]
        if s:cpath(base . '/', (file . '/')[0 : len(base)])
          let file = '/' . strpart(file, len(base) + 1)
        else
          let altdir = FugitiveExtractGitDir(file)
          if len(altdir) && !s:cpath(dir, altdir)
            return fugitive#Find(a:object, altdir)
          endif
          return file
        endif
      endif
      if commit !~# '^[0-9a-f]\{40,\}$'
        let commit = matchstr(s:ChompDefault('', [dir, 'rev-parse', '--verify', commit, '--']), '\<[0-9a-f]\{40,\}\>')
      endif
      if len(commit)
        let f = 'fugitive://' . dir . '//' . commit . file
      else
        let f = base . '/' . substitute(rev, '^:/:\=\|^[^:]\+:', '', '')
      endif
    endif
  endif
  return s:PlatformSlash(f)
endfunction

function! s:Generate(rev, ...) abort
  let dir = a:0 ? a:1 : s:Dir()
  let tree = s:Tree(dir)
  let object = a:rev
  if a:rev =~# '^/\.git\%(/\|$\)'
    let object = a:rev[1:-1]
  elseif a:rev =~# '^/' && len(tree) && getftime(tree . a:rev) >= 0 && getftime(a:rev) < 0
    let object = ':(top)' . a:rev[1:-1]
  endif
  return fugitive#Find(object, dir)
endfunction

function! s:DotRelative(path, ...) abort
  let cwd = a:0 ? a:1 : getcwd()
  let path = substitute(a:path, '^[~$]\i*', '\=expand(submatch(0))', '')
  if len(cwd) && s:cpath(cwd . '/', (path . '/')[0 : len(cwd)])
    return '.' . strpart(path, len(cwd))
  endif
  return a:path
endfunction

function! fugitive#Object(...) abort
  let dir = a:0 > 1 ? a:2 : s:Dir()
  let [fdir, rev] = s:DirRev(a:0 ? a:1 : @%)
  if s:cpath(dir) !=# s:cpath(fdir)
    let rev = ''
  endif
  let tree = s:Tree(dir)
  if empty(rev) && empty(tree)
  elseif empty(rev)
    let rev = fugitive#Path(a:0 ? a:1 : @%, './', dir)
    let cdir = fugitive#CommonDir(dir)
    if rev =~# '^\./\.git/refs/\%(tags\|heads\|remotes\)/.\|^\./\.git/\w*HEAD$'
      let rev = rev[7:-1]
    elseif s:cpath(cdir . '/refs/', rev[0 : len(cdir)])
      let rev = strpart(rev, len(cdir)+1)
    elseif rev =~# '^\./.git\%(/\|$\)'
      return fnamemodify(a:0 ? a:1 : @%, ':p')
    endif
  endif
  if rev !~# '^\.\%(/\|$\)' || s:cpath(getcwd(), tree)
    return rev
  else
    return tree . rev[1:-1]
  endif
endfunction

let s:var = '\%(%\|#<\=\d\+\|##\=\)'
let s:flag = '\%(:[p8~.htre]\|:g\=s\(.\).\{-\}\1.\{-\}\1\)'
let s:expand = '\%(\(' . s:var . '\)\(' . s:flag . '*\)\(:S\)\=\)'

function! s:BufName(var) abort
  if a:var ==# '%'
    return bufname(get(b:, 'fugitive_blamed_bufnr', ''))
  elseif a:var =~# '^#\d*$'
    let nr = getbufvar(+a:var[1:-1], 'fugitive_blamed_bufnr', '')
    return bufname(nr ? nr : +a:var[1:-1])
  else
    return expand(a:var)
  endif
endfunction

function! s:ExpandVarLegacy(str) abort
  if get(g:, 'fugitive_legacy_quoting', 1)
    return substitute(a:str, '\\\ze[%#!]', '', 'g')
  else
    return a:str
  endif
endfunction

function! s:ExpandVar(other, var, flags, esc, ...) abort
  let cwd = a:0 ? a:1 : getcwd()
  if a:other =~# '^\'
    return a:other[1:-1]
  elseif a:other =~# '^'''
    return s:ExpandVarLegacy(substitute(a:other[1:-2], "''", "'", "g"))
  elseif a:other =~# '^"'
    return s:ExpandVarLegacy(substitute(a:other[1:-2], '""', '"', "g"))
  elseif a:other =~# '^!'
    let buffer = s:BufName(len(a:other) > 1 ? '#'. a:other[1:-1] : '%')
    let owner = s:Owner(buffer)
    return len(owner) ? owner : '@'
  endif
  let flags = a:flags
  let file = s:DotRelative(fugitive#Real(s:BufName(a:var)), cwd)
  while len(flags)
    let flag = matchstr(flags, s:flag)
    let flags = strpart(flags, len(flag))
    if flag ==# ':.'
      let file = s:DotRelative(file, cwd)
    else
      let file = fnamemodify(file, flag)
    endif
  endwhile
  let file = s:Slash(file)
  return (len(a:esc) ? shellescape(file) : file)
endfunction

function! s:Expand(rev, ...) abort
  if a:rev =~# '^:0$'
    call s:throw('Use ' . string(':%') . ' instead of ' . string(a:rev))
  elseif a:rev =~# '^:[1-3]$'
    call s:throw('Use ' . string(a:rev . ':%') . ' instead of ' . string(a:rev))
  elseif a:rev =~# '^@{' || a:rev =~# '^\^[0-9~^{]\|^\~[0-9~^]\|^\^$'
    call s:throw('Use ' . string('!' . a:rev . ':%') . ' instead of ' . string(a:rev))
  elseif a:rev =~# '^-'
    call s:throw('Use ' . string('!' . a:rev[1:-1] . ':%') . ' instead of ' . string(a:rev))
  elseif a:rev =~# '^>[~^]\|^>@{\|^>:\d$'
    let file = 'HEAD' . a:rev[1:-1] . ':%'
  elseif a:rev =~# '^>[> ]\@!'
    let file = a:rev[1:-1] . ':%'
  else
    let file = a:rev
  endif
  return substitute(file,
        \ '\(\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\)\|' . s:expand,
        \ '\=s:ExpandVar(submatch(1),submatch(2),submatch(3),"", a:0 ? a:1 : getcwd())', 'g')
endfunction

function! fugitive#Expand(object) abort
  return substitute(a:object,
        \ '\(\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\)\|' . s:expand,
        \ '\=s:ExpandVar(submatch(1),submatch(2),submatch(3),submatch(5))', 'g')
endfunction

function! s:ExpandSplit(string, ...) abort
  let list = []
  let string = a:string
  let handle_bar = a:0 && a:1
  let dquote = handle_bar ? '"\%([^"]\|""\|\\"\)*"\|' : ''
  let cwd = a:0 > 1 ? a:2 : getcwd()
  while string =~# '\S'
    if handle_bar && string =~# '^\s*|'
      return [list, substitute(string, '^\s*', '', '')]
    endif
    let arg = matchstr(string, '^\s*\%(' . dquote . '''[^'']*''\|\\.\|[^[:space:] ' . (handle_bar ? '|' : '') . ']\)\+')
    let string = strpart(string, len(arg))
    let arg = substitute(arg, '^\s\+', '', '')
    if !exists('seen_separator')
      let arg = substitute(arg, '^\%([^:.][^:]*:\|^:\|^:[0-3]:\)\=\zs\.\.\=\%(/.*\)\=$',
            \ '\=s:DotRelative(s:Slash(simplify(getcwd() . "/" . submatch(0))), cwd)', '')
    endif
    let arg = substitute(arg,
          \ '\(' . dquote . '''\%(''''\|[^'']\)*''\|\\[' . s:fnameescape . ']\|^\\[>+-]\|!\d*\)\|' . s:expand,
          \ '\=s:ExpandVar(submatch(1),submatch(2),submatch(3),submatch(5), cwd)', 'g')
    call add(list, arg)
    if arg ==# '--'
      let seen_separator = 1
    endif
  endwhile
  return handle_bar ? [list, ''] : list
endfunction

function! s:SplitExpand(string, ...) abort
  return s:ExpandSplit(a:string, 0, a:0 ? a:1 : getcwd())
endfunction

function! s:SplitExpandChain(string, ...) abort
  return s:ExpandSplit(a:string, 1, a:0 ? a:1 : getcwd())
endfunction

let s:trees = {}
let s:indexes = {}
function! s:TreeInfo(dir, commit) abort
  if a:commit =~# '^:\=[0-3]$'
    let index = get(s:indexes, a:dir, [])
    let newftime = getftime(fugitive#Find('.git/index', a:dir))
    if get(index, 0, -1) < newftime
      let [lines, exec_error] = s:LinesError([a:dir, 'ls-files', '--stage', '--'])
      let s:indexes[a:dir] = [newftime, {'0': {}, '1': {}, '2': {}, '3': {}}]
      if exec_error
        return [{}, -1]
      endif
      for line in lines
        let [info, filename] = split(line, "\t")
        let [mode, sha, stage] = split(info, '\s\+')
        let s:indexes[a:dir][1][stage][filename] = [newftime, mode, 'blob', sha, -2]
        while filename =~# '/'
          let filename = substitute(filename, '/[^/]*$', '', '')
          let s:indexes[a:dir][1][stage][filename] = [newftime, '040000', 'tree', '', 0]
        endwhile
      endfor
    endif
    return [get(s:indexes[a:dir][1], a:commit[-1:-1], {}), newftime]
  elseif a:commit =~# '^\x\{40,\}$'
    if !has_key(s:trees, a:dir)
      let s:trees[a:dir] = {}
    endif
    if !has_key(s:trees[a:dir], a:commit)
      let [ftime, exec_error] = s:ChompError([a:dir, 'log', '-1', '--pretty=format:%ct', a:commit, '--'])
      if exec_error
        let s:trees[a:dir][a:commit] = [{}, -1]
        return s:trees[a:dir][a:commit]
      endif
      let s:trees[a:dir][a:commit] = [{}, +ftime]
      let [lines, exec_error] = s:LinesError([a:dir, 'ls-tree', '-rtl', '--full-name', a:commit, '--'])
      if exec_error
        return s:trees[a:dir][a:commit]
      endif
      for line in lines
        let [info, filename] = split(line, "\t")
        let [mode, type, sha, size] = split(info, '\s\+')
        let s:trees[a:dir][a:commit][0][filename] = [+ftime, mode, type, sha, +size, filename]
      endfor
    endif
    return s:trees[a:dir][a:commit]
  endif
  return [{}, -1]
endfunction

function! s:PathInfo(url) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  if empty(dir) || !get(g:, 'fugitive_file_api', 1)
    return [-1, '000000', '', '', -1]
  endif
  let path = substitute(file[1:-1], '/*$', '', '')
  let [tree, ftime] = s:TreeInfo(dir, commit)
  let entry = empty(path) ? [ftime, '040000', 'tree', '', -1] : get(tree, path, [])
  if empty(entry) || file =~# '/$' && entry[2] !=# 'tree'
    return [-1, '000000', '', '', -1]
  else
    return entry
  endif
endfunction

function! fugitive#simplify(url) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  if empty(dir)
    return ''
  endif
  if file =~# '/\.\.\%(/\|$\)'
    let tree = s:Tree(dir)
    if len(tree)
      let path = simplify(tree . file)
      if strpart(path . '/', 0, len(tree) + 1) !=# tree . '/'
        return s:PlatformSlash(path)
      endif
    endif
  endif
  return s:PlatformSlash('fugitive://' . simplify(dir) . '//' . commit . simplify(file))
endfunction

function! fugitive#resolve(url) abort
  let url = fugitive#simplify(a:url)
  if url =~? '^fugitive:'
    return url
  else
    return resolve(url)
  endif
endfunction

function! fugitive#getftime(url) abort
  return s:PathInfo(a:url)[0]
endfunction

function! fugitive#getfsize(url) abort
  let entry = s:PathInfo(a:url)
  if entry[4] == -2 && entry[2] ==# 'blob' && len(entry[3])
    let dir = s:DirCommitFile(a:url)[0]
    let entry[4] = +s:ChompDefault(-1, [dir, 'cat-file', '-s', entry[3]])
  endif
  return entry[4]
endfunction

function! fugitive#getftype(url) abort
  return get({'tree': 'dir', 'blob': 'file'}, s:PathInfo(a:url)[2], '')
endfunction

function! fugitive#filereadable(url) abort
  return s:PathInfo(a:url)[2] ==# 'blob'
endfunction

function! fugitive#filewritable(url) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  if commit !~# '^\d$' || !filewritable(fugitive#Find('.git/index', dir))
    return 0
  endif
  return s:PathInfo(a:url)[2] ==# 'blob' ? 1 : 2
endfunction

function! fugitive#isdirectory(url) abort
  return s:PathInfo(a:url)[2] ==# 'tree'
endfunction

function! fugitive#getfperm(url) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  let perm = getfperm(dir)
  let fperm = s:PathInfo(a:url)[1]
  if fperm ==# '040000'
    let fperm = '000755'
  endif
  if fperm !~# '[15]'
    let perm = tr(perm, 'x', '-')
  endif
  if fperm !~# '[45]$'
    let perm = tr(perm, 'rw', '--')
  endif
  if commit !~# '^\d$'
    let perm = tr(perm, 'w', '-')
  endif
  return perm ==# '---------' ? '' : perm
endfunction

function! fugitive#setfperm(url, perm) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  let entry = s:PathInfo(a:url)
  let perm = fugitive#getfperm(a:url)
  if commit !~# '^\d$' || entry[2] !=# 'blob' ||
      \ substitute(perm, 'x', '-', 'g') !=# substitute(a:perm, 'x', '-', 'g')
    return -2
  endif
  let exec_error = s:SystemError([dir, 'update-index', '--index-info'],
        \ (a:perm =~# 'x' ? '000755 ' : '000644 ') . entry[3] . ' ' . commit . "\t" . file[1:-1])[1]
  return exec_error ? -1 : 0
endfunction

function! s:TempCmd(out, cmd) abort
  let prefix = ''
  try
    let cmd = (type(a:cmd) == type([]) ? fugitive#Prepare(a:cmd) : a:cmd)
    let redir = ' > ' . a:out
    if s:winshell()
      let cmd_escape_char = &shellxquote == '(' ?  '^' : '^^^'
      return s:SystemError('cmd /c "' . prefix . s:gsub(cmd, '[<>]', cmd_escape_char . '&') . redir . '"')
    elseif &shell =~# 'fish'
      return s:SystemError(' begin;' . prefix . cmd . redir . ';end ')
    else
      return s:SystemError(' (' . prefix . cmd . redir . ') ')
    endif
  endtry
endfunction

if !exists('s:blobdirs')
  let s:blobdirs = {}
endif
function! s:BlobTemp(url) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  if empty(file)
    return ''
  endif
  if !has_key(s:blobdirs, dir)
    let s:blobdirs[dir] = tempname()
  endif
  let tempfile = s:blobdirs[dir] . '/' . commit . file
  let tempparent = fnamemodify(tempfile, ':h')
  if !isdirectory(tempparent)
    call mkdir(tempparent, 'p')
  endif
  if commit =~# '^\d$' || !filereadable(tempfile)
    let rev = s:DirRev(a:url)[1]
    let exec_error = s:TempCmd(tempfile, [dir, 'cat-file', 'blob', rev])[1]
    if exec_error
      call delete(tempfile)
      return ''
    endif
  endif
  return s:Resolve(tempfile)
endfunction

function! fugitive#readfile(url, ...) abort
  let entry = s:PathInfo(a:url)
  if entry[2] !=# 'blob'
    return []
  endif
  let temp = s:BlobTemp(a:url)
  if empty(temp)
    return []
  endif
  return call('readfile', [temp] + a:000)
endfunction

function! fugitive#writefile(lines, url, ...) abort
  let url = type(a:url) ==# type('') ? a:url : ''
  let [dir, commit, file] = s:DirCommitFile(url)
  let entry = s:PathInfo(url)
  if commit =~# '^\d$' && entry[2] !=# 'tree'
    let temp = tempname()
    if a:0 && a:1 =~# 'a' && entry[2] ==# 'blob'
      call writefile(fugitive#readfile(url, 'b'), temp, 'b')
    endif
    call call('writefile', [a:lines, temp] + a:000)
    let [hash, exec_error] = s:ChompError([dir, 'hash-object', '-w', temp])
    let mode = len(entry[1]) ? entry[1] : '100644'
    if !exec_error && hash =~# '^\x\{40,\}$'
      let exec_error = s:SystemError([dir, 'update-index', '--index-info'],
            \ mode . ' ' . hash . ' ' . commit . "\t" . file[1:-1])[1]
      if !exec_error
        return 0
      endif
    endif
  endif
  return call('writefile', [a:lines, a:url] + a:000)
endfunction

let s:globsubs = {
      \ '/**/': '/\%([^./][^/]*/\)*',
      \ '/**': '/\%([^./][^/]\+/\)*[^./][^/]*',
      \ '**/': '[^/]*\%(/[^./][^/]*\)*',
      \ '**': '.*',
      \ '/*': '/[^/.][^/]*',
      \ '*': '[^/]*',
      \ '?': '[^/]'}
function! fugitive#glob(url, ...) abort
  let [dirglob, commit, glob] = s:DirCommitFile(a:url)
  let append = matchstr(glob, '/*$')
  let glob = substitute(glob, '/*$', '', '')
  let pattern = '^' . substitute(glob, '/\=\*\*/\=\|/\=\*\|[.?\$]\|^^', '\=get(s:globsubs, submatch(0), "\\" . submatch(0))', 'g')[1:-1] . '$'
  let results = []
  for dir in dirglob =~# '[*?]' ? split(glob(dirglob), "\n") : [dirglob]
    if empty(dir) || !get(g:, 'fugitive_file_api', 1) || !filereadable(fugitive#Find('.git/HEAD', dir))
      continue
    endif
    let files = items(s:TreeInfo(dir, commit)[0])
    if len(append)
      call filter(files, 'v:val[1][2] ==# "tree"')
    endif
    call map(files, 'v:val[0]')
    call filter(files, 'v:val =~# pattern')
    let prepend = 'fugitive://' . dir . '//' . substitute(commit, '^:', '', '') . '/'
    call sort(files)
    call map(files, 's:PlatformSlash(prepend . v:val . append)')
    call extend(results, files)
  endfor
  if a:0 > 1 && a:2
    return results
  else
    return join(results, "\n")
  endif
endfunction

function! fugitive#delete(url, ...) abort
  let [dir, commit, file] = s:DirCommitFile(a:url)
  if a:0 && len(a:1) || commit !~# '^\d$'
    return -1
  endif
  let entry = s:PathInfo(a:url)
  if entry[2] !=# 'blob'
    return -1
  endif
  let exec_error = s:SystemError([dir, 'update-index', '--index-info'],
        \ '000000 0000000000000000000000000000000000000000 ' . commit . "\t" . file[1:-1])[1]
  return exec_error ? -1 : 0
endfunction

" Section: Buffer Object

let s:buffer_prototype = {}

function! fugitive#buffer(...) abort
  let buffer = {'#': bufnr(a:0 ? a:1 : '%')}
  call extend(buffer, s:buffer_prototype, 'keep')
  return buffer
endfunction

function! s:buffer_getvar(var) dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().getvar() which has been removed. Replace it with the local variable or getbufvar()"
endfunction

function! s:buffer_getline(lnum) dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().getline() which has been removed. Replace it with getline() or getbufline()"
endfunction

function! s:buffer_repo() dict abort
  return fugitive#repo(self['#'])
endfunction

function! s:buffer_type(...) dict abort
  return getbufvar(self['#'], 'fugitive_type')
endfunction

function! s:buffer_spec() dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().spec() which has been removed. Replace it with bufname(), expand('%:p'), etc"
endfunction

function! s:buffer_name() dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().name() which has been removed. Replace it with bufname(), expand('%:p'), etc"
endfunction

function! s:buffer_commit() dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().commit() which has been removed. Replace it with matchstr(FugitiveParse()[0], '^\x\+')"
endfunction

function! s:buffer_relative(...) dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().relative() which has been removed. Replace it with FugitivePath(@%, " . string(a:0 ? a:1 : '') . ")"
endfunction

function! s:buffer_path(...) dict abort
  throw "fugitive: A third-party plugin or vimrc is calling fugitive#buffer().path() which has been removed. Replace it with FugitivePath(@%, " . string(a:0 ? a:1 : '') . ")"
endfunction

call s:add_methods('buffer',['getvar','getline','repo','type','spec','name','commit','path','relative'])

" Section: Completion

function! s:FilterEscape(items, ...) abort
  let items = copy(a:items)
  if a:0 && type(a:1) == type('')
    call filter(items, 'strpart(v:val, 0, strlen(a:1)) ==# a:1')
  endif
  return map(items, 's:fnameescape(v:val)')
endfunction

function! s:GlobComplete(lead, pattern) abort
  if a:lead ==# '/'
    return []
  elseif v:version >= 704
    let results = glob(a:lead . a:pattern, 0, 1)
  else
    let results = split(glob(a:lead . a:pattern), "\n")
  endif
  call map(results, 'v:val !~# "/$" && isdirectory(v:val) ? v:val."/" : v:val')
  call map(results, 'v:val[ strlen(a:lead) : -1 ]')
  return results
endfunction

function! fugitive#CompletePath(base, ...) abort
  let dir = a:0 == 1 ? a:1 : a:0 == 3 ? a:3 : s:Dir()
  let tree = s:Tree(dir) . '/'
  let strip = '^\%(:/:\=\|:(top)\|:(top,literal)\|:(literal,top)\|:(literal)\)'
  let base = substitute(a:base, strip, '', '')
  if base =~# '^\.git/'
    let pattern = s:gsub(base[5:-1], '/', '*&').'*'
    let matches = s:GlobComplete(dir . '/', pattern)
    let cdir = fugitive#CommonDir(dir)
    if len(cdir) && s:cpath(dir) !=# s:cpath(cdir)
      call extend(matches, s:GlobComplete(cdir . '/', pattern))
    endif
    call s:Uniq(matches)
    call map(matches, "'.git/' . v:val")
  elseif base =~# '^\~/'
    let matches = map(s:GlobComplete(expand('~/'), base[2:-1] . '*'), '"~/" . v:val')
  elseif a:base =~# '^/\|^\a\+:\|^\.\.\=/\|^:(literal)'
    let matches = s:GlobComplete('', base . '*')
  elseif len(tree) > 1
    let matches = s:GlobComplete(tree, s:gsub(base, '/', '*&').'*')
  else
    let matches = []
  endif
  call map(matches, 's:fnameescape(s:Slash(matchstr(a:base, strip) . v:val))')
  return matches
endfunction

function! fugitive#PathComplete(...) abort
  return call('fugitive#CompletePath', a:000)
endfunction

function! fugitive#CompleteObject(base, ...) abort
  let dir = a:0 == 1 ? a:1 : a:0 == 3 ? a:3 : s:Dir()
  let cwd = getcwd()
  let tree = s:Tree(dir) . '/'
  let subdir = ''
  if len(tree) > 1 && s:cpath(tree, cwd[0 : len(tree) - 1])
    let subdir = strpart(cwd, len(tree)) . '/'
  endif

  if a:base =~# '^\.\=/\|^:(' || a:base !~# ':'
    let results = []
    if a:base =~# '^refs/'
      let results += map(s:GlobComplete(fugitive#CommonDir(dir) . '/', a:base . '*'), 's:Slash(v:val)')
    elseif a:base !~# '^\.\=/\|^:('
      let heads = ['HEAD', 'ORIG_HEAD', 'FETCH_HEAD', 'MERGE_HEAD', 'refs/']
      let heads += sort(s:LinesError(["rev-parse","--symbolic","--branches","--tags","--remotes"], dir)[0])
      if filereadable(fugitive#CommonDir(dir) . '/refs/stash')
        let heads += ["stash"]
        let heads += sort(s:LinesError(["stash","list","--pretty=format:%gd"], dir)[0])
      endif
      call filter(heads,'v:val[ 0 : strlen(a:base)-1 ] ==# a:base')
      let results += heads
    endif
    call map(results, 's:fnameescape(v:val)')
    if !empty(tree)
      let results += a:0 == 1 ? fugitive#CompletePath(a:base, dir) : fugitive#CompletePath(a:base)
    endif
    return results

  elseif a:base =~# '^:'
    let entries = s:LinesError(['ls-files','--stage'], dir)[0]
    if a:base =~# ':\./'
      call map(entries, 'substitute(v:val, "\\M\t\\zs" . subdir, "./", "")')
    endif
    call map(entries,'s:sub(v:val,".*(\\d)\\t(.*)",":\\1:\\2")')
    if a:base !~# '^:[0-3]\%(:\|$\)'
      call filter(entries,'v:val[1] == "0"')
      call map(entries,'v:val[2:-1]')
    endif

  else
    let tree = matchstr(a:base, '.*[:/]')
    let entries = s:LinesError(['ls-tree', substitute(tree,  ':\zs\./', '\=subdir', '')], dir)[0]
    call map(entries,'s:sub(v:val,"^04.*\\zs$","/")')
    call map(entries,'tree.s:sub(v:val,".*\t","")')

  endif
  return s:FilterEscape(entries, a:base)
endfunction

function! s:CompleteSubcommand(subcommand, A, L, P, ...) abort
  let pre = strpart(a:L, 0, a:P)
  if pre =~# ' -- '
    return fugitive#CompletePath(a:A)
  elseif a:A =~# '^-' || a:A is# 0
    return s:FilterEscape(split(s:ChompDefault('', a:subcommand, '--git-completion-helper'), ' '), a:A)
  elseif !a:0
    return fugitive#CompleteObject(a:A, s:Dir())
  elseif type(a:1) == type(function('tr'))
    return call(a:1, [a:A, a:L, a:P])
  else
    return s:FilterEscape(a:1, a:A)
  endif
endfunction

function! s:CompleteRevision(A, L, P) abort
  return s:FilterEscape(['HEAD', 'FETCH_HEAD', 'MERGE_HEAD', 'ORIG_HEAD'] +
        \ s:LinesError('rev-parse', '--symbolic', '--branches', '--tags', '--remotes')[0], a:A)
endfunction

function! s:CompleteRemote(A, L, P) abort
  let remote = matchstr(a:L, '\u\w*[! ] *\zs\S\+\ze ')
  if !empty(remote)
    let matches = s:LinesError('ls-remote', remote)[0]
    call filter(matches, 'v:val =~# "\t" && v:val !~# "{"')
    call map(matches, 's:sub(v:val, "^.*\t%(refs/%(heads/|tags/)=)=", "")')
  else
    let matches = s:LinesError('remote')[0]
  endif
  return s:FilterEscape(matches, a:A)
endfunction

" Section: Buffer auto-commands

function! s:ReplaceCmd(cmd) abort
  let temp = tempname()
  let [err, exec_error] = s:TempCmd(temp, a:cmd)
  if exec_error
    call s:throw((len(err) ? err : filereadable(temp) ? join(readfile(temp), ' ') : 'unknown error running ' . a:cmd))
  endif
  let temp = s:Resolve(temp)
  let fn = expand('%:p')
  silent exe 'keepalt file '.temp
  let modelines = &modelines
  try
    set modelines=0
    silent keepjumps noautocmd edit!
  finally
    let &modelines = modelines
    try
      silent exe 'keepalt file '.s:fnameescape(fn)
    catch /^Vim\%((\a\+)\)\=:E302:/
    endtry
    call delete(temp)
    if s:cpath(fnamemodify(bufname('$'), ':p'), temp)
      silent execute 'bwipeout '.bufnr('$')
    endif
  endtry
endfunction

function! s:QueryLog(refspec) abort
  let lines = s:LinesError(['log', '-n', '256', '--format=%h%x09%s', a:refspec, '--'])[0]
  call map(lines, 'split(v:val, "\t")')
  call map(lines, '{"type": "Log", "commit": v:val[0], "subject": v:val[-1]}')
  return lines
endfunction

function! s:FormatLog(dict) abort
  return a:dict.commit . ' ' . a:dict.subject
endfunction

function! s:FormatRebase(dict) abort
  return a:dict.status . ' ' . a:dict.commit . ' ' . a:dict.subject
endfunction

function! s:FormatFile(dict) abort
  return a:dict.status . ' ' . a:dict.filename
endfunction

function! s:Format(val) abort
  if type(a:val) == type({})
    return s:Format{a:val.type}(a:val)
  elseif type(a:val) == type([])
    return map(copy(a:val), 's:Format(v:val)')
  else
    return '' . a:val
  endif
endfunction

function! s:AddHeader(key, value) abort
  if empty(a:value)
    return
  endif
  let before = 1
  while !empty(getline(before))
    let before += 1
  endwhile
  call append(before - 1, [a:key . ':' . (len(a:value) ? ' ' . a:value : '')])
  if before == 1 && line('$') == 2
    silent 2delete _
  endif
endfunction

function! s:AddSection(label, lines, ...) abort
  let note = a:0 ? a:1 : ''
  if empty(a:lines) && empty(note)
    return
  endif
  call append(line('$'), ['', a:label . (len(note) ? ': ' . note : ' (' . len(a:lines) . ')')] + s:Format(a:lines))
endfunction

function! fugitive#BufReadStatus() abort
  let amatch = s:Slash(expand('%:p'))
  let b:fugitive_type = 'index'
  unlet! b:fugitive_reltime
  try
    silent doautocmd BufReadPre
    let cmd = [fnamemodify(amatch, ':h')]
    setlocal noro ma nomodeline buftype=nowrite
    if s:cpath(fnamemodify($GIT_INDEX_FILE !=# '' ? $GIT_INDEX_FILE : fugitive#Find('.git/index'), ':p')) !=# s:cpath(amatch)
      let cmd += ['-c', 'GIT_INDEX_FILE=' . amatch]
    endif
    let cmd += ['status', '--porcelain', '-bz']
    let [output, message, exec_error] = s:NullError(cmd)
    if exec_error
      throw 'fugitive: ' . message
    endif

    let head = matchstr(output[0], '^## \zs\S\+\ze\%($\| \[\)')
    let pull = ''
    if head =~# '\.\.\.'
      let [head, pull] = split(head, '\.\.\.')
      let branch = head
    elseif head ==# 'HEAD' || empty(head)
      let head = FugitiveHead(11)
      let branch = ''
    else
      let branch = head
    endif

    let b:fugitive_status = {'Staged': {}, 'Unstaged': {}}
    let [staged, unstaged, untracked] = [[], [], []]
    let i = 0
    while i < len(output)
      let line = output[i]
      let file = line[3:-1]
      let files = file
      let i += 1
      if line[2] !=# ' '
        continue
      endif
      if line[0:1] =~# '[RC]'
        let files = output[i] . ' -> ' . file
        let i += 1
      endif
      if line[0] !~# '[ ?!#]'
        call add(staged, {'type': 'File', 'status': line[0], 'filename': files})
        let b:fugitive_status['Staged'][files] = line[0]
      endif
      if line[1] =~# '?'
        call add(untracked, {'type': 'File', 'status': line[1], 'filename': files})
        let b:fugitive_status['Unstaged'][files] = line[1]
      elseif line[1] !~# '[ !#]'
        call add(unstaged, {'type': 'File', 'status': line[1], 'filename': files})
        let b:fugitive_status['Unstaged'][files] = line[1]
      endif
    endwhile

    for dict in staged
      let b:fugitive_status['Staged'][dict.filename] = dict.status
    endfor
    for dict in unstaged
      let b:fugitive_status['Unstaged'][dict.filename] = dict.status
    endfor

    let config = fugitive#Config()

    let pull_type = 'Pull'
    if len(pull)
      let rebase = fugitive#Config('branch.' . branch . '.rebase', config)
      if empty(rebase)
        let rebase = fugitive#Config('pull.rebase', config)
      endif
      if rebase =~# '^\%(true\|yes\|on\|1\|interactive\)$'
        let pull_type = 'Rebase'
      elseif rebase =~# '^\%(false\|no|off\|0\|\)$'
        let pull_type = 'Merge'
      endif
    endif

    let push_remote = fugitive#Config('branch.' . branch . '.pushRemote', config)
    if empty(push_remote)
      let push_remote = fugitive#Config('remote.pushDefault', config)
    endif
    let push = len(push_remote) && len(branch) ? push_remote . '/' . branch : ''
    if empty(push)
      let push = pull
    endif

    if len(pull)
      let unpulled = s:QueryLog(head . '..' . pull)
    else
      let unpulled = []
    endif
    if len(push)
      let unpushed = s:QueryLog(push . '..' . head)
    else
      let unpushed = []
    endif

    if isdirectory(fugitive#Find('.git/rebase-merge/'))
      let rebasing_dir = fugitive#Find('.git/rebase-merge/')
    elseif isdirectory(fugitive#Find('.git/rebase-apply/'))
      let rebasing_dir = fugitive#Find('.git/rebase-apply/')
    endif

    let rebasing = []
    let rebasing_head = 'detached HEAD'
    if exists('rebasing_dir') && filereadable(rebasing_dir . 'git-rebase-todo')
      let rebasing_head = substitute(readfile(rebasing_dir . 'head-name')[0], '\C^refs/heads/', '', '')
      let len = 11
      let lines = readfile(rebasing_dir . 'git-rebase-todo')
      for line in lines
        let hash = matchstr(line, '^[^a-z].*\s\zs[0-9a-f]\{4,\}\ze\.\.')
        if len(hash)
          let len = len(hash)
          break
        endif
      endfor
      if getfsize(rebasing_dir . 'done') > 0
        let done = readfile(rebasing_dir . 'done')
        call map(done, 'substitute(v:val, ''^\l\+\>'', "done", "")')
        let done[-1] = substitute(done[-1], '^\l\+\>', 'stop', '')
        let lines = done + lines
      endif
      call reverse(lines)
      for line in lines
        let match = matchlist(line, '^\(\l\+\)\s\+\(\x\{4,\}\)\s\+\(.*\)')
        if len(match) && match[1] !~# 'exec\|merge\|label'
          call add(rebasing, {'type': 'Rebase', 'status': get(s:rebase_abbrevs, match[1], match[1]), 'commit': strpart(match[2], 0, len), 'subject': match[3]})
        endif
      endfor
    endif

    let b:fugitive_diff = {
          \ 'Staged': s:LinesError(['diff', '--color=never', '--no-ext-diff', '--no-prefix', '--cached'])[0],
          \ 'Unstaged': s:LinesError(['diff', '--color=never', '--no-ext-diff', '--no-prefix'])[0]}
    let expanded = get(b:, 'fugitive_expanded', {'Staged': {}, 'Unstaged': {}})
    let b:fugitive_expanded = {'Staged': {}, 'Unstaged': {}}

    silent keepjumps %delete_

    call s:AddHeader('Head', head)
    call s:AddHeader(pull_type, pull)
    if push !=# pull
      call s:AddHeader('Push', push)
    endif
    call s:AddSection('Rebasing ' . rebasing_head, rebasing)
    call s:AddSection('Untracked', untracked)
    call s:AddSection('Unstaged', unstaged)
    let unstaged_end = len(unstaged) ? line('$') : 0
    call s:AddSection('Staged', staged)
    let staged_end = len(staged) ? line('$') : 0
    call s:AddSection('Unpushed to ' . push, unpushed)
    call s:AddSection('Unpulled from ' . pull, unpulled)

    setlocal nomodified readonly noswapfile
    silent doautocmd BufReadPost
    setlocal nomodifiable
    if &bufhidden ==# ''
      setlocal bufhidden=delete
    endif
    let b:dispatch = ':Gfetch --all'
    call fugitive#MapJumps()
    let nowait = v:version >= 704 ? '<nowait>' : ''
    nunmap   <buffer>          P
    nunmap   <buffer>          ~
    nnoremap <buffer> <silent> [[ :<C-U>execute <SID>PreviousSection(v:count1)<CR>
    nnoremap <buffer> <silent> ]] :<C-U>execute <SID>NextSection(v:count1)<CR>
    exe "nnoremap <buffer> <silent>" nowait "- :<C-U>execute <SID>Do('Toggle',0)<CR>"
    exe "xnoremap <buffer> <silent>" nowait "- :<C-U>execute <SID>Do('Toggle',1)<CR>"
    exe "nnoremap <buffer> <silent>" nowait "s :<C-U>execute <SID>Do('Stage',0)<CR>"
    exe "xnoremap <buffer> <silent>" nowait "s :<C-U>execute <SID>Do('Stage',1)<CR>"
    exe "nnoremap <buffer> <silent>" nowait "u :<C-U>execute <SID>Do('Unstage',0)<CR>"
    exe "xnoremap <buffer> <silent>" nowait "u :<C-U>execute <SID>Do('Unstage',1)<CR>"
    nnoremap <buffer> <silent> gu :<C-U>exe <SID>StageJump(v:count, 'Unstaged')<CR>
    nnoremap <buffer> <silent> gU :<C-U>exe <SID>StageJump(v:count, 'Untracked')<CR>
    nnoremap <buffer> <silent> gs :<C-U>exe <SID>StageJump(v:count, 'Staged')<CR>
    nnoremap <buffer> <silent> gp :<C-U>exe <SID>StageJump(v:count, 'Unpushed')<CR>
    nnoremap <buffer> <silent> gP :<C-U>exe <SID>StageJump(v:count, 'Unpulled')<CR>
    nnoremap <buffer> <silent> C :<C-U>Gcommit<CR>:echohl WarningMsg<Bar>echo ':Gstatus C is deprecated in favor of cc'<Bar>echohl NONE<CR>
    nnoremap <buffer> <silent> a :<C-U>execute <SID>Do('Toggle',0)<CR>
    nnoremap <buffer> <silent> i :<C-U>execute <SID>StageIntend(v:count1)<CR>
    exe 'nnoremap <buffer> <silent>' nowait "= :<C-U>execute <SID>StageInline('toggle',line('.'),v:count)<CR>"
    exe 'nnoremap <buffer> <silent>' nowait "< :<C-U>execute <SID>StageInline('show',  line('.'),v:count)<CR>"
    exe 'nnoremap <buffer> <silent>' nowait "> :<C-U>execute <SID>StageInline('hide',  line('.'),v:count)<CR>"
    exe 'xnoremap <buffer> <silent>' nowait "= :<C-U>execute <SID>StageInline('toggle',line(\"'<\"),line(\"'>\")-line(\"'<\")+1)<CR>"
    exe 'xnoremap <buffer> <silent>' nowait "< :<C-U>execute <SID>StageInline('show',  line(\"'<\"),line(\"'>\")-line(\"'<\")+1)<CR>"
    exe 'xnoremap <buffer> <silent>' nowait "> :<C-U>execute <SID>StageInline('hide',  line(\"'<\"),line(\"'>\")-line(\"'<\")+1)<CR>"
    nnoremap <buffer> <silent> D :<C-U>execute <SID>StageDiff('Gdiffsplit')<CR>
    nnoremap <buffer> <silent> dd :<C-U>execute <SID>StageDiff('Gdiffsplit')<CR>
    nnoremap <buffer> <silent> dh :<C-U>execute <SID>StageDiff('Ghdiffsplit')<CR>
    nnoremap <buffer> <silent> ds :<C-U>execute <SID>StageDiff('Ghdiffsplit')<CR>
    nnoremap <buffer> <silent> dp :<C-U>execute <SID>StageDiffEdit()<CR>
    nnoremap <buffer> <silent> dv :<C-U>execute <SID>StageDiff('Gvdiffsplit')<CR>
    nnoremap <buffer> <silent> P :<C-U>execute <SID>StagePatch(line('.'),line('.')+v:count1-1)<CR>
    xnoremap <buffer> <silent> P :<C-U>execute <SID>StagePatch(line("'<"),line("'>"))<CR>
    if empty(mapcheck('q', 'n'))
      nnoremap <buffer> <silent> q :<C-U>if bufnr('$') == 1<Bar>quit<Bar>else<Bar>bdelete<Bar>endif<CR>
    endif
    exe 'nnoremap <buffer> <silent>' s:nowait "gq :<C-U>if bufnr('$') == 1<Bar>quit<Bar>else<Bar>bdelete<Bar>endif<CR>"
    nnoremap <buffer> <silent> R :echohl WarningMsg<Bar>echo 'Reloading is automatic.  Use :e to force'<Bar>echohl NONE<CR>
    nnoremap <buffer> <silent> U :<C-U>echoerr 'Changed to X'<CR>
    nnoremap <buffer> <silent> g<Bar> :<C-U>echoerr 'Changed to X'<CR>
    xnoremap <buffer> <silent> g<Bar> :<C-U>echoerr 'Changed to X'<CR>
    nnoremap <buffer> <silent> X :<C-U>execute <SID>StageDelete(line('.'),v:count)<CR>
    xnoremap <buffer> <silent> X :<C-U>execute <SID>StageDelete(line("'<"),line("'>")-line("'<")+1)<CR>
    nnoremap <buffer>          . :<C-U> <C-R>=<SID>StageArgs(0)<CR><Home>
    xnoremap <buffer>          . :<C-U> <C-R>=<SID>StageArgs(1)<CR><Home>
    nnoremap <buffer> <silent> <F1> :help fugitive-mappings<CR>
    setlocal filetype=fugitive

    for [lnum, section] in [[staged_end, 'Staged'], [unstaged_end, 'Unstaged']]
      while len(getline(lnum))
        let filename = matchstr(getline(lnum), '^[A-Z?] \zs.*')
        if has_key(expanded[section], filename)
          call s:StageInline('show', lnum)
        endif
        let lnum -= 1
      endwhile
    endfor

    let b:fugitive_reltime = reltime()
    return ''
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
endfunction

function! fugitive#FileReadCmd(...) abort
  let amatch = a:0 ? a:1 : expand('<amatch>')
  let [dir, rev] = s:DirRev(amatch)
  let line = a:0 > 1 ? a:2 : line("'[")
  if empty(dir)
    return 'noautocmd ' . line . 'read ' . s:fnameescape(amatch)
  endif
  if rev !~# ':'
    let cmd = fugitive#Prepare(dir, 'log', '--pretty=format:%B', '-1', rev, '--')
  else
    let cmd = fugitive#Prepare(dir, 'cat-file', '-p', rev)
  endif
  return line . 'read !' . escape(cmd, '!#%')
endfunction

function! fugitive#FileWriteCmd(...) abort
  let tmp = tempname()
  let amatch = a:0 ? a:1 : expand('<amatch>')
  let autype = a:0 > 1 ? 'Buf' : 'File'
  if exists('#' . autype . 'WritePre')
    execute 'doautocmd ' . autype . 'WritePre ' . s:fnameescape(amatch)
  endif
  try
    let [dir, commit, file] = s:DirCommitFile(amatch)
    if commit !~# '^[0-3]$' || !v:cmdbang && (line("'[") != 1 || line("']") != line('$'))
      return "noautocmd '[,']write" . (v:cmdbang ? '!' : '') . ' ' . s:fnameescape(amatch)
    endif
    silent execute "'[,']write !".fugitive#Prepare(dir, 'hash-object', '-w', '--stdin', '--').' > '.tmp
    let sha1 = readfile(tmp)[0]
    let old_mode = matchstr(s:SystemError([dir, 'ls-files', '--stage', '.' . file])[0], '^\d\+')
    if empty(old_mode)
      let old_mode = executable(s:Tree(dir) . file) ? '100755' : '100644'
    endif
    let info = old_mode.' '.sha1.' '.commit."\t".file[1:-1]
    let [error, exec_error] = s:SystemError([dir, 'update-index', '--index-info'], info . "\n")
    if !exec_error
      setlocal nomodified
      if exists('#' . autype . 'WritePost')
        execute 'doautocmd ' . autype . 'WritePost ' . s:fnameescape(amatch)
      endif
      return ''
    else
      return 'echoerr '.string('fugitive: '.error)
    endif
  finally
    call delete(tmp)
  endtry
endfunction

function! fugitive#BufReadCmd(...) abort
  let amatch = a:0 ? a:1 : expand('<amatch>')
  try
    let [dir, rev] = s:DirRev(amatch)
    if empty(dir)
      return 'echo "Invalid Fugitive URL"'
    endif
    if rev =~# '^:\d$'
      let b:fugitive_type = 'stage'
    else
      let [b:fugitive_type, exec_error] = s:ChompError([dir, 'cat-file', '-t', rev])
      if exec_error && rev =~# '^:0'
        let sha = s:ChompDefault('', dir, 'write-tree', '--prefix=' . rev[3:-1])
        let exec_error = empty(sha)
        let b:fugitive_type = exec_error ? '' : 'tree'
      endif
      if exec_error
        let error = b:fugitive_type
        unlet b:fugitive_type
        setlocal noswapfile
        if empty(&bufhidden)
          setlocal bufhidden=delete
        endif
        if rev =~# '^:\d:'
          let &l:readonly = !filewritable(fugitive#Find('.git/index', dir))
          return 'silent doautocmd BufNewFile'
        else
          setlocal readonly nomodifiable
          return 'silent doautocmd BufNewFile|echo ' . string(error)
        endif
      elseif b:fugitive_type !~# '^\%(tag\|commit\|tree\|blob\)$'
        return "echoerr ".string("fugitive: unrecognized git type '".b:fugitive_type."'")
      endif
      if !exists('b:fugitive_display_format') && b:fugitive_type != 'blob'
        let b:fugitive_display_format = +getbufvar('#','fugitive_display_format')
      endif
    endif

    if b:fugitive_type !=# 'blob'
      setlocal nomodeline
    endif

    setlocal noreadonly modifiable
    let pos = getpos('.')
    silent keepjumps %delete_
    setlocal endofline

    try
      silent doautocmd BufReadPre
      if b:fugitive_type ==# 'tree'
        let b:fugitive_display_format = b:fugitive_display_format % 2
        if b:fugitive_display_format
          call s:ReplaceCmd([dir, 'ls-tree', exists('sha') ? sha : rev])
        else
          if !exists('sha')
            let sha = s:TreeChomp(dir, 'rev-parse', '--verify', rev, '--')
          endif
          call s:ReplaceCmd([dir, 'show', '--no-color', sha])
        endif
      elseif b:fugitive_type ==# 'tag'
        let b:fugitive_display_format = b:fugitive_display_format % 2
        if b:fugitive_display_format
          call s:ReplaceCmd([dir, 'cat-file', b:fugitive_type, rev])
        else
          call s:ReplaceCmd([dir, 'cat-file', '-p', rev])
        endif
      elseif b:fugitive_type ==# 'commit'
        let b:fugitive_display_format = b:fugitive_display_format % 2
        if b:fugitive_display_format
          call s:ReplaceCmd([dir, 'cat-file', b:fugitive_type, rev])
        else
          call s:ReplaceCmd([dir, 'show', '--no-color', '--pretty=format:tree%x20%T%nparent%x20%P%nauthor%x20%an%x20<%ae>%x20%ad%ncommitter%x20%cn%x20<%ce>%x20%cd%nencoding%x20%e%n%n%s%n%n%b', rev])
          keepjumps call search('^parent ')
          if getline('.') ==# 'parent '
            silent keepjumps delete_
          else
            silent exe (exists(':keeppatterns') ? 'keeppatterns' : '') 'keepjumps s/\m\C\%(^parent\)\@<! /\rparent /e' . (&gdefault ? '' : 'g')
          endif
          keepjumps let lnum = search('^encoding \%(<unknown>\)\=$','W',line('.')+3)
          if lnum
            silent keepjumps delete_
          end
          silent exe (exists(':keeppatterns') ? 'keeppatterns' : '') 'keepjumps 1,/^diff --git\|\%$/s/\r$//e'
          keepjumps 1
        endif
      elseif b:fugitive_type ==# 'stage'
        call s:ReplaceCmd([dir, 'ls-files', '--stage'])
      elseif b:fugitive_type ==# 'blob'
        call s:ReplaceCmd([dir, 'cat-file', b:fugitive_type, rev])
      endif
    finally
      keepjumps call setpos('.',pos)
      setlocal nomodified noswapfile
      let modifiable = rev =~# '^:.:' && b:fugitive_type !=# 'tree'
      let &l:readonly = !modifiable || !filewritable(fugitive#Find('.git/index', dir))
      if empty(&bufhidden)
        setlocal bufhidden=delete
      endif
      let &l:modifiable = modifiable
      if b:fugitive_type !=# 'blob'
        setlocal filetype=git foldmethod=syntax
        nnoremap <buffer> <silent> a :<C-U>let b:fugitive_display_format += v:count1<Bar>exe fugitive#BufReadCmd(@%)<CR>
        nnoremap <buffer> <silent> i :<C-U>let b:fugitive_display_format -= v:count1<Bar>exe fugitive#BufReadCmd(@%)<CR>
      endif
      call fugitive#MapJumps()
    endtry

    setlocal modifiable
    return 'silent doautocmd' . (v:version >= 704 ? ' <nomodeline>' : '') .
          \ ' BufReadPost' . (modifiable ? '' : '|setl nomodifiable')
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
endfunction

function! fugitive#BufWriteCmd(...) abort
  return fugitive#FileWriteCmd(a:0 ? a:1 : expand('<amatch>'), 1)
endfunction

function! fugitive#SourceCmd(...) abort
  let amatch = a:0 ? a:1 : expand('<amatch>')
  let temp = s:BlobTemp(amatch)
  if empty(temp)
    return 'noautocmd source ' . s:fnameescape(amatch)
  endif
  if !exists('g:virtual_scriptnames')
    let g:virtual_scriptnames = {}
  endif
  let g:virtual_scriptnames[temp] = amatch
  return 'source ' . s:fnameescape(temp)
endfunction

" Section: Temp files

if !exists('s:temp_files')
  let s:temp_files = {}
endif

function! s:SetupTemp(file) abort
  if has_key(s:temp_files, s:cpath(a:file))
    let dict = s:temp_files[s:cpath(a:file)]
    if has_key(dict, 'filetype') && dict.filetype !=# &l:filetype
      let &l:filetype = dict.filetype
    endif
    setlocal foldmarker=<<<<<<<,>>>>>>>
    setlocal bufhidden=delete nobuflisted
    setlocal buftype=nowrite
    if empty(mapcheck('q', 'n'))
      nnoremap <buffer> <silent> q    :<C-U>bdelete<CR>
    endif
    exe 'nnoremap <buffer> <silent>' s:nowait "gq :<C-U>bdelete<CR>"
    if getline(1) !~# '^diff '
      setlocal nomodifiable
    endif
    if len(dict.dir)
      let b:git_dir = dict.dir
      call extend(b:, {'fugitive_type': 'temp'}, 'keep')
      call FugitiveDetect(a:file)
      if &filetype ==# 'git'
        call fugitive#MapJumps()
      endif
    endif
  endif
  return ''
endfunction

augroup fugitive_temp
  autocmd!
  autocmd BufNewFile,BufReadPost * exe s:SetupTemp(expand('<amatch>:p'))
augroup END

" Section: :Git

function! s:GitExec(line1, line2, range, count, bang, mods, reg, args, dir) abort
  if empty(a:args)
    return s:StatusCommand(a:line1, a:line2, a:range, a:count, a:bang, a:mods, a:reg, '', [])
  endif
  if a:bang
    return s:OpenExec((a:count > 0 ? a:count : '') . (a:count ? 'split' : 'edit'), a:mods, a:args, a:dir)
  endif
  let git = s:UserCommandList(a:dir)
  if s:HasOpt(a:args, ['add', 'checkout', 'commit', 'stage', 'stash', 'reset'], '-p', '--patch') ||
        \ s:HasOpt(a:args, ['add', 'clean', 'stage'], '-i', '--interactive')
    let mods = substitute(s:Mods(a:mods), '\<tab\>', '-tab', 'g')
    if has('nvim')
      if &autowrite || &autowriteall | silent! wall | endif
      return mods . (a:count ? 'split' : 'edit') . ' term://' . s:fnameescape(s:shellesc(git + a:args)) . '|startinsert'
    elseif has('terminal')
      if &autowrite || &autowriteall | silent! wall | endif
      return 'exe ' . string(mods . 'terminal ' . (a:count ? '' : '++curwin ') . join(map(git + a:args, 's:fnameescape(v:val)')))
    endif
  endif
  if has('gui_running') && !has('win32')
    call add(git, '--no-pager')
  endif
  let pre = ''
  if has('nvim') && executable('env')
    let pre .= 'env GIT_TERMINAL_PROMPT=0 '
  endif
  return 'exe ' . string('!' . escape(pre . s:shellesc(git + a:args), '!#%'))
endfunction

function! s:GitCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  let dir = s:Dir()
  let [args, after] = s:SplitExpandChain(a:arg, s:Tree(dir))
  return s:GitExec(a:line1, a:line2, a:range, a:count, a:bang, a:mods, a:reg, args, dir) . after
endfunction

function! s:Command(line1, line2, range, count, bang, mods, reg, arg, args, ...) abort
  let dir = a:0 ? s:Dir(a:1) : s:Dir()
  let [args, after] = s:SplitExpandChain(a:arg, s:Tree(dir))
  return s:GitExec(a:line1, a:line2, a:range, a:count, a:bang, a:mods, a:reg, args, dir) . after
endfunction

let s:exec_paths = {}
function! s:Subcommands() abort
  if !has_key(s:exec_paths, g:fugitive_git_executable)
    let s:exec_paths[g:fugitive_git_executable] = s:sub(system(g:fugitive_git_executable.' --exec-path'),'\n$','')
  endif
  let exec_path = s:exec_paths[g:fugitive_git_executable]
  return map(split(glob(exec_path.'/git-*'),"\n"),'s:sub(v:val[strlen(exec_path)+5 : -1],"\\.exe$","")')
endfunction

let s:aliases = {}
function! s:Aliases(dir) abort
  if !has_key(s:aliases, a:dir)
    let s:aliases[a:dir] = {}
    let lines = s:NullError([a:dir, 'config', '-z', '--get-regexp', '^alias[.]'])[0]
    for line in lines
      let s:aliases[a:dir][matchstr(line, '\.\zs.\{-}\ze\n')] = matchstr(line, '\n\zs.*')
    endfor
  endif
  return s:aliases[a:dir]
endfunction

function! fugitive#CompleteGit(lead, ...) abort
  let dir = a:0 == 1 ? a:1 : a:0 == 3 ? a:3 : s:Dir()
  let pre = a:0 > 1 ? strpart(a:1, 0, a:2) : ''
  let subcmd = matchstr(pre, '\u\w*[! ] *\zs[[:alnum:]-]\+\ze ')
  if empty(subcmd)
    let results = sort(s:Subcommands() + keys(s:Aliases(dir)))
  elseif pre =~# ' -- '
    return fugitive#CompletePath(a:lead, dir)
  elseif a:lead =~# '^-'
    let results = split(s:ChompDefault('', dir, subcmd, '--git-completion-helper'), ' ')
  else
    return fugitive#CompleteObject(a:lead, dir)
  endif
  return filter(results, 'strpart(v:val, 0, strlen(a:lead)) ==# a:lead')
endfunction

function! fugitive#Complete(...) abort
  return call('fugitive#CompleteGit', a:000)
endfunction

call s:command("-bang -nargs=? -range=-1 -complete=customlist,fugitive#CompleteGit Git", "Git")
call s:command("-bang -nargs=? -range=-1 -complete=customlist,fugitive#CompleteGit G", "")

" Section: :Gcd, :Glcd

function! s:DirComplete(A, L, P) abort
  return filter(fugitive#CompletePath(a:A), 'v:val =~# "/$"')
endfunction

function! s:DirArg(path) abort
  let path = substitute(a:path, '^:/:\=\|^:(\%(top\|top,literal\|literal,top\|literal\))', '', '')
  if path =~# '^/\|^\a\+:\|^\.\.\=\%(/\|$\)'
    return path
  else
    return (empty(s:Tree()) ? s:Dir() : s:Tree()) . '/' . path
  endif
endfunction

call s:command("-bar -bang -nargs=? -complete=customlist,s:DirComplete Gcd  :exe 'cd<bang>'  s:fnameescape(s:DirArg(<q-args>))")
call s:command("-bar -bang -nargs=? -complete=customlist,s:DirComplete Glcd :exe 'lcd<bang>' s:fnameescape(s:DirArg(<q-args>))")

" Section: :Gstatus

call s:command("-bar -bang -range=-1 Gstatus", "Status")

function! s:StatusCommand(line1, line2, range, count, bang, mods, reg, arg, args, ...) abort
  let dir = a:0 ? a:1 : s:Dir()
  exe s:DirCheck(dir)
  try
    let mods = s:Mods(a:mods, &splitbelow ? 'botright' : 'topleft')
    let file = fugitive#Find(':', dir)
    let arg = ' +setl\ foldmethod=syntax\ foldlevel=1\|let\ w:fugitive_status=FugitiveGitDir() ' .
          \ s:fnameescape(file)
    for winnr in range(1, winnr('$'))
      if s:cpath(file, fnamemodify(bufname(winbufnr(winnr)), ':p'))
        exe winnr . 'wincmd w'
        let w:fugitive_status = dir
        return s:ReloadStatus()
      endif
    endfor
    if a:count ==# 0
      return mods . 'edit' . (a:bang ? '!' : '') . arg
    elseif a:bang
      return mods . 'pedit' . arg . '|wincmd P'
    else
      return mods . (a:count > 0 ? a:count : '') . 'split' . arg
    endif
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
  return ''
endfunction

function! s:StageJump(offset, section, ...) abort
  let line = search('^' . a:section, 'nw')
  if line
    exe line
    return s:NextFileHunk(a:offset ? a:offset : 1)
  endif
  return ''
endfunction

function! s:StageSeek(info, fallback) abort
  let info = a:info
  if empty(info.section)
    return a:fallback
  endif
  let line = search('^' . info.section, 'wn')
  if !line
    for section in get({'Staged': ['Unstaged', 'Untracked'], 'Unstaged': ['Untracked', 'Staged']}, info.section, [])
      let line = search('^' . section, 'wn')
      if line
        return line + (info.index > 0 ? 1 : 0)
      endif
    endfor
    return 1
  endif
  let i = 0
  while len(getline(line))
    let filename = matchstr(getline(line), '^[A-Z?] \zs.*')
    if len(filename) &&
          \ ((info.filename[-1:-1] ==# '/' && filename[0 : len(info.filename) - 1] ==# info.filename) ||
          \ (filename[-1:-1] ==# '/' && filename ==# info.filename[0 : len(filename) - 1]) ||
          \ filename ==# info.filename)
      if info.offset < 0
        return line
      else
        if getline(line+1) !~# '^@'
          exe s:StageInline('show', line)
        endif
        if getline(line+1) !~# '^@'
          return line
        endif
        let type = info.sigil ==# '-' ? '-' : '+'
        let offset = -1
        while offset < info.offset
          let line += 1
          if getline(line) =~# '^@'
            let offset = +matchstr(getline(line), type . '\zs\d\+') - 1
          elseif getline(line) =~# '^[ ' . type . ']'
            let offset += 1
          elseif getline(line) !~# '^[ @\+-]'
            return line - 1
          endif
        endwhile
        return line
      endif
    endif
    let commit = matchstr(getline(line), '^\%(\%(\x\x\x\)\@!\l\+\s\+\)\=\zs[0-9a-f]\+')
    if len(commit) && commit ==# info.commit
      return line
    endif
    if i ==# info.index
      let backup = line
    endif
    let i += getline(line) !~# '^[ @\+-]'
    let line += 1
  endwhile
  return exists('backup') ? backup : line - 1
endfunction

function! s:ReloadStatus(...) abort
  call s:ExpireStatus(-1)
  if get(b:, 'fugitive_type', '') !=# 'index'
    return ''
  endif
  let original_lnum = a:0 ? a:1 : line('.')
  let info = s:StageInfo(original_lnum)
  call fugitive#BufReadStatus()
  exe s:StageSeek(info, original_lnum)
  normal! 0
  return ''
endfunction

let s:last_time = reltime()
if !exists('s:last_times')
  let s:last_times = {}
endif

function! s:ExpireStatus(bufnr) abort
  if a:bufnr == -2
    let s:last_time = reltime()
    return ''
  endif
  let dir = s:Dir(a:bufnr)
  if len(dir)
    let s:last_times[s:cpath(dir)] = reltime()
  endif
  return ''
endfunction

function! FugitiveReloadCheck() abort
  let t = b:fugitive_reltime
  return [t, reltimestr(reltime(s:last_time, t)),
        \ reltimestr(reltime(get(s:last_times, s:cpath(s:Dir()), t), t))]
endfunction

function! s:ReloadWinStatus(...) abort
  if get(b:, 'fugitive_type', '') !=# 'index' || &modified
    return
  endif
  if !exists('b:fugitive_reltime')
    exe s:ReloadStatus()
    return
  endif
  let t = b:fugitive_reltime
  if reltimestr(reltime(s:last_time, t)) =~# '-\|\d\{10\}\.' ||
        \ reltimestr(reltime(get(s:last_times, s:cpath(s:Dir()), t), t)) =~# '-\|\d\{10\}\.'
    exe s:ReloadStatus()
  endif
endfunction

function! s:ReloadTabStatus(...) abort
  let mytab = tabpagenr()
  let tab = a:0 ? a:1 : mytab
  for winnr in range(1, tabpagewinnr(tab, '$'))
    if getbufvar(tabpagebuflist(tab)[winnr-1], 'fugitive_type') ==# 'index'
      execute 'tabnext '.tab
      if winnr != winnr()
        execute winnr.'wincmd w'
        let restorewinnr = 1
      endif
      try
        call s:ReloadWinStatus()
      finally
        if exists('restorewinnr')
          unlet restorewinnr
          wincmd p
        endif
        execute 'tabnext '.mytab
      endtry
    endif
  endfor
  unlet! t:fugitive_reload_status
endfunction

function! fugitive#ReloadStatus(...) abort
  call s:ExpireStatus(a:0 ? a:1 : -2)
  if a:0 > 1 ? a:2 : s:CanAutoReloadStatus()
    let t = reltime()
    let t:fugitive_reload_status = t
    for tabnr in exists('*settabvar') ? range(1, tabpagenr('$')) : []
      call settabvar(tabnr, 'fugitive_reload_status', t)
    endfor
    call s:ReloadTabStatus()
  else
    call s:ReloadWinStatus()
  endif
endfunction

function! s:CanAutoReloadStatus() abort
  return get(g:, 'fugitive_autoreload_status', !has('win32'))
endfunction

augroup fugitive_status
  autocmd!
  autocmd BufWritePost         * call fugitive#ReloadStatus(-1, 0)
  autocmd ShellCmdPost         * call fugitive#ReloadStatus()
  autocmd BufDelete     term://* call fugitive#ReloadStatus()
  if !has('win32')
    autocmd FocusGained        * call fugitive#ReloadStatus(-2, 0)
  endif
  autocmd BufEnter index,index.lock
        \ call s:ReloadWinStatus()
  autocmd TabEnter *
        \ if exists('t:fugitive_reload_status') |
        \    call s:ReloadTabStatus() |
        \ endif
augroup END

function! s:StageInfo(...) abort
  let lnum = a:0 ? a:1 : line('.')
  let sigil = matchstr(getline(lnum), '^[ @\+-]')
  let offset = -1
  if len(sigil)
    let type = sigil ==# '-' ? '-' : '+'
    while lnum > 0 && getline(lnum) !~# '^@'
      if getline(lnum) =~# '^[ '.type.']'
        let offset += 1
      endif
      let lnum -= 1
    endwhile
    let offset += matchstr(getline(lnum), type.'\zs\d\+')
    while getline(lnum) =~# '^[ @\+-]'
      let lnum -= 1
    endwhile
  endif
  let slnum = lnum + 1
  let section = ''
  let index = 0
  while len(getline(slnum - 1)) && empty(section)
    let slnum -= 1
    let section = matchstr(getline(slnum), '^\u\l\+\ze.* (\d\+)$')
    if empty(section) && getline(slnum) !~# '^[ @\+-]'
      let index += 1
    endif
  endwhile
  let text = matchstr(getline(lnum), '^[A-Z?] \zs.*')
  return {'section': section,
        \ 'heading': getline(slnum),
        \ 'sigil': sigil,
        \ 'offset': offset,
        \ 'filename': text,
        \ 'relative': reverse(split(text, ' -> ')),
        \ 'paths': map(reverse(split(text, ' -> ')), 's:Tree() . "/" . v:val'),
        \ 'commit': matchstr(getline(lnum), '^\%(\%(\x\x\x\)\@!\l\+\s\+\)\=\zs[0-9a-f]\{4,\}\ze '),
        \ 'status': matchstr(getline(lnum), '^[A-Z?]\ze \|^\%(\x\x\x\)\@!\l\+\ze [0-9a-f]'),
        \ 'index': index}
endfunction

function! s:Selection(arg1, ...) abort
  if a:arg1 ==# 'n'
    let arg1 = line('.')
    let arg2 = -v:count
  elseif a:arg1 ==# 'v'
    let arg1 = line("'<")
    let arg2 = line("'>")
  else
    let arg1 = a:arg1
    let arg2 = a:0 ? a:1 : 0
  endif
  let first = arg1
  if arg2 < 0
    let last = first - arg2 + 1
  elseif arg2 > 0
    let last = arg2
  else
    let last = first
  endif
  while getline(first) =~# '^$\|^[A-Z][a-z]'
    let first += 1
  endwhile
  if first > last || &filetype !=# 'fugitive'
    return []
  endif
  let flnum = first
  while getline(flnum) =~# '^[ @\+-]'
    let flnum -= 1
  endwhile
  let slnum = flnum + 1
  let section = ''
  let index = 0
  while len(getline(slnum - 1)) && empty(section)
    let slnum -= 1
    let heading = matchstr(getline(slnum), '^\u\l\+.* (\d\+)$')
    if empty(heading) && getline(slnum) !~# '^[ @\+-]'
      let index += 1
    endif
  endwhile
  let results = []
  let template = {
        \ 'heading': heading,
        \ 'section': matchstr(heading, '^\u\l\+\ze.* (\d\+)$'),
        \ 'filename': '',
        \ 'relative': [],
        \ 'paths': [],
        \ 'commit': '',
        \ 'status': '',
        \ 'patch': 0,
        \ 'index': index}
  let line = getline(flnum)
  let lnum = first - (arg1 == flnum ? 0 : 1)
  let root = s:Tree() . '/'
  while lnum <= last
    if line =~# '^\u\l\+\ze.* (\d\+)$'
      let template.heading = getline(lnum)
      let template.section = matchstr(template.heading, '^\u\l\+\ze.* (\d\+)$')
      let template.index = 0
    elseif line =~# '^[ @\+-]'
      let template.index -= 1
      if !results[-1].patch
        let results[-1].patch = lnum
      endif
      let results[-1].lnum = lnum
    elseif line =~# '^[A-Z?] '
      let filename = matchstr(line, '^[A-Z?] \zs.*')
      call add(results, extend(deepcopy(template), {
            \ 'lnum': lnum,
            \ 'filename': filename,
            \ 'relative': reverse(split(filename, ' -> ')),
            \ 'paths': map(reverse(split(filename, ' -> ')), 'root . v:val'),
            \ 'status': matchstr(line, '^[A-Z?]'),
            \ }))
    elseif line =~# '^\x\x\x\+ '
      call add(results, extend({
            \ 'lnum': lnum,
            \ 'commit': matchstr(line, '^\x\x\x\+'),
            \ }, template, 'keep'))
    elseif line =~# '^\l\+ \x\x\x\+ '
      call add(results, extend({
            \ 'lnum': lnum,
            \ 'commit': matchstr(line, '^\l\+ \zs\x\x\x\+'),
            \ 'status': matchstr(line, '^\l\+'),
            \ }, template, 'keep'))
    endif
    let lnum += 1
    let template.index += 1
    let line = getline(lnum)
  endwhile
  if len(results) && results[0].patch && arg2 == 0
    while getline(results[0].patch) =~# '^[ \+-]'
      let results[0].patch -= 1
    endwhile
    while getline(results[0].lnum + 1) =~# '^[ \+-]'
      let results[0].lnum += 1
    endwhile
  endif
  return results
endfunction

function! s:StageArgs(visual) abort
  let commits = []
  let paths = []
  for record in s:Selection(a:visual ? 'v' : 'n')
    if len(record.commit)
      call add(commits, record.commit)
    endif
    call extend(paths, record.paths)
  endfor
  if s:cpath(s:Tree(), getcwd())
    call map(paths, 'fugitive#Path(v:val, "./")')
  endif
  return join(map(commits + paths, 's:fnameescape(v:val)'), ' ')
endfunction

function! s:Do(action, visual) abort
  let line = getline('.')
  let reload = 0
  if !a:0 && !v:count && line =~# '^[A-Z][a-z]'
    let header = matchstr(line, '^\S\+\ze:')
    if len(header) && exists('*s:Do' . a:action . header . 'Header')
      let reload = s:Do{a:action}{header}Header(matchstr(line, ': \zs.*')) > 0
    else
      let section = matchstr(line, '^\S\+')
      if exists('*s:Do' . a:action . section . 'Heading')
        let reload = s:Do{a:action}{section}Heading(line) > 0
      endif
    endif
    return reload ? s:ReloadStatus() : ''
  endif
  let selection = s:Selection(a:visual ? 'v' : 'n')
  if empty(selection)
    return ''
  endif
  call filter(selection, 'v:val.section ==# selection[0].section')
  let status = 0
  let err = ''
  try
    for record in selection
      if exists('*s:Do' . a:action . record.section)
        let status = s:Do{a:action}{record.section}(record)
      else
        continue
      endif
      if !status
        return ''
      endif
      let reload = reload || (status > 0)
    endfor
    if status < 0
      execute record.lnum + 1
    endif
    let success = 1
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  finally
    if reload
      execute s:ReloadStatus()
    endif
    if exists('success')
      call s:StageReveal()
    endif
  endtry
  return ''
endfunction

function! s:StageReveal(...) abort
  let begin = a:0 ? a:1 : line('.')
  if getline(begin) =~# '^@'
    let end = begin + 1
    while getline(end) =~# '^[ \+-]'
      let end += 1
    endwhile
    while line('w$') < line('$') && end > line('w$') && line('.') > line('w0') + &scrolloff
      execute "normal! \<C-E>"
    endwhile
  endif
endfunction

function! s:NextFileHunk(count) abort
  for i in range(a:count)
    call search('^[A-Z?] .\|^diff --\|^[0-9a-f]\{4,\} \|^@','W')
  endfor
  call s:StageReveal()
  return '.'
endfunction

function! s:PreviousFileHunk(count) abort
  for i in range(a:count)
    call search('^[A-Z?] .\|^diff --\|^[0-9a-f]\{4,\} \|^@','Wbe')
  endfor
  call s:StageReveal()
  return '.'
endfunction

function! s:NextSection(count) abort
  for i in range(a:count)
    if !search('^[A-Z][a-z][^:]*$','W')
      return '.'
    endif
    +
  endfor
  call s:StageReveal()
  return '.'
endfunction

function! s:PreviousSection(count) abort
  -
  for i in range(a:count)
    if !search('^[A-Z][a-z][^:]*$\|\%^','bW') || line('.') == 1
      return '.'
    endif
    +
  endfor
  call s:StageReveal()
  return '.'
endfunction

function! s:StageInline(mode, ...) abort
  let lnum1 = a:0 ? a:1 : line('.')
  let lnum = lnum1 + 1
  if a:0 > 1 && a:2 == 0
    let info = s:StageInfo(lnum - 1)
    if empty(info.paths) && len(info.section)
      while len(getline(lnum))
        let lnum += 1
      endwhile
    endif
  elseif a:0 > 1
    let lnum += a:2 - 1
  endif
  while lnum > lnum1
    let lnum -= 1
    while lnum > 0 && getline(lnum) =~# '^[ @\+-]'
      let lnum -= 1
    endwhile
    let info = s:StageInfo(lnum)
    if !has_key(b:fugitive_diff, info.section)
      continue
    endif
    if getline(lnum + 1) =~# '^[ @\+-]'
      let lnum2 = lnum + 1
      while getline(lnum2 + 1) =~# '^[ @\+-]'
        let lnum2 += 1
      endwhile
      if a:mode !=# 'show'
        setlocal modifiable noreadonly
        exe 'silent keepjumps ' . (lnum + 1) . ',' . lnum2 . 'delete _'
        call remove(b:fugitive_expanded[info.section], info.filename)
        setlocal nomodifiable readonly nomodified
      endif
      continue
    endif
    if !has_key(b:fugitive_diff, info.section) || info.status !~# '^[ADMR]$' || a:mode ==# 'hide'
      continue
    endif
    let mode = ''
    let diff = []
    let index = 0
    let start = -1
    for line in b:fugitive_diff[info.section]
      if mode ==# 'await' && line[0] ==# '@'
        let mode = 'capture'
      endif
      if mode !=# 'head' && line !~# '^[ @\+-]'
        if len(diff)
          break
        endif
        let start = index
        let mode = 'head'
      elseif mode ==# 'head' && substitute(line, "\t$", '', '') ==# '--- ' . info.relative[-1]
        let mode = 'await'
      elseif mode ==# 'head' && substitute(line, "\t$", '', '') ==# '+++ ' . info.relative[0]
        let mode = 'await'
      elseif mode ==# 'capture'
        call add(diff, line)
      elseif line[0] ==# '@'
        let mode = ''
      endif
      let index += 1
    endfor
    if len(diff)
      setlocal modifiable noreadonly
      silent call append(lnum, diff)
      let b:fugitive_expanded[info.section][info.filename] = [start, len(diff)]
      setlocal nomodifiable readonly nomodified
    endif
  endwhile
  return lnum
endfunction

function! s:StageIntend(count) abort
  for i in range(a:count)
    if getline('.')[0:1] ==# '? '
      call s:TreeChomp('add', '--intent-to-add', '--', s:Tree() . '/' . getline('.')[2:-1])
      -
      exe s:ReloadStatus()
    elseif getline('.') =~# '^Unstaged\|^Untracked'
      call s:TreeChomp('add', '--intent-to-add', '--', s:Tree())
      exe s:ReloadStatus()
    else
      call s:StageInline('show', line('.'), 1)
    endif
    call s:NextFileHunk(1)
  endfor
  return '.'
endfunction

function! s:StageDiff(diff) abort
  let lnum = line('.')
  let info = s:StageInfo(lnum)
  let prefix = info.offset > 0 ? '+' . info.offset : ''
  if empty(info.paths) && info.section ==# 'Staged'
    return 'Git! diff --no-ext-diff --cached'
  elseif empty(info.paths)
    return 'Git! diff --no-ext-diff'
  elseif len(info.paths) > 1
    execute 'Gedit' . prefix s:fnameescape(':0:' . info.paths[0])
    return a:diff.' HEAD:'.s:fnameescape(info.paths[1])
  elseif info.section ==# 'Staged' && info.sigil ==# '-'
    execute 'Gedit' prefix s:fnameescape('@:'.info.paths[0])
    return a:diff.'! :0:%'
  elseif info.section ==# 'Staged'
    execute 'Gedit' prefix s:fnameescape(':0:'.info.paths[0])
    return a:diff . (info.sigil ==# '+' ? '!' : '') . ' @:%'
  elseif info.sigil ==# '-'
    execute 'Gedit' prefix s:fnameescape(':0:'.info.paths[0])
    return a:diff . '!'
  else
    execute 'Gedit' prefix s:fnameescape(':(top)'.info.paths[0])
    return a:diff . (info.sigil ==# '+' ? '!' : '')
  endif
endfunction

function! s:StageDiffEdit() abort
  let info = s:StageInfo(line('.'))
  let arg = (empty(info.paths) ? s:Tree() : info.paths[0])
  if info.section ==# 'Staged'
    return 'Git! diff --no-ext-diff --cached '.s:fnameescape(arg)
  elseif info.status ==# '?'
    call s:TreeChomp('add', '--intent-to-add', '--', arg)
    return s:ReloadStatus()
  else
    return 'Git! diff --no-ext-diff '.s:fnameescape(arg)
  endif
endfunction

function! s:StageApply(info, reverse, extra) abort
  if a:info.status ==# 'R'
    call s:throw('fugitive: patching renamed file not yet supported')
  endif
  let cmd = ['apply', '-p0', '--recount'] + a:extra
  let info = a:info
  let start = info.patch
  let end = info.lnum
  let lines = getline(start, end)
  if empty(filter(copy(lines), 'v:val =~# "^[+-]"'))
    return -1
  endif
  while getline(end) =~# '^[-+ ]'
    let end += 1
    if getline(end) =~# '^[' . (a:reverse ? '+' : '-') . ' ]'
      call add(lines, ' ' . getline(end)[1:-1])
    endif
  endwhile
  while start > 0 && getline(start) !~# '^@'
    let start -= 1
    if getline(start) =~# '^[' . (a:reverse ? '+' : '-') . ' ]'
      call insert(lines, ' ' . getline(start)[1:-1])
    elseif getline(start) =~# '^@'
      call insert(lines, getline(start))
    endif
  endwhile
  if start == 0 || getline(start) !~# '^@@ '
    call s:throw("could not find hunk")
  endif
  let i = b:fugitive_expanded[info.section][info.filename][0]
  let head = []
  while get(b:fugitive_diff[info.section], i, '@') !~# '^@'
    call add(head, b:fugitive_diff[info.section][i])
    let i += 1
  endwhile
  call extend(lines, head, 'keep')
  let temp = tempname()
  call writefile(lines, temp)
  if a:reverse
    call add(cmd, '--reverse')
  endif
  call extend(cmd, ['--', temp])
  let [output, exec_error] = s:ChompError(cmd)
  if !exec_error
    return 1
  endif
  call s:throw(output)
endfunction

function! s:StageDelete(lnum, count) abort
  let info = get(s:Selection(a:lnum, -a:count), 0, {'filename': ''})
  if empty(info.filename)
    return ''
  endif
  let hash = s:TreeChomp('hash-object', '-w', '--', info.paths[0])
  if empty(hash)
    return ''
  elseif info.patch
    try
      call s:StageApply(info, 1, info.section ==# 'Staged' ? ['--index'] : [])
    catch /^fugitive:/
      return 'echoerr ' . string(v:exception)
    endtry
  elseif a:count == 2
    call s:TreeChomp('checkout', '--ours', '--', info.paths[0])
  elseif a:count == 3
    call s:TreeChomp('checkout', '--theirs', '--', info.paths[0])
  elseif info.status =~# '[ADU]' &&
        \ get(b:fugitive_status[info.section ==# 'Staged' ? 'Unstaged' : 'Staged'], info.filename, '') =~# '[AU]'
    call s:TreeChomp('checkout', info.section ==# 'Staged' ? '--ours' : '--theirs', '--', info.paths[0])
  elseif info.status ==# 'U'
    call s:TreeChomp('rm', '--', info.paths[0])
  elseif info.status ==# 'A'
    call s:TreeChomp('rm', '-f', '--', info.paths[0])
  elseif info.status ==# '?'
    call s:TreeChomp('clean', '-f', '--', info.paths[0])
  elseif info.section ==# 'Unstaged'
    call s:TreeChomp('checkout', '--', info.paths[0])
  else
    call s:TreeChomp('checkout', 'HEAD^{}', '--', info.paths[0])
  endif
  exe s:ReloadStatus()
  call s:StageReveal()
  let @@ = hash
  return 'checktime|redraw|echomsg ' .
        \ string('To restore, :Gedit ' . info.relative[0] . '|Gread ' . hash[0:6])
endfunction

function! s:DoToggleHeadHeader(value) abort
  exe 'edit' s:fnameescape(s:Dir())
  call search('\C^index$', 'wc')
endfunction

function! s:DoToggleUnpushedHeading(heading) abort
  let remote = matchstr(a:heading, 'to \zs[^/]\+\ze/')
  if empty(remote)
    let remote = '.'
  endif
  let branch = matchstr(a:heading, 'to \%([^/]\+/\)\=\zs\S\+')
  call feedkeys(':Gpush ' . remote . ' ' . 'HEAD:' . branch)
endfunction

function! s:DoToggleUnpushed(record) abort
  let remote = matchstr(a:record.heading, 'to \zs[^/]\+\ze/')
  if empty(remote)
    let remote = '.'
  endif
  let branch = matchstr(a:record.heading, 'to \%([^/]\+/\)\=\zs\S\+')
  call feedkeys(':Gpush ' . remote . ' ' . a:record.commit . ':' . branch)
endfunction

function! s:DoToggleUnpulledHeading(heading) abort
  call feedkeys(':Grebase')
endfunction

function! s:DoToggleUnpulled(record) abort
  call feedkeys(':Grebase ' . a:record.commit)
endfunction

function! s:DoToggleStagedHeading(...) abort
  call s:TreeChomp('reset', '-q')
  return 1
endfunction

function! s:DoUnstageStagedHeading(heading) abort
  return s:DoToggleStagedHeading(a:heading)
endfunction

function! s:DoToggleUnstagedHeading(...) abort
  call s:TreeChomp('add', '-u')
  return 1
endfunction

function! s:DoStageUnstagedHeading(heading) abort
  return s:DoToggleUnstagedHeading(a:heading)
endfunction

function! s:DoToggleUntrackedHeading(...) abort
  call s:TreeChomp('add', '.')
  return 1
endfunction

function! s:DoStageUntrackedHeading(heading) abort
  return s:DoToggleUntrackedHeading(a:heading)
endfunction

function! s:DoToggleStaged(record) abort
  if a:record.patch
    return s:StageApply(a:record, 1, ['--cached'])
  else
    call s:TreeChomp(['reset', '-q', '--'] + a:record.paths)
    return 1
  endif
endfunction

function! s:DoUnstageStaged(record) abort
  return s:DoToggleStaged(a:record)
endfunction

function! s:DoToggleUnstaged(record) abort
  if a:record.patch
    return s:StageApply(a:record, 0, ['--cached'])
  else
    call s:TreeChomp(['add', '-A', '--'] + a:record.paths)
    return 1
  endif
endfunction

function! s:DoStageUnstaged(record) abort
  return s:DoToggleUnstaged(a:record)
endfunction

function! s:DoUnstageUnstaged(record) abort
  if a:record.status ==# 'A'
    call s:TreeChomp(['reset', '-q', '--'] + a:record.paths)
    return 1
  else
    return -1
  endif
endfunction

function! s:DoToggleUntracked(record) abort
  call s:TreeChomp(['add', '--'] + a:record.paths)
  return 1
endfunction

function! s:DoStageUntracked(record) abort
  return s:DoToggleUntracked(a:record)
endfunction

function! s:StagePatch(lnum1,lnum2) abort
  let add = []
  let reset = []

  for lnum in range(a:lnum1,a:lnum2)
    let info = s:StageInfo(lnum)
    if empty(info.paths) && info.section ==# 'Staged'
      return 'Git reset --patch'
    elseif empty(info.paths) && info.section ==# 'Unstaged'
      return 'Git add --patch'
    elseif empty(info.paths) && info.section ==# 'Untracked'
      return 'Git add --interactive'
    elseif empty(info.paths)
      continue
    endif
    execute lnum
    if info.section ==# 'Staged'
      let reset += info.relative
    elseif info.status !~# '^D'
      let add += info.relative
    endif
  endfor
  try
    if !empty(add)
      execute "Git add --patch -- ".join(map(add,'s:fnameescape(v:val)'))
    endif
    if !empty(reset)
      execute "Git reset --patch -- ".join(map(reset,'s:fnameescape(v:val)'))
    endif
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
  return s:ReloadStatus()
endfunction

" Section: :Gcommit

function! s:CommitCommand(line1, line2, range, count, bang, mods, reg, arg, args, ...) abort
  let mods = substitute(s:Mods(a:mods), '\C\<tab\>', '-tab', 'g')
  let dir = a:0 ? a:1 : s:Dir()
  let tree = s:Tree(dir)
  let msgfile = fugitive#Find('.git/COMMIT_EDITMSG', dir)
  let outfile = tempname()
  try
    let guioptions = &guioptions
    try
      if &guioptions =~# '!'
        setglobal guioptions-=!
      endif
      if s:winshell()
        let command = 'set GIT_EDITOR=false& '
      else
        let command = 'env GIT_EDITOR=false '
      endif
      if type(a:arg) == type([])
        let [argv, after] = [a:arg, '']
      else
        let [argv, after] = s:SplitExpandChain(a:arg, tree)
      endif
      let i = 0
      while get(argv, i, '--') !=# '--'
        if argv[i] =~# '^-[apzsneiovq].'
          call insert(argv, argv[i][0:1])
          let argv[i+1] = '-' . argv[i+1][2:-1]
        else
          let i += 1
        endif
      endwhile
      let command .= s:UserCommand(dir) . ' commit ' . s:shellesc(argv)
      if s:HasOpt(argv, '-i', '--interactive', '-p', '--patch') && &shell !~# 'csh'
        let errorfile = tempname()
        noautocmd execute '!'.command.' 2> '.errorfile
        let errors = readfile(errorfile)
        let exec_error = v:shell_error
        call delete(errorfile)
      else
        if (&autowrite || &autowriteall) && !a:0
          silent! wall
        endif
        let [error_string, exec_error] = s:TempCmd(outfile, command)
        let errors = split(error_string, "\n")
      endif
    finally
      let &guioptions = guioptions
    endtry
    if !has('gui_running')
      redraw!
    endif
    if !exec_error
      echo join(errors, "\n")
      if filereadable(outfile)
        echo join(readfile(outfile), "\n")
      endif
      call fugitive#ReloadStatus(dir, 1)
      return after[1:-1]
    else
      let error = get(errors,-2,get(errors,-1,'!'))
      if error =~# 'false''\=\.$'
        let i = 0
        while get(argv, i, '--') !=# '--'
          if argv[i] =~# '^\%(-[eips]\|-[CcFm].\+\|--edit\|--interactive\|--patch\|--signoff\|--reedit-message=.*\|--reuse-message=.*\|--file=.*\|--message=.*\)$'
            call remove(argv, i)
          elseif argv[i] =~# '^\%(-[CcFm]\|--reedit-message\|--reuse-message\|--file\|--message\)$'
            call remove(argv, i, i + 1)
          else
            if argv[i] =~# '^--cleanup\>'
              let cleanup = 1
            endif
            let i += 1
          endif
        endwhile
        call insert(argv, '--no-signoff', i)
        call insert(argv, '--no-interactive', i)
        call insert(argv, '--no-edit', i)
        if !exists('cleanup')
          call insert(argv, '--cleanup=strip')
        endif
        call extend(argv, ['-F', msgfile], 'keep')
        if bufname('%') == '' && line('$') == 1 && getline(1) == '' && !&modified
          execute mods . 'keepalt edit' s:fnameescape(msgfile)
        elseif s:HasOpt(argv, '-v') || mods =~# '\<tab\>'
          execute mods . 'keepalt -tabedit' s:fnameescape(msgfile)
        else
          execute mods . 'keepalt split' s:fnameescape(msgfile)
        endif
        let b:fugitive_commit_arguments = argv
        setlocal bufhidden=wipe filetype=gitcommit
        return '1' . after
      elseif empty(errors)
        let out = readfile(outfile)
        echo get(out, -1, '') =~# 'stash\|\d' ? get(out, -2, '') : out[-1]
        return after[1:-1]
      else
        echo join(errors, "\n")
        return after[1:-1]
      endif
    endif
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  finally
    call delete(outfile)
  endtry
endfunction

function! s:CommitComplete(A, L, P) abort
  if a:A =~# '^--fixup=\|^--squash='
    let commits = s:LinesError(['log', '--pretty=format:%s', '@{upstream}..'])[0]
    let pre = matchstr(a:A, '^--\w*=''\=') . ':/^'
    if pre =~# "'"
      call map(commits, 'pre . string(tr(v:val, "|\"^$*[]", "......."))[1:-1]')
      call filter(commits, 'strpart(v:val, 0, strlen(a:A)) ==# a:A')
      return commits
    else
      return s:FilterEscape(map(commits, 'pre . tr(v:val, "\\ !^$*?[]()''\"`&;<>|#", "....................")'), a:A)
    endif
  else
    return s:CompleteSubcommand('commit', a:A, a:L, a:P, function('fugitive#CompletePath'))
  endif
  return []
endfunction

function! s:FinishCommit() abort
  let buf = +expand('<abuf>')
  let args = getbufvar(buf, 'fugitive_commit_arguments')
  if !empty(args)
    call setbufvar(buf, 'fugitive_commit_arguments', [])
    if getbufvar(buf, 'fugitive_commit_rebase')
      call setbufvar(buf, 'fugitive_commit_rebase', 0)
      let s:rebase_continue = s:Dir(buf)
    endif
    return s:CommitCommand(-1, -1, 0, -1, 0, '', '', args, [], s:Dir(buf))
  endif
  return ''
endfunction

call s:command("-nargs=? -complete=customlist,s:CommitComplete Gcommit", "Commit")

" Section: :Gmerge, :Grebase, :Gpull

function! s:MergeComplete(A, L, P) abort
  return s:CompleteSubcommand('merge', a:A, a:L, a:P, function('s:CompleteRevision'))
endfunction

function! s:RebaseComplete(A, L, P) abort
  return s:CompleteSubcommand('rebase', a:A, a:L, a:P, function('s:CompleteRevision'))
endfunction

function! s:PullComplete(A, L, P) abort
  return s:CompleteSubcommand('pull', a:A, a:L, a:P, function('s:CompleteRemote'))
endfunction

function! s:RebaseSequenceAborter() abort
  if !exists('s:rebase_sequence_aborter')
    let temp = tempname() . '.sh'
    call writefile(
          \ ['#!/bin/sh',
          \ 'echo exec false | cat - "$1" > "$1.fugitive"',
          \ 'mv "$1.fugitive" "$1"'],
          \ temp)
    let s:rebase_sequence_aborter = temp
  endif
  return s:rebase_sequence_aborter
endfunction

function! fugitive#Cwindow() abort
  if &buftype == 'quickfix'
    cwindow
  else
    botright cwindow
    if &buftype == 'quickfix'
      wincmd p
    endif
  endif
endfunction

let s:common_efm = ''
      \ . '%+Egit:%.%#,'
      \ . '%+Eusage:%.%#,'
      \ . '%+Eerror:%.%#,'
      \ . '%+Efatal:%.%#,'
      \ . '%-G%.%#%\e[K%.%#,'
      \ . '%-G%.%#%\r%.%\+'

let s:rebase_abbrevs = {
      \ 'p': 'pick',
      \ 'r': 'reword',
      \ 'e': 'edit',
      \ 's': 'squash',
      \ 'f': 'fixup',
      \ 'x': 'exec',
      \ 'd': 'drop',
      \ 'l': 'label',
      \ 't': 'reset',
      \ 'm': 'merge',
      \ 'b': 'break',
      \ }

function! s:RebaseEdit(cmd, dir) abort
  let rebase_todo = s:fnameescape(fugitive#Find('.git/rebase-merge/git-rebase-todo', a:dir))

  if filereadable(rebase_todo)
    let new = readfile(rebase_todo)
    let sha_length = 0
    let shas = {}

    for i in range(len(new))
      if new[i] =~# '^\l\+\s\+[0-9a-f]\{5,\}\>'
        let sha = matchstr(new[i], '\C\<[a-f0-9]\{5,\}\>')
        if !sha_length
          let sha_length = len(s:TreeChomp(a:dir, 'rev-parse', '--short', sha))
        endif
        let shortened_sha = strpart(sha, 0, sha_length)
        let shas[shortened_sha] = sha
        let new[i] = substitute(new[i], sha, shortened_sha, '')
      endif
    endfor
    call writefile(new, rebase_todo)
  endif
  return a:cmd . ' +setlocal\ bufhidden=wipe\|' . escape('let b:fugitive_rebase_shas = ' . string(shas), ' ') . ' ' . rebase_todo
endfunction

function! s:MergeRebase(cmd, bang, mods, args, ...) abort
  let dir = a:0 ? a:1 : s:Dir()
  let args = a:args
  let mods = s:Mods(a:mods)
  if a:cmd =~# '^rebase' && s:HasOpt(args, '-i', '--interactive')
    let cmd = fugitive#Prepare(dir, '-c', 'sequence.editor=sh ' . s:RebaseSequenceAborter(), 'rebase') . ' ' . s:shellesc(args)
    let out = system(cmd)[0:-2]
    for file in ['end', 'msgnum']
      let file = fugitive#Find('.git/rebase-merge/' . file, dir)
      if !filereadable(file)
        return 'echoerr ' . string("fugitive: " . out)
      endif
      call writefile([readfile(file)[0] - 1], file)
    endfor
    call writefile([], fugitive#Find('.git/rebase-merge/done', dir))
    if a:bang
      return 'exe'
    endif
    return s:RebaseEdit(mods . 'split', dir)
  elseif a:cmd =~# '^rebase' && s:HasOpt(args, '--edit-todo') && filereadable(fugitive#Find('.git/rebase-merge/git-rebase-todo', dir))
    return s:RebaseEdit(mods . 'split', dir)
  elseif a:cmd =~# '^rebase' && s:HasOpt(args, '--continue') && !a:0
    let rdir = fugitive#Find('.git/rebase-merge', dir)
    let exec_error = s:ChompError([dir, 'diff-index', '--cached', '--quiet', 'HEAD', '--'])[1]
    if exec_error && isdirectory(rdir)
      if getfsize(rdir . '/amend') <= 0
        return 'exe ' . string(mods . 'Gcommit -n -F ' . s:fnameescape(rdir .'/message') . ' -e') . '|let b:fugitive_commit_rebase = 1'
      elseif readfile(rdir . '/amend')[0] ==# fugitive#Head(-1, dir)
        return 'exe ' . string(mods . 'Gcommit --amend -n -F ' . s:fnameescape(rdir . '/message') . ' -e') . '|let b:fugitive_commit_rebase = 1'
      endif
    endif
  endif
  let [mp, efm] = [&l:mp, &l:efm]
  let had_merge_msg = filereadable(fugitive#Find('.git/MERGE_MSG', dir))
  try
    let cdback = s:Cd(s:Tree(dir))
    let &l:errorformat = ''
          \ . '%-Gerror:%.%#false''.,'
          \ . '%-G%.%# ''git commit'' %.%#,'
          \ . '%+Emerge:%.%#,'
          \ . s:common_efm . ','
          \ . '%+ECannot %.%#: You have unstaged changes.,'
          \ . '%+ECannot %.%#: Your index contains uncommitted changes.,'
          \ . '%+EThere is no tracking information for the current branch.,'
          \ . '%+EYou are not currently on a branch. Please specify which,'
          \ . '%+I %#git rebase --continue,'
          \ . 'CONFLICT (%m): %f deleted in %.%#,'
          \ . 'CONFLICT (%m): Merge conflict in %f,'
          \ . 'CONFLICT (%m): Rename \"%f\"->%.%#,'
          \ . 'CONFLICT (%m): Rename %.%#->%f %.%#,'
          \ . 'CONFLICT (%m): There is a directory with name %f in %.%#,'
          \ . '%+ECONFLICT %.%#,'
          \ . '%+EKONFLIKT %.%#,'
          \ . '%+ECONFLIT %.%#,'
          \ . "%+EXUNG \u0110\u1ed8T %.%#,"
          \ . "%+E\u51b2\u7a81 %.%#,"
          \ . 'U%\t%f'
    if a:cmd =~# '^merge' && empty(args) &&
          \ (had_merge_msg || isdirectory(fugitive#Find('.git/rebase-apply', dir)) ||
          \  !empty(s:TreeChomp(dir, 'diff-files', '--diff-filter=U')))
      let &l:makeprg = g:fugitive_git_executable.' diff-files --name-status --diff-filter=U'
    else
      let &l:makeprg = s:sub(s:UserCommand() . ' ' . a:cmd .
            \ (s:HasOpt(args, '--no-edit', '--abort', '-m') || a:cmd =~# '^rebase' ? '' : ' --edit') .
            \ (s:HasOpt(args, '--autosquash') && a:cmd =~# '^rebase' ? ' --interactive' : '') .
            \ ' ' . s:shellesc(args), ' *$', '')
    endif
    if !empty($GIT_SEQUENCE_EDITOR) || has('win32')
      let old_sequence_editor = $GIT_SEQUENCE_EDITOR
      let $GIT_SEQUENCE_EDITOR = 'true'
    else
      let &l:makeprg = 'env GIT_SEQUENCE_EDITOR=true ' . &l:makeprg
    endif
    if !empty($GIT_EDITOR) || has('win32')
      let old_editor = $GIT_EDITOR
      let $GIT_EDITOR = 'false'
    else
      let &l:makeprg = 'env GIT_EDITOR=false ' . substitute(&l:makeprg, '^env ', '', '')
    endif
    if !has('patch-8.1.0334') && has('terminal') && &autowrite
      let autowrite_was_set = 1
      set noautowrite
      silent! wall
    endif
    silent noautocmd make!
  catch /^Vim\%((\a\+)\)\=:E211/
    let err = v:exception
  finally
    if exists('autowrite_was_set')
      set autowrite
    endif
    redraw!
    let [&l:mp, &l:efm] = [mp, efm]
    if exists('old_editor')
      let $GIT_EDITOR = old_editor
    endif
    if exists('old_sequence_editor')
      let $GIT_SEQUENCE_EDITOR = old_sequence_editor
    endif
    execute cdback
  endtry
  call fugitive#ReloadStatus(dir, 1)
  if empty(filter(getqflist(),'v:val.valid && v:val.type !=# "I"'))
    if a:cmd =~# '^rebase' &&
          \ filereadable(fugitive#Find('.git/rebase-merge/amend', dir)) &&
          \ filereadable(fugitive#Find('.git/rebase-merge/done', dir)) &&
          \ get(readfile(fugitive#Find('.git/rebase-merge/done', dir)), -1, '') =~# '^[^e]'
      cclose
      return 'exe ' . string(mods . 'Gcommit --amend -n -F ' . s:fnameescape(fugitive#Find('.git/rebase-merge/message', dir)) . ' -e') . '|let b:fugitive_commit_rebase = 1'
    elseif !had_merge_msg && filereadable(fugitive#Find('.git/MERGE_MSG', dir))
      cclose
      return mods . 'Gcommit --no-status -n -t '.s:fnameescape(fugitive#Find('.git/MERGE_MSG', dir))
    endif
  endif
  let qflist = getqflist()
  let found = 0
  for e in qflist
    if !empty(e.bufnr)
      let found = 1
      let e.pattern = '^<<<<<<<'
    endif
  endfor
  call fugitive#Cwindow()
  if found
    call setqflist(qflist, 'r')
    if !a:bang
      call s:BlurStatus()
      return 'cfirst'
    endif
  endif
  return exists('err') ? 'echoerr '.string(err) : 'exe'
endfunction

function! s:RebaseClean(file) abort
  if !filereadable(a:file)
    return ''
  endif
  let old = readfile(a:file)
  let new = copy(old)
  for i in range(len(new))
    let new[i] = substitute(new[i], '^\l\>', '\=get(s:rebase_abbrevs,submatch(0),submatch(0))', '')

    let sha = matchstr(new[i], '\C\<[a-f0-9]\{5,\}\>')
    let rebase_shas = getbufvar(a:file, 'fugitive_rebase_shas')
    if len(sha) && type(rebase_shas) == type({}) && has_key(rebase_shas, sha)
      let new[i] = substitute(new[i], '\C\<' . sha . '\>', rebase_shas[sha], '')
    endif
  endfor
  if new !=# old
    call writefile(new, a:file)
  endif
  return ''
endfunction

function! s:MergeCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  let [args, after] = s:SplitExpandChain(a:arg, s:Tree())
  return s:MergeRebase('merge', a:bang, a:mods, args) . after
endfunction

function! s:RebaseCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  let [args, after] = s:SplitExpandChain(a:arg, s:Tree())
  return s:MergeRebase('rebase', a:bang, a:mods, args) . after
endfunction

function! s:PullCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  let [args, after] = s:SplitExpandChain(a:arg, s:Tree())
  return s:MergeRebase('pull --progress', a:bang, a:mods, args) . after
endfunction

augroup fugitive_merge
  autocmd!
  autocmd VimLeavePre,BufDelete git-rebase-todo
        \ if getbufvar(+expand('<abuf>'), '&bufhidden') ==# 'wipe' |
        \   call s:RebaseClean(expand('<afile>')) |
        \   if getfsize(FugitiveFind('.git/rebase-merge/done', +expand('<abuf>'))) == 0 |
        \     let s:rebase_continue = FugitiveGitDir(+expand('<abuf>')) |
        \   endif |
        \ endif
  autocmd BufEnter * nested
        \ if exists('s:rebase_continue') |
        \   exe s:MergeRebase('rebase', 0, '', [getfsize(fugitive#Find('.git/rebase-merge/git-rebase-todo', s:rebase_continue)) > 0 ? '--continue' : '--abort'], remove(s:, 'rebase_continue')) |
        \ endif
augroup END

call s:command("-nargs=? -bang -complete=customlist,s:MergeComplete Gmerge", "Merge")
call s:command("-nargs=? -bang -complete=customlist,s:RebaseComplete Grebase", "Rebase")
call s:command("-nargs=? -bang -complete=customlist,s:PullComplete Gpull", "Pull")

" Section: :Ggrep, :Glog

if !exists('g:fugitive_summary_format')
  let g:fugitive_summary_format = '%s'
endif

function! s:GrepComplete(A, L, P) abort
  return s:CompleteSubcommand('grep', a:A, a:L, a:P)
endfunction

function! s:LogComplete(A, L, P) abort
  return s:CompleteSubcommand('log', a:A, a:L, a:P)
endfunction

function! s:GrepParseLine(prefix, name_only, dir, line) abort
  let entry = {'valid': 1}
  let match = matchlist(a:line, '^\(.\{-\}\):\(\d\+\):\(\d\+:\)\=\(.*\)$')
  if len(match)
    let entry.module = match[1]
    let entry.lnum = +match[2]
    let entry.col = +match[3]
    let entry.text = match[4]
  elseif a:line =~# '^git: \|^usage: \|^error: \|^fatal: '
    return {'text': a:line}
  else
    let entry.module = matchstr(a:line, '\CBinary file \zs.*\ze matches$')
    if len(entry.module)
      let entry.text = 'Binary file'
      let entry.valid = 0
    endif
  endif
  if empty(entry.module) && a:name_only
    let entry.module = a:line
  endif
  if empty(entry.module)
    return {'text': a:line}
  endif
  if entry.module !~# ':'
    let entry.filename = a:prefix . entry.module
  else
    let entry.filename = fugitive#Find(entry.module, a:dir)
  endif
  return entry
endfunction

function! s:Grep(type, bang, arg) abort
  let dir = s:Dir()
  let listnr = a:type =~# '^l' ? 0 : -1
  let cmd = s:UserCommandList(dir) + ['--no-pager', 'grep', '-n', '--no-color', '--full-name']
  if fugitive#GitVersion(2, 19)
    call add(cmd, '--column')
  endif
  let tree = s:Tree(dir)
  let [args, after] = s:SplitExpandChain(a:arg, tree)
  let prefix = s:PlatformSlash(s:HasOpt(args, '--cached') || empty(tree) ? 'fugitive://' . dir . '//0/' : tree . '/')
  let name_only = s:HasOpt(args, '-l', '--files-with-matches', '--name-only', '-L', '--files-without-match')
  let title = [listnr < 0 ? ':Ggrep' : ':Glgrep'] + args
  call s:QuickfixCreate(listnr, {'title': (listnr < 0 ? ':Ggrep ' : ':Glgrep ') . s:fnameescape(args)})
  let tempfile = tempname()
  exe '!' . s:shellesc(cmd + args)
        \ printf(&shellpipe . (&shellpipe =~# '%s' ? '' : ' %s'), s:shellesc(tempfile))
  let list = map(readfile(tempfile), 's:GrepParseLine(prefix, name_only, dir, v:val)')
  call s:QuickfixSet(listnr, list, 'a')
  if !a:bang && !empty(list)
    call s:BlurStatus()
    return (listnr < 0 ? 'c' : 'l').'first' . after
  else
    return after[1:-1]
  endif
endfunction

function! s:LogFlushQueue(state) abort
  let queue = remove(a:state, 'queue')
  if a:state.child_found
    call remove(queue, 0)
  endif
  if len(queue) && queue[-1] ==# {'text': ''}
    call remove(queue, -1)
  endif
  return queue
endfunction

function! s:LogParse(state, target, dir, line) abort
  if a:state.context ==# 'hunk' && a:line =~# '^[-+ ]'
    return []
  endif
  let list = matchlist(a:line, '^\%(fugitive \(.\{-\}\)\t\|commit \|From \)\=\(\x\{40,\}\)\%( \(.*\)\)\=$')
  if len(list)
    let a:state.context = 'commit'
    let a:state.base = 'fugitive://' . a:dir . '//' . list[2]
    let a:state.base_module = len(list[1]) ? list[1] : list[2]
    let a:state.message = list[3]
    if has_key(a:state, 'diffing')
      call remove(a:state, 'diffing')
    endif
    let queue = s:LogFlushQueue(a:state)
    let a:state.queue = [{
          \ 'valid': 1,
          \ 'filename': a:state.base . a:target,
          \ 'module': a:state.base_module . substitute(a:target, '^/', ':', ''),
          \ 'text': a:state.message}]
    let a:state.child_found = 0
    return queue
  elseif type(a:line) == type(0)
    return s:LogFlushQueue(a:state)
  elseif a:line =~# '^diff'
    let a:state.context = 'diffhead'
  elseif a:line =~# '^[+-]\{3\} \w/' && a:state.context ==# 'diffhead'
    let a:state.diffing = a:line[5:-1]
  elseif a:line =~# '^@@[^@]*+\d' && has_key(a:state, 'diffing') && has_key(a:state, 'base')
    let a:state.context = 'hunk'
    if empty(a:target) || a:target ==# a:state.diffing
      let a:state.child_found = 1
      call add(a:state.queue, {
            \ 'valid': 1,
            \ 'filename': a:state.base . a:state.diffing,
            \ 'module': a:state.base_module . substitute(a:state.diffing, '^/', ':', ''),
            \ 'lnum': +matchstr(a:line, '+\zs\d\+'),
            \ 'text': a:state.message . matchstr(a:line, ' @@\+ .\+')})
    endif
  elseif a:state.context ==# 'commit' || a:state.context ==# 'init'
    call add(a:state.queue, {'text': a:line})
  endif
  return []
endfunction

function! s:Log(type, bang, line1, count, args) abort
  let dir = s:Dir()
  let listnr = a:type =~# '^l' ? 0 : -1
  let [args, after] = s:SplitExpandChain(a:args, s:Tree(dir))
  let split = index(args, '--')
  if split > 0
    let paths = args[split : -1]
    let args = args[0 : split - 1]
  elseif split == 0
    let paths = args
    let args = []
  else
    let paths = []
  endif
  if a:line1 == 0 && a:count
    let path = fugitive#Path(bufname(a:count), '/', dir)
  elseif a:count >= 0
    let path = fugitive#Path(@%, '/', dir)
  else
     let path = ''
  endif
  let range = ''
  let extra = []
  if path =~# '^/\.git\%(/\|$\)\|^$'
    let path = ''
  elseif a:line1 == 0
    let range = "0," . (a:count ? a:count : bufnr(''))
    let extra = (len(paths) ? [] : ['--']) + [path[1:-1]]
  elseif a:count > 0
    if !s:HasOpt(args, '--merges', '--no-merges')
      call insert(args, '--no-merges')
    endif
    call add(args, '-L' . a:line1 . ',' . a:count . ':' . path[1:-1])
  endif
  if len(path) && empty(filter(copy(args), 'v:val =~# "^[^-]"'))
    let owner = s:Owner(@%, dir)
    if len(owner)
      call add(args, owner)
    endif
  endif
  if empty(extra)
    let path = ''
  endif
  if s:HasOpt(args, '-g', '--walk-reflogs')
    let format = "%gd\t%H %gs"
  else
    let format = "%h\t%H " . g:fugitive_summary_format
  endif
  let cmd = s:UserCommandList(dir) + ['--no-pager']
  if fugitive#GitVersion(1, 9)
    call extend(cmd, ['-c', 'diff.context=0', 'log'])
  else
    call extend(cmd, ['log', '-U0', '--no-patch'])
  endif
  call extend(cmd,
        \ ['--no-color', '--no-ext-diff', '--pretty=format:fugitive ' . format] +
        \ args + paths + extra)
  let state = {'context': 'init', 'child_found': 0, 'queue': []}
  let title = (listnr < 0 ? ':Glog ' : ':Gllog ') . s:fnameescape(args + paths)
  return s:QuickfixStream(listnr, title, cmd, !a:bang, s:function('s:LogParse'), state, path, dir) . after
endfunction

call s:command("-bang -nargs=? -complete=customlist,s:GrepComplete Ggrep :execute s:Grep('c',<bang>0,<q-args>)")
call s:command("-bang -nargs=? -complete=customlist,s:GrepComplete Gcgrep :execute s:Grep('c',<bang>0,<q-args>)")
call s:command("-bang -nargs=? -complete=customlist,s:GrepComplete Glgrep :execute s:Grep('l',<bang>0,<q-args>)")
call s:command("-bang -nargs=? -range=-1 -complete=customlist,s:LogComplete Glog :exe s:Log('c',<bang>0,<line1>,<count>,<q-args>)")
call s:command("-bang -nargs=? -range=-1 -complete=customlist,s:LogComplete Gclog :exe s:Log('c',<bang>0,<line1>,<count>,<q-args>)")
call s:command("-bang -nargs=? -range=-1 -complete=customlist,s:LogComplete Gllog :exe s:Log('l',<bang>0,<line1>,<count>,<q-args>)")

" Section: :Gedit, :Gpedit, :Gsplit, :Gvsplit, :Gtabedit, :Gread

function! s:UsableWin(nr) abort
  return a:nr && !getwinvar(a:nr, '&previewwindow') &&
        \ (empty(getwinvar(a:nr, 'fugitive_status')) || getbufvar(winbufnr(a:nr), 'fugitive_type') !=# 'index') &&
        \ index(['gitrebase', 'gitcommit'], getbufvar(winbufnr(a:nr), '&filetype')) < 0 &&
        \ index(['nofile','help','quickfix'], getbufvar(winbufnr(a:nr), '&buftype')) < 0
endfunction

function! s:OpenParse(args) abort
  let pre = []
  let args = copy(a:args)
  while !empty(args) && args[0] =~# '^+'
    call add(pre, ' ' . escape(remove(args, 0), ' |"'))
  endwhile
  if len(args)
    let file = join(args)
  elseif empty(expand('%'))
    let file = ':'
  elseif empty(s:DirCommitFile(@%)[1]) && s:Relative('./') !~# '^\./\.git\>'
    let file = ':0:%'
  else
    let file = '%'
  endif
  return [s:Expand(file), join(pre)]
endfunction

function! s:BlurStatus() abort
  if (&previewwindow || exists('w:fugitive_status')) && get(b:,'fugitive_type', '') ==# 'index'
    let winnrs = filter([winnr('#')] + range(1, winnr('$')), 's:UsableWin(v:val)')
    if len(winnrs)
      exe winnrs[0].'wincmd w'
    else
      belowright new
    endif
    if &diff
      let mywinnr = winnr()
      for winnr in range(winnr('$'),1,-1)
        if winnr != mywinnr && getwinvar(winnr,'&diff')
          execute winnr.'wincmd w'
          close
          if winnr('$') > 1
            wincmd p
          endif
        endif
      endfor
      diffoff!
    endif
  endif
endfunction

function! s:OpenExec(cmd, mods, args, ...) abort
  let dir = a:0 ? s:Dir(a:1) : s:Dir()
  let args = s:shellesc(a:args)
  let temp = tempname()
  let git = s:UserCommand(dir)
  silent! execute '!' . escape(git . ' --no-pager ' . args, '!#%') .
        \ (&shell =~# 'csh' ? ' >& ' . temp : ' > ' . temp . ' 2>&1')
  redraw!
  let temp = s:Resolve(temp)
  let s:temp_files[s:cpath(temp)] = { 'dir': dir, 'filetype': 'git' }
  if a:cmd ==# 'edit'
    call s:BlurStatus()
  endif
  silent execute s:Mods(a:mods) . a:cmd temp
  call fugitive#ReloadStatus(dir, 1)
  return 'echo ' . string(':!' . git . ' ' . args)
endfunction

function! s:Open(cmd, bang, mods, arg, args) abort
  if a:bang
    return s:OpenExec(a:cmd, a:mods, s:SplitExpand(a:arg, s:Tree()))
  endif

  let mods = s:Mods(a:mods)
  try
    let [file, pre] = s:OpenParse(a:args)
    let file = s:Generate(file)
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
  if file !~# '^\a\a\+:'
    let file = s:sub(file, '/$', '')
  endif
  if a:cmd ==# 'edit'
    call s:BlurStatus()
  endif
  return mods . a:cmd . pre . ' ' . s:fnameescape(file)
endfunction

function! s:ReadCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  let mods = s:Mods(a:mods)
  let after = a:count
  if a:count < 0
    let delete = 'silent 1,' . line('$') . 'delete_|'
    let after = line('$')
  elseif a:range == 2
    let delete = 'silent ' . a:line1 . ',' . a:count . 'delete_|'
  else
    let delete = ''
  endif
  if a:bang
    let dir = s:Dir()
    let git = s:UserCommand(dir)
    let args = s:shellesc(s:SplitExpand(a:arg, s:Tree(dir)))
    silent execute mods . after . 'read!' escape(git . ' --no-pager ' . args, '!#%')
    execute delete . 'diffupdate'
    call fugitive#ReloadStatus()
    return 'redraw|echo '.string(':!'.git.' '.args)
  endif
  try
    let [file, pre] = s:OpenParse(a:args)
    let file = s:Generate(file)
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
  if file =~# '^fugitive:' && after is# 0
    return 'exe ' .string(mods . fugitive#FileReadCmd(file, 0, pre)) . '|diffupdate'
  endif
  if foldlevel(after)
    exe after . 'foldopen!'
  endif
  return mods . after . 'read' . pre . ' ' . s:fnameescape(file) . '|' . delete . 'diffupdate' . (a:count < 0 ? '|' . line('.') : '')
endfunction

function! s:ReadComplete(A,L,P) abort
  if a:L =~# '^\w\+!'
    return fugitive#CompleteGit(a:A, a:L, a:P)
  else
    return fugitive#CompleteObject(a:A, a:L, a:P)
  endif
endfunction

call s:command("-bar -bang -nargs=*           -complete=customlist,fugitive#CompleteObject Ge       execute s:Open('edit<bang>', 0, '<mods>', <q-args>, [<f-args>])")
call s:command("-bar -bang -nargs=*           -complete=customlist,fugitive#CompleteObject Gedit    execute s:Open('edit<bang>', 0, '<mods>', <q-args>, [<f-args>])")
call s:command("-bar -bang -nargs=*           -complete=customlist,s:ReadComplete Gpedit   execute s:Open('pedit', <bang>0, '<mods>', <q-args>, [<f-args>])")
call s:command("-bar -bang -nargs=* -range=-1 -complete=customlist,s:ReadComplete Gsplit   execute s:Open((<count> > 0 ? <count> : '').(<count> ? 'split' : 'edit'), <bang>0, '<mods>', <q-args>, [<f-args>])")
call s:command("-bar -bang -nargs=* -range=-1 -complete=customlist,s:ReadComplete Gvsplit  execute s:Open((<count> > 0 ? <count> : '').(<count> ? 'vsplit' : 'edit!'), <bang>0, '<mods>', <q-args>, [<f-args>])")
call s:command("-bar -bang -nargs=* -range=-1 -complete=customlist,s:ReadComplete" . (has('patch-7.4.542') ? ' -addr=tabs' : '') . " Gtabedit execute s:Open((<count> >= 0 ? <count> : '').'tabedit', <bang>0, '<mods>', <q-args>, [<f-args>])")
call s:command("-bar -bang -nargs=* -range=-1 -complete=customlist,s:ReadComplete Gread", "Read")

" Section: :Gwrite, :Gwq

call s:command("-bar -bang -nargs=* -complete=customlist,fugitive#CompleteObject Gwrite", "Write")
call s:command("-bar -bang -nargs=* -complete=customlist,fugitive#CompleteObject Gw", "Write")
call s:command("-bar -bang -nargs=* -complete=customlist,fugitive#CompleteObject Gwq", "Wq")

function! s:WriteCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  if exists('b:fugitive_commit_arguments')
    return 'write|bdelete'
  elseif expand('%:t') == 'COMMIT_EDITMSG' && $GIT_INDEX_FILE != ''
    return 'wq'
  elseif get(b:, 'fugitive_type', '') ==# 'index'
    return 'Gcommit'
  elseif &buftype ==# 'nowrite' && getline(4) =~# '^+++ '
    let filename = getline(4)[6:-1]
    setlocal buftype=
    silent write
    setlocal buftype=nowrite
    if matchstr(getline(2),'index [[:xdigit:]]\+\.\.\zs[[:xdigit:]]\{7\}') ==# fugitive#RevParse(':0:'.filename)[0:6]
      let err = s:TreeChomp('apply', '--cached', '--reverse', '--', expand('%:p'))
    else
      let err = s:TreeChomp('apply', '--cached', '--', expand('%:p'))
    endif
    if err !=# ''
      let v:errmsg = split(err,"\n")[0]
      return 'echoerr v:errmsg'
    elseif a:bang
      return 'bdelete'
    else
      return 'Gedit '.fnameescape(filename)
    endif
  endif
  let mytab = tabpagenr()
  let mybufnr = bufnr('')
  try
    let file = len(a:args) ? s:Generate(s:Expand(join(a:args, ' '))) : fugitive#Real(@%)
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
  if empty(file)
    return 'echoerr '.string('fugitive: cannot determine file path')
  endif
  if file =~# '^fugitive:'
    return 'write' . (a:bang ? '! ' : ' ') . s:fnameescape(file)
  endif
  let always_permitted = s:cpath(fugitive#Real(@%), file) && s:DirCommitFile(@%)[1] =~# '^0\=$'
  if !always_permitted && !a:bang && (len(s:TreeChomp('diff', '--name-status', 'HEAD', '--', file)) || len(s:TreeChomp('ls-files', '--others', '--', file)))
    let v:errmsg = 'fugitive: file has uncommitted changes (use ! to override)'
    return 'echoerr v:errmsg'
  endif
  let treebufnr = 0
  for nr in range(1,bufnr('$'))
    if fnamemodify(bufname(nr),':p') ==# file
      let treebufnr = nr
    endif
  endfor

  if treebufnr > 0 && treebufnr != bufnr('')
    let temp = tempname()
    silent execute '%write '.temp
    for tab in [mytab] + range(1,tabpagenr('$'))
      for winnr in range(1,tabpagewinnr(tab,'$'))
        if tabpagebuflist(tab)[winnr-1] == treebufnr
          execute 'tabnext '.tab
          if winnr != winnr()
            execute winnr.'wincmd w'
            let restorewinnr = 1
          endif
          try
            let lnum = line('.')
            let last = line('$')
            silent execute '$read '.temp
            silent execute '1,'.last.'delete_'
            silent write!
            silent execute lnum
            let did = 1
          finally
            if exists('restorewinnr')
              wincmd p
            endif
            execute 'tabnext '.mytab
          endtry
        endif
      endfor
    endfor
    if !exists('did')
      call writefile(readfile(temp,'b'),file,'b')
    endif
  else
    execute 'write! '.s:fnameescape(file)
  endif

  if a:bang
    let [error, exec_error] = s:ChompError(['add', '--force', '--', file])
  else
    let [error, exec_error] = s:ChompError(['add', '--', file])
  endif
  if exec_error
    let v:errmsg = 'fugitive: '.error
    return 'echoerr v:errmsg'
  endif
  if s:cpath(fugitive#Real(@%), file) && s:DirCommitFile(@%)[1] =~# '^\d$'
    setlocal nomodified
  endif

  let one = s:Generate(':1:'.file)
  let two = s:Generate(':2:'.file)
  let three = s:Generate(':3:'.file)
  for nr in range(1,bufnr('$'))
    let name = fnamemodify(bufname(nr), ':p')
    if bufloaded(nr) && !getbufvar(nr,'&modified') && (name ==# one || name ==# two || name ==# three)
      execute nr.'bdelete'
    endif
  endfor

  unlet! restorewinnr
  let zero = s:Generate(':0:'.file)
  silent execute 'doautocmd BufWritePost' s:fnameescape(zero)
  for tab in range(1,tabpagenr('$'))
    for winnr in range(1,tabpagewinnr(tab,'$'))
      let bufnr = tabpagebuflist(tab)[winnr-1]
      let bufname = fnamemodify(bufname(bufnr), ':p')
      if bufname ==# zero && bufnr != mybufnr
        execute 'tabnext '.tab
        if winnr != winnr()
          execute winnr.'wincmd w'
          let restorewinnr = 1
        endif
        try
          let lnum = line('.')
          let last = line('$')
          silent execute '$read '.s:fnameescape(file)
          silent execute '1,'.last.'delete_'
          silent execute lnum
          setlocal nomodified
          diffupdate
        finally
          if exists('restorewinnr')
            wincmd p
          endif
          execute 'tabnext '.mytab
        endtry
        break
      endif
    endfor
  endfor
  call fugitive#ReloadStatus()
  return 'checktime'
endfunction

function! s:WqCommand(...) abort
  let bang = a:5 ? '!' : ''
  if exists('b:fugitive_commit_arguments')
    return 'wq'.bang
  endif
  let result = call(s:function('s:WriteCommand'),a:000)
  if result =~# '^\%(write\|wq\|echoerr\)'
    return s:sub(result,'^write','wq')
  else
    return result.'|quit'.bang
  endif
endfunction

augroup fugitive_commit
  autocmd!
  autocmd VimLeavePre,BufDelete COMMIT_EDITMSG execute substitute(s:FinishCommit(), '\C^echoerr \(''[^'']*''\)*', 'redraw|echohl ErrorMsg|echo \1|echohl NONE', '')
augroup END

" Section: :Gpush, :Gfetch

function! s:PushComplete(A, L, P) abort
  return s:CompleteSubcommand('push', a:A, a:L, a:P, function('s:CompleteRemote'))
endfunction

function! s:FetchComplete(A, L, P) abort
  return s:CompleteSubcommand('fetch', a:A, a:L, a:P, function('s:CompleteRemote'))
endfunction

function! s:Dispatch(bang, cmd, arg) abort
  let dir = s:Dir()
  let [args, after] = s:SplitExpandChain(a:arg, s:Tree(dir))
  let [mp, efm, cc] = [&l:mp, &l:efm, get(b:, 'current_compiler', '')]
  try
    let b:current_compiler = 'git'
    let &l:errorformat = s:common_efm
    let &l:makeprg = s:shellesc(s:UserCommandList(dir) + [a:cmd] + args)
    if exists(':Make') == 2
      Make
      return after[1:-1]
    else
      if !has('patch-8.1.0334') && has('terminal') && &autowrite
        let autowrite_was_set = 1
        set noautowrite
        silent! wall
      endif
      silent noautocmd make!
      redraw!
      return 'call fugitive#Cwindow()|call fugitive#ReloadStatus()' . after
    endif
  finally
    let [&l:mp, &l:efm, b:current_compiler] = [mp, efm, cc]
    if empty(cc) | unlet! b:current_compiler | endif
    if exists('autowrite_was_set')
      set autowrite
    endif
  endtry
endfunction

function! s:PushCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  return s:Dispatch(a:bang ? '!' : '', 'push', a:arg)
endfunction

function! s:FetchCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  return s:Dispatch(a:bang ? '!' : '', 'fetch', a:arg)
endfunction

call s:command("-nargs=? -bang -complete=customlist,s:PushComplete Gpush", "Push")
call s:command("-nargs=? -bang -complete=customlist,s:FetchComplete Gfetch", "Fetch")

" Section: :Gdiff

call s:command("-bang -bar -nargs=* -complete=customlist,fugitive#CompleteObject Gdiffsplit  :execute s:Diff(1, <bang>0, '<mods>', <f-args>)")
call s:command("-bang -bar -nargs=* -complete=customlist,fugitive#CompleteObject Gvdiffsplit :execute s:Diff(0, <bang>0, 'vertical <mods>', <f-args>)")
call s:command("-bang -bar -nargs=* -complete=customlist,fugitive#CompleteObject Ghdiffsplit :execute s:Diff(0, <bang>0, '<mods>', <f-args>)")

augroup fugitive_diff
  autocmd!
  autocmd BufWinLeave *
        \ if s:can_diffoff(+expand('<abuf>')) && s:diff_window_count() == 2 |
        \   call s:diffoff_all(s:Dir(+expand('<abuf>'))) |
        \ endif
  autocmd BufWinEnter *
        \ if s:can_diffoff(+expand('<abuf>')) && s:diff_window_count() == 1 |
        \   call s:diffoff() |
        \ endif
augroup END

function! s:can_diffoff(buf) abort
  return getwinvar(bufwinnr(a:buf), '&diff') &&
        \ !empty(s:Dir(a:buf)) &&
        \ !empty(getwinvar(bufwinnr(a:buf), 'fugitive_diff_restore'))
endfunction

function! fugitive#CanDiffoff(buf) abort
  return s:can_diffoff(bufnr(a:buf))
endfunction

function! s:diff_modifier(count) abort
  let fdc = matchstr(&diffopt, 'foldcolumn:\zs\d\+')
  if &diffopt =~# 'horizontal' && &diffopt !~# 'vertical'
    return ''
  elseif &diffopt =~# 'vertical'
    return 'vertical '
  elseif winwidth(0) <= a:count * ((&tw ? &tw : 80) + (empty(fdc) ? 2 : fdc))
    return ''
  else
    return 'vertical '
  endif
endfunction

function! s:diff_window_count() abort
  let c = 0
  for nr in range(1,winnr('$'))
    let c += getwinvar(nr,'&diff')
  endfor
  return c
endfunction

function! s:diff_restore() abort
  let restore = 'setlocal nodiff noscrollbind'
        \ . ' scrollopt=' . &l:scrollopt
        \ . (&l:wrap ? ' wrap' : ' nowrap')
        \ . ' foldlevel=999'
        \ . ' foldmethod=' . &l:foldmethod
        \ . ' foldcolumn=' . &l:foldcolumn
        \ . ' foldlevel=' . &l:foldlevel
        \ . (&l:foldenable ? ' foldenable' : ' nofoldenable')
  if has('cursorbind')
    let restore .= (&l:cursorbind ? ' ' : ' no') . 'cursorbind'
  endif
  return restore
endfunction

function! s:diffthis() abort
  if !&diff
    let w:fugitive_diff_restore = s:diff_restore()
    diffthis
  endif
endfunction

function! s:diffoff() abort
  if exists('w:fugitive_diff_restore')
    execute w:fugitive_diff_restore
    unlet w:fugitive_diff_restore
  else
    diffoff
  endif
endfunction

function! s:diffoff_all(dir) abort
  let curwin = winnr()
  for nr in range(1,winnr('$'))
    if getwinvar(nr,'&diff')
      if nr != winnr()
        execute nr.'wincmd w'
        let restorewinnr = 1
      endif
      if s:Dir() ==# a:dir
        call s:diffoff()
      endif
    endif
  endfor
  execute curwin.'wincmd w'
endfunction

function! s:CompareAge(mine, theirs) abort
  let scores = {':0': 1, ':1': 2, ':2': 3, ':': 4, ':3': 5}
  let mine = substitute(a:mine, '^:', '', '')
  let theirs = substitute(a:theirs, '^:', '', '')
  let my_score    = get(scores, ':'.mine, 0)
  let their_score = get(scores, ':'.theirs, 0)
  if my_score || their_score
    return my_score < their_score ? -1 : my_score != their_score
  elseif mine ==# theirs
    return 0
  endif
  let base = s:TreeChomp('merge-base', mine, theirs)
  if base ==# mine
    return -1
  elseif base ==# theirs
    return 1
  endif
  let my_time    = +s:TreeChomp('log', '--max-count=1', '--pretty=format:%at', a:mine, '--')
  let their_time = +s:TreeChomp('log', '--max-count=1', '--pretty=format:%at', a:theirs, '--')
  return my_time < their_time ? -1 : my_time != their_time
endfunction

function! s:IsConflicted() abort
  return len(@%) && !empty(s:ChompDefault('', 'ls-files', '--unmerged', '--', expand('%:p')))
endfunction

function! s:Diff(autodir, keepfocus, mods, ...) abort
  if exists(':DiffGitCached') && !a:0
    return s:Mods(a:mods) . 'DiffGitCached'
  endif
  let args = copy(a:000)
  let post = ''
  if get(args, 0) =~# '^+'
    let post = remove(args, 0)[1:-1]
  endif
  let commit = s:DirCommitFile(@%)[1]
  if a:mods =~# '\<tab\>'
    let mods = substitute(a:mods, '\<tab\>', '', 'g')
    tab split
  else
    let mods = 'keepalt ' . a:mods
  endif
  let back = exists('*win_getid') ? 'call win_gotoid(' . win_getid() . ')' : 'wincmd p'
  if (empty(args) || args[0] ==# ':') && commit =~# '^[0-1]\=$' && a:keepfocus && s:IsConflicted()
    let mods = (a:autodir ? s:diff_modifier(3) : '') . s:Mods(mods, 'leftabove')
    let nr = bufnr('')
    execute mods 'split' s:fnameescape(s:Generate(s:Relative(':2:')))
    execute 'nnoremap <buffer> <silent> dp :diffput '.nr.'<Bar>diffupdate<CR>'
    let nr2 = bufnr('')
    call s:diffthis()
    exe back
    let mods = substitute(mods, '\Cleftabove\|rightbelow\|aboveleft\|belowright', '\=submatch(0) =~# "f" ? "rightbelow" : "leftabove"', '')
    execute mods 'split' s:fnameescape(s:Generate(s:Relative(':3:')))
    execute 'nnoremap <buffer> <silent> dp :diffput '.nr.'<Bar>diffupdate<CR>'
    let nr3 = bufnr('')
    call s:diffthis()
    exe back
    call s:diffthis()
    execute 'nnoremap <buffer> <silent> d2o :diffget '.nr2.'<Bar>diffupdate<CR>'
    execute 'nnoremap <buffer> <silent> d3o :diffget '.nr3.'<Bar>diffupdate<CR>'
    return post
  elseif len(args)
    let arg = join(args, ' ')
    if arg ==# ''
      return post
    elseif arg ==# '/'
      let file = s:Relative()
    elseif arg ==# ':'
      let file = s:Relative(':0:')
    else
      try
        let file = arg =~# '^:/.' ? fugitive#RevParse(arg) . s:Relative(':') : s:Expand(arg)
      catch /^fugitive:/
        return 'echoerr ' . string(v:exception)
      endtry
    endif
    if file !~# ':' && file !~# '^/' && s:TreeChomp('cat-file','-t',file) =~# '^\%(tag\|commit\)$'
      let file = file.s:Relative(':')
    endif
  elseif len(commit)
    let file = s:Relative()
  elseif s:IsConflicted()
    let file = s:Relative(':1:')
    let post = 'echohl WarningMsg|echo "Use :Gdiffsplit! for 3 way diff"|echohl NONE|' . post
  else
    let file = s:Relative(':0:')
  endif
  try
    let spec = s:Generate(file)
    let restore = s:diff_restore()
    if exists('+cursorbind')
      setlocal cursorbind
    endif
    let w:fugitive_diff_restore = restore
    if s:CompareAge(commit, s:DirCommitFile(spec)[1]) < 0
      let mods = s:Mods(mods, 'rightbelow')
    else
      let mods = s:Mods(mods, 'leftabove')
    endif
    let mods = (a:autodir ? s:diff_modifier(2) : '') . mods
    execute mods 'diffsplit' s:fnameescape(spec)
    let &l:readonly = &l:readonly
    redraw
    let w:fugitive_diff_restore = restore
    let winnr = winnr()
    if getwinvar('#', '&diff')
      exe back
      if !a:keepfocus
        call feedkeys(winnr."\<C-W>w", 'n')
      endif
    endif
    return post
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
endfunction

" Section: :Gmove, :Gremove

function! s:Move(force, rename, destination) abort
  if a:destination =~# '^\.\.\=\%(/\|$\)'
    let destination = simplify(getcwd() . '/' . a:destination)
  elseif a:destination =~# '^\a\+:\|^/'
    let destination = a:destination
  elseif a:destination =~# '^:/:\='
    let destination = s:Tree() . substitute(a:destination, '^:/:\=', '', '')
  elseif a:destination =~# '^:(\%(top\|top,literal\|literal,top\))'
    let destination = s:Tree() . matchstr(a:destination, ')\zs.*')
  elseif a:destination =~# '^:(literal)'
    let destination = simplify(getcwd() . '/' . matchstr(a:destination, ')\zs.*'))
  elseif a:rename
    let destination = expand('%:p:s?[\/]$??:h') . '/' . a:destination
  else
    let destination = s:Tree() . '/' . a:destination
  endif
  let destination = s:Slash(destination)
  if isdirectory(@%)
    setlocal noswapfile
  endif
  let [message, exec_error] = s:ChompError(['mv'] + (a:force ? ['-f'] : []) + ['--', expand('%:p'), destination])
  if exec_error
    let v:errmsg = 'fugitive: '.message
    return 'echoerr v:errmsg'
  endif
  if isdirectory(destination)
    let destination = fnamemodify(s:sub(destination,'/$','').'/'.expand('%:t'),':.')
  endif
  call fugitive#ReloadStatus()
  if empty(s:DirCommitFile(@%)[1])
    if isdirectory(destination)
      return 'keepalt edit '.s:fnameescape(destination)
    else
      return 'keepalt saveas! '.s:fnameescape(destination)
    endif
  else
    return 'file '.s:fnameescape(s:Generate(':0:'.destination))
  endif
endfunction

function! s:RenameComplete(A,L,P) abort
  if a:A =~# '^[.:]\=/'
    return fugitive#CompletePath(a:A)
  else
    let pre = s:Slash(fnamemodify(expand('%:p:s?[\/]$??'), ':h')) . '/'
    return map(fugitive#CompletePath(pre.a:A), 'strpart(v:val, len(pre))')
  endif
endfunction

function! s:Remove(after, force) abort
  if s:DirCommitFile(@%)[1] ==# ''
    let cmd = ['rm']
  elseif s:DirCommitFile(@%)[1] ==# '0'
    let cmd = ['rm','--cached']
  else
    let v:errmsg = 'fugitive: rm not supported here'
    return 'echoerr v:errmsg'
  endif
  if a:force
    let cmd += ['--force']
  endif
  let [message, exec_error] = s:ChompError(cmd + ['--', expand('%:p')])
  if exec_error
    let v:errmsg = 'fugitive: '.s:sub(message,'error:.*\zs\n\(.*-f.*',' (add ! to force)')
    return 'echoerr '.string(v:errmsg)
  else
    call fugitive#ReloadStatus()
    return a:after . (a:force ? '!' : '')
  endif
endfunction

augroup fugitive_remove
  autocmd!
  autocmd User Fugitive if s:DirCommitFile(@%)[1] =~# '^0\=$' |
        \ exe "command! -buffer -bar -bang -nargs=1 -complete=customlist,fugitive#CompletePath Gmove :execute s:Move(<bang>0,0,<q-args>)" |
        \ exe "command! -buffer -bar -bang -nargs=1 -complete=customlist,s:RenameComplete Grename :execute s:Move(<bang>0,1,<q-args>)" |
        \ exe "command! -buffer -bar -bang Gremove :execute s:Remove('edit',<bang>0)" |
        \ exe "command! -buffer -bar -bang Gdelete :execute s:Remove('bdelete',<bang>0)" |
        \ endif
augroup END

" Section: :Gblame

function! s:Keywordprg() abort
  let args = ' --git-dir='.escape(s:Dir(),"\\\"' ")
  if has('gui_running') && !has('win32')
    return s:UserCommand() . ' --no-pager' . args . ' log -1'
  else
    return s:UserCommand() . args . ' show'
  endif
endfunction

augroup fugitive_blame
  autocmd!
  autocmd FileType fugitiveblame setlocal nomodeline | if len(s:Dir()) | let &l:keywordprg = s:Keywordprg() | endif
  autocmd User Fugitive
        \ if get(b:, 'fugitive_type') =~# '^\%(file\|blob\|blame\)$' || filereadable(@%) |
        \   exe "command! -buffer -bar -bang -range=-1 -nargs=* Gblame :execute s:BlameCommand(<line1>,<line2>,+'<range>',<count>,<bang>0,'<mods>',<q-reg>,<q-args>,[<f-args>])" |
        \ endif
  autocmd ColorScheme,GUIEnter * call s:RehighlightBlame()
  autocmd BufWinLeave * execute getwinvar(+bufwinnr(+expand('<abuf>')), 'fugitive_leave')
augroup END

function! s:linechars(pattern) abort
  let chars = strlen(s:gsub(matchstr(getline('.'), a:pattern), '.', '.'))
  if exists('*synconcealed') && &conceallevel > 1
    for col in range(1, chars)
      let chars -= synconcealed(line('.'), col)[0]
    endfor
  endif
  return chars
endfunction

function! s:BlameCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  if exists('b:fugitive_blamed_bufnr')
    return 'bdelete'
  endif
  try
    if empty(s:Relative('/'))
      call s:throw('file or blob required')
    endif
    if filter(copy(a:args),'v:val !~# "^-"') != []
      call s:throw("'-' required for all options")
    elseif filter(copy(a:args),'v:val !~# "^\\%(--abbrev=\\d*\\|--relative-date\\|--first-parent\\|--root\\|--show-name\\|-\\%([ltfnsew]\\|[MC]\\d*\\)\\+\\)$"') != []
      call s:throw('unsupported option')
    endif
    let cmd = ['--no-pager', 'blame', '--show-number']
    if a:count > 0
      let cmd += ['-L', (a:line1 ? a:line1 : line('.')) . ',' . (a:line1 ? a:line1 : line('.'))]
    endif
    let cmd += a:args
    if s:DirCommitFile(@%)[1] =~# '\D\|..'
      let cmd += [s:DirCommitFile(@%)[1]]
    else
      let cmd += ['--contents', '-']
    endif
    let cmd += ['--', expand('%:p')]
    let basecmd = escape(fugitive#Prepare(cmd), '!#%')
    let error = tempname()
    let temp = error.'.fugitiveblame'
    if &shell =~# 'csh'
      silent! execute '%write !('.basecmd.' > '.temp.') >& '.error
    else
      silent! execute '%write !'.basecmd.' > '.temp.' 2> '.error
    endif
    try
      if v:shell_error
        call s:throw(join(readfile(error),"\n"))
      endif
      if a:count > 0
        let edit = s:Mods(a:mods) . get(['edit', 'split', 'pedit'], a:count - (a:line1 ? a:line1 : 1), 'split')
        return s:BlameCommit(edit, get(readfile(temp), 0, ''))
      else
        for winnr in range(winnr('$'),1,-1)
          call setwinvar(winnr, '&scrollbind', 0)
          if exists('+cursorbind')
            call setwinvar(winnr, '&cursorbind', 0)
          endif
          if getbufvar(winbufnr(winnr), 'fugitive_blamed_bufnr')
            execute winbufnr(winnr).'bdelete'
          endif
        endfor
        let bufnr = bufnr('')
        let restore = 'call setwinvar(bufwinnr('.bufnr.'),"&scrollbind",0)'
        if exists('+cursorbind')
          let restore .= '|call setwinvar(bufwinnr('.bufnr.'),"&cursorbind",0)'
        endif
        if &l:wrap
          let restore .= '|call setwinvar(bufwinnr('.bufnr.'),"&wrap",1)'
        endif
        if &l:foldenable
          let restore .= '|call setwinvar(bufwinnr('.bufnr.'),"&foldenable",1)'
        endif
        setlocal scrollbind nowrap nofoldenable
        if exists('+cursorbind')
          setlocal cursorbind
        endif
        let top = line('w0') + &scrolloff
        let current = line('.')
        let temp = s:Resolve(temp)
        let s:temp_files[s:cpath(temp)] = { 'dir': s:Dir(), 'filetype': 'fugitiveblame', 'args': cmd, 'bufnr': bufnr }
        exe 'keepalt' (a:bang ? 'split' : 'leftabove vsplit') s:fnameescape(temp)
        let b:fugitive_blamed_bufnr = bufnr
        let b:fugitive_type = 'blame'
        let w:fugitive_leave = restore
        let b:fugitive_blame_arguments = join(a:args,' ')
        execute top
        normal! zt
        execute current
        if exists('+cursorbind')
          setlocal cursorbind
        endif
        setlocal nomodified nomodifiable nonumber scrollbind nowrap foldcolumn=0 nofoldenable winfixwidth filetype=fugitiveblame buftype=nowrite
        if exists('+concealcursor')
          setlocal concealcursor=nc conceallevel=2
        endif
        if exists('+relativenumber')
          setlocal norelativenumber
        endif
        execute "vertical resize ".(s:linechars('.\{-\}\ze\s\+\d\+)')+1)
        let nowait = v:version >= 704 ? '<nowait>' : ''
        nnoremap <buffer> <silent> <F1> :help fugitive-:Gblame<CR>
        nnoremap <buffer> <silent> g?   :help fugitive-:Gblame<CR>
        if empty(mapcheck('q', 'n'))
          nnoremap <buffer> <silent> q    :exe substitute(bufwinnr(b:fugitive_blamed_bufnr).' wincmd w<Bar>'.bufnr('').'bdelete','^-1','','')<CR>
        endif
        exe 'nnoremap <buffer> <silent>' s:nowait "gq :exe substitute(bufwinnr(b:fugitive_blamed_bufnr).' wincmd w<Bar>'.bufnr('').'bdelete<Bar>if expand(''%:p'') =~# ''^fugitive:[\\/][\\/]''<Bar>Gedit<Bar>endif','^-1','','')<CR>"
        nnoremap <buffer> <silent> <CR> :<C-U>exe <SID>BlameCommit("exe 'norm gq'<Bar>edit")<CR>
        nnoremap <buffer> <silent> -    :<C-U>exe <SID>BlameJump('')<CR>
        nnoremap <buffer> <silent> P    :<C-U>exe <SID>BlameJump('^'.v:count1)<CR>
        nnoremap <buffer> <silent> ~    :<C-U>exe <SID>BlameJump('~'.v:count1)<CR>
        nnoremap <buffer> <silent> i    :<C-U>exe <SID>BlameCommit("exe 'norm q'<Bar>edit")<CR>
        nnoremap <buffer> <silent> o    :<C-U>exe <SID>BlameCommit((&splitbelow ? "botright" : "topleft")." split")<CR>
        nnoremap <buffer> <silent> O    :<C-U>exe <SID>BlameCommit("tabedit")<CR>
        nnoremap <buffer> <silent> p    :<C-U>exe <SID>Open((&splitbelow ? "botright" : "topleft").' pedit', 0, '', matchstr(getline('.'), '\x\+'), [matchstr(getline('.'), '\x\+')])<CR>
        nnoremap <buffer> <silent> A    :<C-u>exe "vertical resize ".(<SID>linechars('.\{-\}\ze [0-9:/+-][0-9:/+ -]* \d\+)')+1+v:count)<CR>
        nnoremap <buffer> <silent> C    :<C-u>exe "vertical resize ".(<SID>linechars('^\S\+')+1+v:count)<CR>
        nnoremap <buffer> <silent> D    :<C-u>exe "vertical resize ".(<SID>linechars('.\{-\}\ze\d\ze\s\+\d\+)')+1-v:count)<CR>
        redraw
        syncbind
      endif
    endtry
    return ''
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
endfunction

function! s:BlameCommit(cmd, ...) abort
  let line = a:0 ? a:1 : getline('.')
  if line =~# '^0\{4,\} '
    return 'echoerr ' . string('Not Committed Yet')
  endif
  let cmd = s:Open(a:cmd, 0, '', matchstr(line, '\x\+'), [matchstr(line, '\x\+')])
  if cmd =~# '^echoerr'
    return cmd
  endif
  let lnum = matchstr(line, ' \zs\d\+\ze\s\+[([:digit:]]')
  let path = matchstr(line, '^\^\=\x\+\s\+\zs.\{-\}\ze\s*\d\+ ')
  if path ==# ''
    let path = fugitive#Path(a:0 ? @% : bufname(b:fugitive_blamed_bufnr), '')
  endif
  execute cmd
  if a:cmd ==# 'pedit'
    return ''
  endif
  if search('^diff .* b/\M'.escape(path,'\').'$','W')
    call search('^+++')
    let head = line('.')
    while search('^@@ \|^diff ') && getline('.') =~# '^@@ '
      let top = +matchstr(getline('.'),' +\zs\d\+')
      let len = +matchstr(getline('.'),' +\d\+,\zs\d\+')
      if lnum >= top && lnum <= top + len
        let offset = lnum - top
        if &scrolloff
          +
          normal! zt
        else
          normal! zt
          +
        endif
        while offset > 0 && line('.') < line('$')
          +
          if getline('.') =~# '^[ +]'
            let offset -= 1
          endif
        endwhile
        return 'normal! zv'
      endif
    endwhile
    execute head
    normal! zt
  endif
  return ''
endfunction

function! s:BlameJump(suffix) abort
  let commit = matchstr(getline('.'),'^\^\=\zs\x\+')
  let suffix = a:suffix
  if commit =~# '^0\+$'
    let commit = 'HEAD'
    let suffix = ''
  endif
  let lnum = matchstr(getline('.'),' \zs\d\+\ze\s\+[([:digit:]]')
  let path = matchstr(getline('.'),'^\^\=\x\+\s\+\zs.\{-\}\ze\s*\d\+ ')
  if path ==# ''
    let path = fugitive#Path(bufname(b:fugitive_blamed_bufnr), '')
  endif
  let args = b:fugitive_blame_arguments
  let offset = line('.') - line('w0')
  let bufnr = bufnr('%')
  let winnr = bufwinnr(b:fugitive_blamed_bufnr)
  if winnr > 0
    exe winnr.'wincmd w'
  endif
  execute 'Gedit' s:fnameescape(commit . suffix . ':' . path)
  execute lnum
  if winnr > 0
    exe bufnr.'bdelete'
  endif
  if exists(':Gblame')
    execute 'Gblame '.args
    execute lnum
    let delta = line('.') - line('w0') - offset
    if delta > 0
      execute 'normal! '.delta."\<C-E>"
    elseif delta < 0
      execute 'normal! '.(-delta)."\<C-Y>"
    endif
    syncbind
  endif
  return ''
endfunction

let s:hash_colors = {}

function! fugitive#BlameSyntax() abort
  let conceal = has('conceal') ? ' conceal' : ''
  syn match FugitiveblameBoundary "^\^"
  syn match FugitiveblameBlank                      "^\s\+\s\@=" nextgroup=FugitiveblameAnnotation,fugitiveblameOriginalFile,FugitiveblameOriginalLineNumber skipwhite
  syn match FugitiveblameHash       "\%(^\^\=\)\@<=\<\x\{7,\}\>" nextgroup=FugitiveblameAnnotation,FugitiveblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite
  syn match FugitiveblameUncommitted "\%(^\^\=\)\@<=\<0\{7,\}\>" nextgroup=FugitiveblameAnnotation,FugitiveblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite
  syn region FugitiveblameAnnotation matchgroup=FugitiveblameDelimiter start="(" end="\%( \d\+\)\@<=)" contained keepend oneline
  syn match FugitiveblameTime "[0-9:/+-][0-9:/+ -]*[0-9:/+-]\%( \+\d\+)\)\@=" contained containedin=FugitiveblameAnnotation
  exec 'syn match FugitiveblameLineNumber         " *\d\+)\@=" contained containedin=FugitiveblameAnnotation' conceal
  exec 'syn match FugitiveblameOriginalFile       " \%(\f\+\D\@<=\|\D\@=\f\+\)\%(\%(\s\+\d\+\)\=\s\%((\|\s*\d\+)\)\)\@=" contained nextgroup=FugitiveblameOriginalLineNumber,FugitiveblameAnnotation skipwhite' conceal
  exec 'syn match FugitiveblameOriginalLineNumber " *\d\+\%(\s(\)\@=" contained nextgroup=FugitiveblameAnnotation skipwhite' conceal
  exec 'syn match FugitiveblameOriginalLineNumber " *\d\+\%(\s\+\d\+)\)\@=" contained nextgroup=FugitiveblameShort skipwhite' conceal
  syn match FugitiveblameShort              " \d\+)" contained contains=FugitiveblameLineNumber
  syn match FugitiveblameNotCommittedYet "(\@<=Not Committed Yet\>" contained containedin=FugitiveblameAnnotation
  hi def link FugitiveblameBoundary           Keyword
  hi def link FugitiveblameHash               Identifier
  hi def link FugitiveblameUncommitted        Ignore
  hi def link FugitiveblameTime               PreProc
  hi def link FugitiveblameLineNumber         Number
  hi def link FugitiveblameOriginalFile       String
  hi def link FugitiveblameOriginalLineNumber Float
  hi def link FugitiveblameShort              FugitiveblameDelimiter
  hi def link FugitiveblameDelimiter          Delimiter
  hi def link FugitiveblameNotCommittedYet    Comment
  if !get(g:, 'fugitive_dynamic_colors', 1)
    return
  endif
  let seen = {}
  for lnum in range(1, line('$'))
    let hash = matchstr(getline(lnum), '^\^\=\zs\x\{6\}')
    if hash ==# '' || hash ==# '000000' || has_key(seen, hash)
      continue
    endif
    let seen[hash] = 1
    if &t_Co > 16 && get(g:, 'CSApprox_loaded') && !empty(findfile('autoload/csapprox/per_component.vim', escape(&rtp, ' ')))
          \ && empty(get(s:hash_colors, hash))
      let [s, r, g, b; __] = map(matchlist(hash, '\(\x\x\)\(\x\x\)\(\x\x\)'), 'str2nr(v:val,16)')
      let color = csapprox#per_component#Approximate(r, g, b)
      if color == 16 && &background ==# 'dark'
        let color = 8
      endif
      let s:hash_colors[hash] = ' ctermfg='.color
    else
      let s:hash_colors[hash] = ''
    endif
    exe 'syn match FugitiveblameHash'.hash.'       "\%(^\^\=\)\@<='.hash.'\x\{1,34\}\>" nextgroup=FugitiveblameAnnotation,FugitiveblameOriginalLineNumber,fugitiveblameOriginalFile skipwhite'
  endfor
  call s:RehighlightBlame()
endfunction

function! s:RehighlightBlame() abort
  for [hash, cterm] in items(s:hash_colors)
    if !empty(cterm) || has('gui_running') || has('termguicolors') && &termguicolors
      exe 'hi FugitiveblameHash'.hash.' guifg=#'.hash.get(s:hash_colors, hash, '')
    else
      exe 'hi link FugitiveblameHash'.hash.' Identifier'
    endif
  endfor
endfunction

" Section: :Gbrowse

call s:command("-bar -bang -range=0 -nargs=* -complete=customlist,fugitive#CompleteObject Gbrowse", "Browse")

let s:redirects = {}

function! s:BrowseCommand(line1, line2, range, count, bang, mods, reg, arg, args) abort
  let dir = s:Dir()
  try
    let validremote = '\.\|\.\=/.*\|[[:alnum:]_-]\+\%(://.\{-\}\)\='
    if len(a:args)
      let remote = matchstr(join(a:args, ' '),'@\zs\%('.validremote.'\)$')
      let rev = substitute(join(a:args, ' '),'@\%('.validremote.'\)$','','')
    else
      let remote = ''
      let rev = ''
    endif
    if rev ==# ''
      let rev = s:DirRev(@%)[1]
    endif
    if rev =~# '^:\=$'
      let expanded = s:Relative()
    else
      let expanded = s:Expand(rev)
    endif
    let cdir = fugitive#CommonDir(s:Dir())
    for subdir in ['tags/', 'heads/', 'remotes/']
      if expanded !~# '^[./]' && filereadable(cdir . '/refs/' . subdir . expanded)
        let expanded = '.git/refs/' . subdir . expanded
      endif
    endfor
    let full = s:Generate(expanded)
    let commit = ''
    if full =~? '^fugitive:'
      let [pathdir, commit, path] = s:DirCommitFile(full)
      if commit =~# '^:\=\d$'
        let commit = ''
      endif
      if commit =~ '..'
        let type = s:TreeChomp('cat-file','-t',commit.s:sub(path,'^/',':'))
        let branch = matchstr(expanded, '^[^:]*')
      else
        let type = 'blob'
      endif
      let path = path[1:-1]
    elseif empty(s:Tree(dir))
      let path = '.git/' . full[strlen(dir)+1:-1]
      let type = ''
    else
      let path = full[strlen(s:Tree(dir))+1:-1]
      if path =~# '^\.git/'
        let type = ''
      elseif isdirectory(full)
        let type = 'tree'
      else
        let type = 'blob'
      endif
    endif
    if type ==# 'tree' && !empty(path)
      let path = s:sub(path, '/\=$', '/')
    endif
    if path =~# '^\.git/.*HEAD$' && filereadable(dir . '/' . path[5:-1])
      let body = readfile(dir . '/' . path[5:-1])[0]
      if body =~# '^\x\{40,\}$'
        let commit = body
        let type = 'commit'
        let path = ''
      elseif body =~# '^ref: refs/'
        let path = '.git/' . matchstr(body,'ref: \zs.*')
      endif
    endif

    let merge = ''
    if path =~# '^\.git/refs/remotes/.'
      if empty(remote)
        let remote = matchstr(path, '^\.git/refs/remotes/\zs[^/]\+')
        let branch = matchstr(path, '^\.git/refs/remotes/[^/]\+/\zs.\+')
      else
        let merge = matchstr(path, '^\.git/refs/remotes/[^/]\+/\zs.\+')
        let path = '.git/refs/heads/'.merge
      endif
    elseif path =~# '^\.git/refs/heads/.'
      let branch = path[16:-1]
    elseif !exists('branch')
      let branch = FugitiveHead()
    endif
    if !empty(branch)
      let r = fugitive#Config('branch.'.branch.'.remote')
      let m = fugitive#Config('branch.'.branch.'.merge')[11:-1]
      if r ==# '.' && !empty(m)
        let r2 = fugitive#Config('branch.'.m.'.remote')
        if r2 !~# '^\.\=$'
          let r = r2
          let m = fugitive#Config('branch.'.m.'.merge')[11:-1]
        endif
      endif
      if empty(remote)
        let remote = r
      endif
      if r ==# '.' || r ==# remote
        let merge = m
        if path =~# '^\.git/refs/heads/.'
          let path = '.git/refs/heads/'.merge
        endif
      endif
    endif

    let line1 = a:count > 0 ? a:line1 : 0
    let line2 = a:count > 0 ? a:count : 0
    if empty(commit) && path !~# '^\.git/'
      if a:line1 && !a:count && !empty(merge)
        let commit = merge
      else
        let commit = ''
        if len(merge)
          let owner = s:Owner(@%)
          let [commit, exec_error] = s:ChompError(['merge-base', 'refs/remotes/' . remote . '/' . merge, empty(owner) ? 'HEAD' : owner, '--'])
          if exec_error
            let commit = ''
          endif
          if a:count && empty(a:args) && commit =~# '^\x\{40,\}$'
            let blame_list = tempname()
            call writefile([commit, ''], blame_list, 'b')
            let blame_in = tempname()
            silent exe '%write' blame_in
            let [blame, exec_error] = s:LinesError(['blame', '--contents', blame_in, '-L', a:line1.','.a:count, '-S', blame_list, '-s', '--show-number', './' . path])
            if !exec_error
              let blame_regex = '^\^\x\+\s\+\zs\d\+\ze\s'
              if get(blame, 0) =~# blame_regex && get(blame, -1) =~# blame_regex
                let line1 = +matchstr(blame[0], blame_regex)
                let line2 = +matchstr(blame[-1], blame_regex)
              else
                call s:throw("Can't browse to uncommitted change")
              endif
            endif
          endif
        endif
      endif
      if empty(commit)
        let commit = readfile(fugitive#Find('.git/HEAD', dir), '', 1)[0]
      endif
      let i = 0
      while commit =~# '^ref: ' && i < 10
        let commit = readfile(cdir . '/' . commit[5:-1], '', 1)[0]
        let i -= 1
      endwhile
    endif

    if empty(remote)
      let remote = '.'
    endif
    let raw = fugitive#RemoteUrl(remote)
    if empty(raw)
      let raw = remote
    endif

    if raw =~# '^https\=://' && s:executable('curl')
      if !has_key(s:redirects, raw)
        let s:redirects[raw] = matchstr(system('curl -I ' .
              \ s:shellesc(raw . '/info/refs?service=git-upload-pack')),
              \ 'Location: \zs\S\+\ze/info/refs?')
      endif
      if len(s:redirects[raw])
        let raw = s:redirects[raw]
      endif
    endif

    let opts = {
          \ 'dir': dir,
          \ 'repo': fugitive#repo(dir),
          \ 'remote': raw,
          \ 'revision': 'No longer provided',
          \ 'commit': commit,
          \ 'path': path,
          \ 'type': type,
          \ 'line1': line1,
          \ 'line2': line2}

    let url = ''
    for Handler in get(g:, 'fugitive_browse_handlers', [])
      let url = call(Handler, [copy(opts)])
      if !empty(url)
        break
      endif
    endfor

    if empty(url)
      call s:throw("No Gbrowse handler installed for '".raw."'")
    endif

    let url = s:gsub(url, '[ <>]', '\="%".printf("%02X",char2nr(submatch(0)))')
    if a:bang
      if has('clipboard')
        let @+ = url
      endif
      return 'echomsg '.string(url)
    elseif exists(':Browse') == 2
      return 'echomsg '.string(url).'|Browse '.url
    else
      if !exists('g:loaded_netrw')
        runtime! autoload/netrw.vim
      endif
      if exists('*netrw#BrowseX')
        return 'echomsg '.string(url).'|call netrw#BrowseX('.string(url).', 0)'
      else
        return 'echomsg '.string(url).'|call netrw#NetrwBrowseX('.string(url).', 0)'
      endif
    endif
  catch /^fugitive: Use '!:%' instead of '-'/
    if a:count >= 0
      return 'echoerr ' . string('fugitive: ''-'' no longer required to get persistent URL')
    else
      return 'echoerr ' . string('fugitive: use :0Gbrowse instead of :Gbrowse -')
    endif
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
endfunction

" Section: Go to file

nnoremap <SID>: :<C-U><C-R>=v:count ? v:count : ''<CR>
function! fugitive#MapCfile(...) abort
  exe 'cnoremap <buffer> <expr> <Plug><cfile>' (a:0 ? a:1 : 'fugitive#Cfile()')
  let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe') . '|sil! exe "cunmap <buffer> <Plug><cfile>"'
  if !exists('g:fugitive_no_maps')
    call s:map('n', 'gf',          '<SID>:find <Plug><cfile><CR>', '<silent><unique>', 1)
    call s:map('n', '<C-W>f',     '<SID>:sfind <Plug><cfile><CR>', '<silent><unique>', 1)
    call s:map('n', '<C-W><C-F>', '<SID>:sfind <Plug><cfile><CR>', '<silent><unique>', 1)
    call s:map('n', '<C-W>gf',  '<SID>:tabfind <Plug><cfile><CR>', '<silent><unique>', 1)
    call s:map('c', '<C-R><C-F>', '<Plug><cfile>', '<silent><unique>', 1)
  endif
endfunction

function! s:ContainingCommit() abort
  let commit = s:Owner(@%)
  return empty(commit) ? 'HEAD' : commit
endfunction

function! s:SquashArgument(...) abort
  if &filetype == 'fugitive'
    let commit = matchstr(getline('.'), '^\%(\%(\x\x\x\)\@!\l\+\s\+\)\=\zs[0-9a-f]\{4,\}\ze ')
  else
    let commit = s:Owner(@%)
  endif
  return len(commit) && a:0 ? printf(a:1, commit) : commit
endfunction

function! s:RebaseArgument() abort
  return s:SquashArgument(' %s^')
endfunction

function! s:NavigateUp(count) abort
  let rev = substitute(s:DirRev(@%)[1], '^$', ':', 'g')
  let c = a:count
  while c
    if rev =~# ':.*/.'
      let rev = matchstr(rev, '.*\ze/.\+', '')
    elseif rev =~# '.:.'
      let rev = matchstr(rev, '^.[^:]*:')
    elseif rev =~# '^:'
      let rev = 'HEAD^{}'
    elseif rev =~# ':$'
      let rev = rev[0:-2]
    else
      return rev.'~'.c
    endif
    let c -= 1
  endwhile
  return rev
endfunction

function! fugitive#MapJumps(...) abort
  if !&modifiable
    if get(b:, 'fugitive_type', '') ==# 'blob'
      nnoremap <buffer> <silent> <CR>  :<C-U>0,1Gblame<CR>
      nnoremap <buffer> <silent> o     :<C-U>0,2Gblame<CR>
      nnoremap <buffer> <silent> S     :<C-U>echoerr 'Use gO'<CR>
      nnoremap <buffer> <silent> gO    :<C-U>vertical 0,2Gblame<CR>
      nnoremap <buffer> <silent> O     :<C-U>tab 0,2Gblame<CR>
      nnoremap <buffer> <silent> p     :<C-U>0,3Gblame<CR>
    else
      nnoremap <buffer> <silent> <CR>  :<C-U>exe <SID>GF("edit")<CR>
      nnoremap <buffer> <silent> o     :<C-U>exe <SID>GF("split")<CR>
      nnoremap <buffer> <silent> S     :<C-U>echoerr 'Use gO'<CR>
      nnoremap <buffer> <silent> gO    :<C-U>exe <SID>GF("vsplit")<CR>
      nnoremap <buffer> <silent> O     :<C-U>exe <SID>GF("tabedit")<CR>
      nnoremap <buffer> <silent> p     :<C-U>exe <SID>GF("pedit")<CR>

      if exists(':CtrlP') && get(g:, 'ctrl_p_map') =~? '^<c-p>$'
        nnoremap <buffer> <silent> <C-P> :<C-U>execute line('.') == 1 ? 'CtrlP ' . fnameescape(<SID>Tree()) : <SID>PreviousFileHunk(v:count1)<CR>
      else
        nnoremap <buffer> <silent> <C-P> :<C-U>execute <SID>PreviousFileHunk(v:count1)<CR>
      endif
      nnoremap <buffer> <silent> <C-N> :<C-U>execute <SID>NextFileHunk(v:count1)<CR>
      nnoremap <buffer> <silent> (  :<C-U>execute <SID>PreviousFileHunk(v:count1)<CR>
      nnoremap <buffer> <silent> )  :<C-U>execute <SID>NextFileHunk(v:count1)<CR>
      nnoremap <buffer> <silent> K  :<C-U>execute <SID>PreviousFileHunk(v:count1)<CR>
      nnoremap <buffer> <silent> J  :<C-U>execute <SID>NextFileHunk(v:count1)<CR>
    endif
    exe "nnoremap <buffer> <silent>" s:nowait  "-     :<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>NavigateUp(v:count1))<Bar> if getline(1) =~# '^tree \x\{40,\}$' && empty(getline(2))<Bar>call search('^'.escape(expand('#:t'),'.*[]~\').'/\=$','wc')<Bar>endif<CR>"
    nnoremap <buffer> <silent> P     :<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>ContainingCommit().'^'.v:count1.<SID>Relative(':'))<CR>
    nnoremap <buffer> <silent> ~     :<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>ContainingCommit().'~'.v:count1.<SID>Relative(':'))<CR>
    nnoremap <buffer> <silent> C     :<C-U>exe 'Gedit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>

    nnoremap <buffer>          c-    :Gcommit -
    nnoremap <buffer>       c<Space> :Gcommit<Space>
    nnoremap <buffer>          c<CR> :Gcommit<CR>
    nnoremap <buffer> <silent> co    :<C-U>echoerr 'Use CTRL-W C'<CR>
    nnoremap <buffer> <silent> <C-W>C :<C-U>exe 'Gsplit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>
    nnoremap <buffer> <silent> cp    :<C-U>echoerr 'Use gC'<CR>
    nnoremap <buffer> <silent> gC    :<C-U>exe 'Gpedit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>
    nnoremap <buffer> <silent> gc    :<C-U>exe 'Gpedit ' . <SID>fnameescape(<SID>ContainingCommit())<CR>
    nnoremap <buffer> <silent> ca    :<C-U>Gcommit --amend<CR>
    nnoremap <buffer> <silent> cc    :<C-U>Gcommit<CR>
    nnoremap <buffer> <silent> ce    :<C-U>Gcommit --amend --no-edit<CR>
    nnoremap <buffer> <silent> cw    :<C-U>Gcommit --amend --only<CR>
    nnoremap <buffer> <silent> cva   :<C-U>Gcommit -v --amend<CR>
    nnoremap <buffer> <silent> cvc   :<C-U>Gcommit -v<CR>
    nnoremap <buffer>          cf    :<C-U>Gcommit --fixup=<C-R>=<SID>SquashArgument()<CR>
    nnoremap <buffer>          cF    :<C-U><Bar>Grebase --autosquash<C-R>=<SID>RebaseArgument()<CR><Home>Gcommit --fixup=<C-R>=<SID>SquashArgument()<CR>
    nnoremap <buffer>          cs    :<C-U>Gcommit --squash=<C-R>=<SID>SquashArgument()<CR>
    nnoremap <buffer>          cS    :<C-U><Bar>Grebase --autosquash<C-R>=<SID>RebaseArgument()<CR><Home>Gcommit --squash=<C-R>=<SID>SquashArgument()<CR>
    nnoremap <buffer>          cA    :<C-U>Gcommit --edit --squash=<C-R>=<SID>SquashArgument()<CR>
    nnoremap <buffer>          r-    :Grebase -
    nnoremap <buffer>       r<Space> :Grebase<Space>
    nnoremap <buffer>          r<CR> :Grebase<CR>
    nnoremap <buffer> <silent> ri    :<C-U>Grebase --interactive<C-R>=<SID>RebaseArgument()<CR><CR>
    nnoremap <buffer> <silent> rf    :<C-U>Grebase --autosquash<C-R>=<SID>RebaseArgument()<CR><CR>
    nnoremap <buffer> <silent> ru    :<C-U>Grebase --interactive @{upstream}<CR>
    nnoremap <buffer> <silent> rp    :<C-U>Grebase --interactive @{push}<CR>
    nnoremap <buffer> <silent> rw    :<C-U>Grebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/reword/e<CR>
    nnoremap <buffer> <silent> rm    :<C-U>Grebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/edit/e<CR>
    nnoremap <buffer> <silent> rd    :<C-U>Grebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/drop/e<CR>
    nnoremap <buffer> <silent> rk    :<C-U>Grebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/drop/e<CR>
    nnoremap <buffer> <silent> rx    :<C-U>Grebase --interactive<C-R>=<SID>RebaseArgument()<CR><Bar>s/^pick/drop/e<CR>
    nnoremap <buffer> <silent> rr    :<C-U>Grebase --continue<CR>
    nnoremap <buffer> <silent> rs    :<C-U>Grebase --skip<CR>
    nnoremap <buffer> <silent> re    :<C-U>Grebase --edit-todo<CR>
    nnoremap <buffer> <silent> ra    :<C-U>Grebase --abort<CR>
    nnoremap <buffer>          .     :<C-U> <C-R>=<SID>fnameescape(fugitive#Real(@%))<CR><Home>
    xnoremap <buffer>          .     :<C-U> <C-R>=<SID>fnameescape(fugitive#Real(@%))<CR><Home>
    nnoremap <buffer> <silent> g?   :help fugitive-mappings<CR>
  endif
endfunction

function! s:StatusCfile(...) abort
  let tree = s:Tree()
  let lead = s:cpath(tree, getcwd()) ? './' : tree . '/'
  let info = s:StageInfo()
  let line = getline('.')
  if len(info.sigil) && len(info.section) && len(info.paths)
    if info.section ==# 'Unstaged' && info.sigil !=# '-'
      return [lead . info.relative[0], info.offset, 'normal!zv']
    elseif info.section ==# 'Staged' && info.sigil ==# '-'
      return ['@:' . info.relative[0], info.offset, 'normal!zv']
    else
      return [':0:' . info.relative[0], info.offset, 'normal!zv']
    endif
  elseif len(info.paths)
    return [lead . info.relative[0]]
  elseif len(info.commit)
    return [info.commit]
  elseif line =~# '^\%(Head\|Merge\|Rebase\|Upstream\|Pull\|Push\): '
    return [matchstr(line, ' \zs.*')]
  else
    return ['']
  endif
endfunction

function! fugitive#StatusCfile() abort
  let file = s:Generate(s:StatusCfile()[0])
  return empty(file) ? fugitive#Cfile() : s:fnameescape(file)
endfunction

function! s:MessageCfile(...) abort
  let tree = s:Tree()
  let lead = s:cpath(tree, getcwd()) ? './' : tree . '/'
  if getline('.') =~# '^.\=\trenamed:.* -> '
    return lead . matchstr(getline('.'),' -> \zs.*')
  elseif getline('.') =~# '^.\=\t\(\k\| \)\+\p\?: *.'
    return lead . matchstr(getline('.'),': *\zs.\{-\}\ze\%( ([^()[:digit:]]\+)\)\=$')
  elseif getline('.') =~# '^.\=\t.'
    return lead . matchstr(getline('.'),'\t\zs.*')
  elseif getline('.') =~# ': needs merge$'
    return lead . matchstr(getline('.'),'.*\ze: needs merge$')
  elseif getline('.') =~# '^\%(. \)\=Not currently on any branch.$'
    return 'HEAD'
  elseif getline('.') =~# '^\%(. \)\=On branch '
    return 'refs/heads/'.getline('.')[12:]
  elseif getline('.') =~# "^\\%(. \\)\=Your branch .*'"
    return matchstr(getline('.'),"'\\zs\\S\\+\\ze'")
  else
    return ''
  endif
endfunction

function! fugitive#MessageCfile() abort
  let file = s:Generate(s:MessageCfile())
  return empty(file) ? fugitive#Cfile() : s:fnameescape(file)
endfunction

function! s:cfile() abort
  try
    let myhash = s:DirRev(@%)[1]
    if len(myhash)
      try
        let myhash = fugitive#RevParse(myhash)
      catch /^fugitive:/
        let myhash = ''
      endtry
    endif
    if empty(myhash) && getline(1) =~# '^\%(commit\|tag\) \w'
      let myhash = matchstr(getline(1),'^\w\+ \zs\S\+')
    endif

    let showtree = (getline(1) =~# '^tree ' && getline(2) == "")

    let treebase = substitute(s:DirCommitFile(@%)[1], '^\d$', ':&', '') . ':' .
          \ s:Relative('') . (s:Relative('') =~# '^$\|/$' ? '' : '/')

    if getline('.') =~# '^\d\{6\} \l\{3,8\} \x\{40,\}\t'
      return [treebase . s:sub(matchstr(getline('.'),'\t\zs.*'),'/$','')]
    elseif showtree
      return [treebase . s:sub(getline('.'),'/$','')]

    else

      let dcmds = []

      " Index
      if getline('.') =~# '^\d\{6\} \x\{40,\} \d\t'
        let ref = matchstr(getline('.'),'\x\{40,\}')
        let file = ':'.s:sub(matchstr(getline('.'),'\d\t.*'),'\t',':')
        return [file]
      endif

      if getline('.') =~# '^ref: '
        let ref = strpart(getline('.'),5)

      elseif getline('.') =~# '^commit \x\{40,\}\>'
        let ref = matchstr(getline('.'),'\x\{40,\}')
        return [ref]

      elseif getline('.') =~# '^parent \x\{40,\}\>'
        let ref = matchstr(getline('.'),'\x\{40,\}')
        let line = line('.')
        let parent = 0
        while getline(line) =~# '^parent '
          let parent += 1
          let line -= 1
        endwhile
        return [ref]

      elseif getline('.') =~# '^tree \x\{40,\}$'
        let ref = matchstr(getline('.'),'\x\{40,\}')
        if len(myhash) && fugitive#RevParse(myhash.':') ==# ref
          let ref = myhash.':'
        endif
        return [ref]

      elseif getline('.') =~# '^object \x\{40,\}$' && getline(line('.')+1) =~ '^type \%(commit\|tree\|blob\)$'
        let ref = matchstr(getline('.'),'\x\{40,\}')
        let type = matchstr(getline(line('.')+1),'type \zs.*')

      elseif getline('.') =~# '^\l\{3,8\} '.myhash.'$'
        let ref = s:DirRev(@%)[1]

      elseif getline('.') =~# '^\l\{3,8\} \x\{40,\}\>'
        let ref = matchstr(getline('.'),'\x\{40,\}')
        echoerr "warning: unknown context ".matchstr(getline('.'),'^\l*')

      elseif getline('.') =~# '^[+-]\{3\} [abciow12]\=/'
        let ref = getline('.')[4:]

      elseif getline('.') =~# '^[+-]' && search('^@@ -\d\+\%(,\d\+\)\= +\d\+','bnW')
        let type = getline('.')[0]
        let lnum = line('.') - 1
        let offset = 0
        while getline(lnum) !~# '^@@ -\d\+\%(,\d\+\)\= +\d\+'
          if getline(lnum) =~# '^[ '.type.']'
            let offset += 1
          endif
          let lnum -= 1
        endwhile
        let offset += matchstr(getline(lnum), type.'\zs\d\+')
        let ref = getline(search('^'.type.'\{3\} [abciow12]/','bnW'))[4:-1]
        let dcmds = [offset, 'normal!zv']

      elseif getline('.') =~# '^rename from '
        let ref = 'a/'.getline('.')[12:]
      elseif getline('.') =~# '^rename to '
        let ref = 'b/'.getline('.')[10:]

      elseif getline('.') =~# '^@@ -\d\+\%(,\d\+\)\= +\d\+'
        let diff = getline(search('^diff --git \%([abciow12]/.*\|/dev/null\) \%([abciow12]/.*\|/dev/null\)', 'bcnW'))
        let offset = matchstr(getline('.'), '+\zs\d\+')

        let dref = matchstr(diff, '\Cdiff --git \zs\%([abciow12]/.*\|/dev/null\)\ze \%([abciow12]/.*\|/dev/null\)')
        let ref = matchstr(diff, '\Cdiff --git \%([abciow12]/.*\|/dev/null\) \zs\%([abciow12]/.*\|/dev/null\)')
        let dcmd = 'Gdiffsplit! +'.offset

      elseif getline('.') =~# '^diff --git \%([abciow12]/.*\|/dev/null\) \%([abciow12]/.*\|/dev/null\)'
        let dref = matchstr(getline('.'),'\Cdiff --git \zs\%([abciow12]/.*\|/dev/null\)\ze \%([abciow12]/.*\|/dev/null\)')
        let ref = matchstr(getline('.'),'\Cdiff --git \%([abciow12]/.*\|/dev/null\) \zs\%([abciow12]/.*\|/dev/null\)')
        let dcmd = 'Gdiffsplit!'

      elseif getline('.') =~# '^index ' && getline(line('.')-1) =~# '^diff --git \%([abciow12]/.*\|/dev/null\) \%([abciow12]/.*\|/dev/null\)'
        let line = getline(line('.')-1)
        let dref = matchstr(line,'\Cdiff --git \zs\%([abciow12]/.*\|/dev/null\)\ze \%([abciow12]/.*\|/dev/null\)')
        let ref = matchstr(line,'\Cdiff --git \%([abciow12]/.*\|/dev/null\) \zs\%([abciow12]/.*\|/dev/null\)')
        let dcmd = 'Gdiffsplit!'

      elseif line('$') == 1 && getline('.') =~ '^\x\{40,\}$'
        let ref = getline('.')

      elseif expand('<cword>') =~# '^\x\{7,\}\>'
        return [expand('<cword>')]

      else
        let ref = ''
      endif

      let prefixes = {
            \ '1': '',
            \ '2': '',
            \ 'b': ':0:',
            \ 'i': ':0:',
            \ 'o': '',
            \ 'w': ''}

      if len(myhash)
        let prefixes.a = myhash.'^:'
        let prefixes.b = myhash.':'
      endif
      let ref = substitute(ref, '^\(\w\)/', '\=get(prefixes, submatch(1), "HEAD:")', '')
      if exists('dref')
        let dref = substitute(dref, '^\(\w\)/', '\=get(prefixes, submatch(1), "HEAD:")', '')
      endif

      if ref ==# '/dev/null'
        " Empty blob
        let ref = 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391'
      endif

      if exists('dref')
        return [ref, dcmd . ' ' . s:fnameescape(dref)] + dcmds
      elseif ref != ""
        return [ref] + dcmds
      endif

    endif
    return []
  endtry
endfunction

function! s:GF(mode) abort
  try
    let results = &filetype ==# 'fugitive' ? s:StatusCfile() : &filetype ==# 'gitcommit' ? [s:MessageCfile()] : s:cfile()
  catch /^fugitive:/
    return 'echoerr ' . string(v:exception)
  endtry
  if len(results) > 1
    return 'G' . a:mode .
          \ ' +' . escape(join(results[1:-1], '|'), '| ') . ' ' .
          \ s:fnameescape(results[0])
  elseif len(results) && len(results[0])
    return 'G' . a:mode . ' ' . s:fnameescape(results[0])
  else
    return ''
  endif
endfunction

function! fugitive#Cfile() abort
  let pre = ''
  let results = s:cfile()
  if empty(results)
    let cfile = expand('<cfile>')
    if &includeexpr =~# '\<v:fname\>'
      sandbox let cfile = eval(substitute(&includeexpr, '\C\<v:fname\>', '\=string(cfile)', 'g'))
    endif
    return cfile
  elseif len(results) > 1
    let pre = '+' . join(map(results[1:-1], 'escape(v:val, " ")'), '\|') . ' '
  endif
  return pre . s:fnameescape(s:Generate(results[0]))
endfunction

" Section: Statusline

function! fugitive#Statusline(...) abort
  if empty(s:Dir())
    return ''
  endif
  let status = ''
  let commit = s:DirCommitFile(@%)[1]
  if len(commit)
    let status .= ':' . commit[0:6]
  endif
  let status .= '('.FugitiveHead(7).')'
  return '[Git'.status.']'
endfunction

function! fugitive#statusline(...) abort
  return fugitive#Statusline()
endfunction

function! fugitive#head(...) abort
  if empty(s:Dir())
    return ''
  endif

  return fugitive#Head(a:0 ? a:1 : 0)
endfunction

" Section: Folding

function! fugitive#Foldtext() abort
  if &foldmethod !=# 'syntax'
    return foldtext()
  endif

  let line_foldstart = getline(v:foldstart)
  if line_foldstart =~# '^diff '
    let [add, remove] = [-1, -1]
    let filename = ''
    for lnum in range(v:foldstart, v:foldend)
      let line = getline(lnum)
      if filename ==# '' && line =~# '^[+-]\{3\} [abciow12]/'
        let filename = line[6:-1]
      endif
      if line =~# '^+'
        let add += 1
      elseif line =~# '^-'
        let remove += 1
      elseif line =~# '^Binary '
        let binary = 1
      endif
    endfor
    if filename ==# ''
      let filename = matchstr(line_foldstart, '^diff .\{-\} [abciow12]/\zs.*\ze [abciow12]/')
    endif
    if filename ==# ''
      let filename = line_foldstart[5:-1]
    endif
    if exists('binary')
      return 'Binary: '.filename
    else
      return (add<10&&remove<100?' ':'') . add . '+ ' . (remove<10&&add<100?' ':'') . remove . '- ' . filename
    endif
  elseif line_foldstart =~# '^# .*:$'
    let lines = getline(v:foldstart, v:foldend)
    call filter(lines, 'v:val =~# "^#\t"')
    cal map(lines, "s:sub(v:val, '^#\t%(modified: +|renamed: +)=', '')")
    cal map(lines, "s:sub(v:val, '^([[:alpha:] ]+): +(.*)', '\\2 (\\1)')")
    return line_foldstart.' '.join(lines, ', ')
  endif
  return foldtext()
endfunction

function! fugitive#foldtext() abort
  return fugitive#Foldtext()
endfunction

augroup fugitive_folding
  autocmd!
  autocmd User Fugitive
        \ if &filetype =~# '^git\%(commit\)\=$' && &foldtext ==# 'foldtext()' |
        \    set foldtext=fugitive#Foldtext() |
        \ endif
augroup END

" Section: Initialization

function! fugitive#Init() abort
  if exists('#User#FugitiveBoot')
    try
      let [save_mls, &modelines] = [&mls, 0]
      doautocmd User FugitiveBoot
    finally
      let &mls = save_mls
    endtry
  endif
  if !exists('g:fugitive_no_maps')
    call s:map('c', '<C-R><C-G>', '<SID>fnameescape(fugitive#Object(@%))', '<expr>')
    call s:map('n', 'y<C-G>', ':<C-U>call setreg(v:register, fugitive#Object(@%))<CR>', '<silent>')
  endif
  if expand('%:p') =~# ':[\/][\/]'
    let &l:path = s:sub(&path, '^\.%(,|$)', '')
  endif
  let dir = s:Dir()
  if stridx(&tags, escape(dir, ', ')) == -1
    let actualdir = fugitive#Find('.git/', dir)
    if filereadable(actualdir . 'tags')
      let &l:tags = escape(actualdir . 'tags', ', ').','.&tags
    endif
    if &filetype !=# '' && filereadable(actualdir . &filetype . '.tags')
      let &l:tags = escape(actualdir . &filetype . '.tags', ', ').','.&tags
    endif
  endif
  try
    let [save_mls, &modelines] = [&mls, 0]
    call s:define_commands()
    doautocmd User Fugitive
  finally
    let &mls = save_mls
  endtry
endfunction

function! fugitive#is_git_dir(path) abort
  return FugitiveIsGitDir(a:path)
endfunction

function! fugitive#extract_git_dir(path) abort
  return FugitiveExtractGitDir(a:path)
endfunction

function! fugitive#detect(path) abort
  return FugitiveDetect(a:path)
endfunction

" Section: End
