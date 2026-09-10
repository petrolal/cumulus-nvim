" TetraVim Apache Velocity (VTL) syntax -- HTML base + Velocity directives / references
"
" No upstream nvim-treesitter grammar and no bundled Vim syntax exist for
" Velocity, so this is a pragmatic hand-rolled layer: load the HTML syntax for
" the markup, then paint #directives, $references and ## / #* *# comments on
" top. Not a full parser -- enough for readable .vm.

if exists("b:current_syntax")
  finish
endif

runtime! syntax/html.vim
unlet! b:current_syntax

syntax case match

" Comments: `## to end of line` and `#* ... *#` blocks.
syntax match velocityComment +##.*$+ contains=@Spell
syntax region velocityComment start=+#\*+ end=+\*#+ contains=@Spell keepend

" #set / #if / #foreach / ... directives, both `#if(...)` and `#{if}(...)` forms.
syntax match velocityDirective +#\{1,2}{\=\%(set\|if\|elseif\|else\|end\|foreach\|break\|stop\|parse\|include\|evaluate\|define\|macro\)\>}\=+
      \ nextgroup=velocityDirectiveArgs
syntax region velocityDirectiveArgs contained matchgroup=velocityDelimiter start=+(+ end=+)+
      \ contains=velocityReference,velocityString,velocityNumber,velocityOperator keepend

" $ref, $!ref, ${ref}, $ref.method($arg), $ref.prop
syntax match velocityReference +\$!\={\=[a-zA-Z_][a-zA-Z0-9_]*\%(\.[a-zA-Z_][a-zA-Z0-9_]*\%((.\{-})\)\=\)*}\=+

syntax match velocityOperator contained +[=!<>]=\|&&\|||\|\<\%(and\|or\|not\|eq\|ne\|gt\|lt\|ge\|le\)\>+
syntax region velocityString contained start=+"+ skip=+\\"+ end=+"+ contains=velocityReference
syntax region velocityString contained start=+'+ end=+'+
syntax match velocityNumber contained +\<\d\+\>+

highlight default link velocityComment Comment
highlight default link velocityDelimiter Delimiter
highlight default link velocityDirective Statement
highlight default link velocityReference Identifier
highlight default link velocityOperator Operator
highlight default link velocityString String
highlight default link velocityNumber Number

let b:current_syntax = "velocity"
