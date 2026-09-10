" TetraVim FreeMarker syntax -- HTML base + FreeMarker directives / interpolations
"
" There is no upstream nvim-treesitter grammar and no bundled Vim syntax for
" FreeMarker, so this is a pragmatic hand-rolled layer: load the HTML syntax for
" the markup, then paint <#...>/<@...> directives, ${...}/#{...} interpolations
" and <#-- --> comments on top. Not a full parser -- enough for readable .ftl.

if exists("b:current_syntax")
  finish
endif

runtime! syntax/html.vim
unlet! b:current_syntax

syntax case match

" <#-- ... --> comments win over everything, including directives.
syntax region ftlComment start=+<#--+ end=+-->+ contains=@Spell keepend

" ${ ... } and #{ ... } interpolations.
syntax region ftlInterpolation matchgroup=ftlDelimiter start=+\${+ end=+}+ contains=ftlString,ftlNumber,ftlBuiltin keepend
syntax region ftlInterpolation matchgroup=ftlDelimiter start=+#{+ end=+}+ contains=ftlString,ftlNumber,ftlBuiltin keepend

" <#directive ...> and </#directive> and user <@macro ...> calls.
syntax region ftlDirective matchgroup=ftlDelimiter start=+</\=#\a+ end=+>+
      \ contains=ftlKeyword,ftlString,ftlNumber,ftlBuiltin,ftlOperator keepend
syntax region ftlDirective matchgroup=ftlDelimiter start=+</\=@+ end=+>+
      \ contains=ftlString,ftlNumber,ftlBuiltin,ftlOperator keepend

syntax keyword ftlKeyword contained if elseif else list items sep as assign global
      \ local macro nested return function break continue stop setting import include
      \ visit recurse fallback escape noescape ftl compress switch case default
      \ attempt recover t rt lt nt outputformat autoesc noautoesc

syntax match ftlBuiltin contained +?\a\w*+
syntax match ftlOperator contained +[=!<>]=\|&&\|||\|[-+*/%]+
syntax region ftlString contained start=+"+ skip=+\\"+ end=+"+
syntax region ftlString contained start=+'+ skip=+\\'+ end=+'+
syntax match ftlNumber contained +\<\d\+\(\.\d\+\)\=\>+

highlight default link ftlComment Comment
highlight default link ftlDelimiter Delimiter
highlight default link ftlDirective Statement
highlight default link ftlKeyword Keyword
highlight default link ftlBuiltin Function
highlight default link ftlOperator Operator
highlight default link ftlInterpolation Identifier
highlight default link ftlString String
highlight default link ftlNumber Number

let b:current_syntax = "freemarker"
