;   AsmBASIC - a BASIC compile and go system written in assembly language
;   Copyright (C) 2022  Ekkehard Morgenstern
;
;   This program is free software: you can redistribute it and/or modify
;   it under the terms of the GNU General Public License as published by
;   the Free Software Foundation, either version 3 of the License, or
;   (at your option) any later version.
;
;   This program is distributed in the hope that it will be useful,
;   but WITHOUT ANY WARRANTY; without even the implied warranty of
;   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;   GNU General Public License for more details.
;
;   You should have received a copy of the GNU General Public License
;   along with this program.  If not, see <https://www.gnu.org/licenses/>.
;
;   NOTE: Programs created with AsmBASIC do not fall under this license.
;
;   CONTACT INFO:
;       E-Mail: ekkehard@ekkehardmorgenstern.de
;       Mail: Ekkehard Morgenstern, Mozartstr. 1, D-76744 Woerth am Rhein,
;             Germany, Europe

; see implementation notes file provided in "implnotes.txt"

                        cpu         x64
                        bits        64

                        %include    "syntree.inc"
                        %include    "cookedsyntree.inc"

                        section     .text
                        extern      cookedsyntree
                        global      refinecookedsyntree

; GOALS:
;   - Rearrange cooked syntax tree such that:
;     o The line number is the first subnode of the root node
;       (and its parent generic node is marked as S_LINENUMBER).
;     o Statements separated by semicolon are regrouped to be
;       children of the root node, each of their generic parent
;       nodes are marked with S_STATEMENT.
;     o Colon operators can be removed.
;     o Expressions will be marked with a S_EXPRESSION parent.
;     o They become direct children of the statement or function
;       call / array access nodes they belong to.
;     o Comma operators can be removed.
;     o Nodes that became superfluous as a part of previous
;       operations are discarded (i.e. generic nodes that
;       became empty), and branch tables are cleaned up.
;     o The root node is marked with S_LINE.
;   - Future steps:
;     o ...
;

                        ; rdi - cooked syntax (sub-)tree
refine_csn              enter       0,0

                        leave
                        ret

refinecookedsyntree     enter       0,0

                        mov         rdi,[cookedsyntree]
                        test        rdi,rdi
                        jz          .end

                        call        refine_csn

.end                    leave
                        ret
