############################################################################################
##    EBNF Compiler                                                                       ##
##    Copyright (C) 2019  Ekkehard Morgenstern                                            ##
##                                                                                        ##
##    This program is free software: you can redistribute it and/or modify                ##
##    it under the terms of the GNU General Public License as published by                ##
##    the Free Software Foundation, either version 3 of the License, or                   ##
##    (at your option) any later version.                                                 ##
##                                                                                        ##
##    This program is distributed in the hope that it will be useful,                     ##
##    but WITHOUT ANY WARRANTY; without even the implied warranty of                      ##
##    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                       ##
##    GNU General Public License for more details.                                        ##
##                                                                                        ##
##    You should have received a copy of the GNU General Public License                   ##
##    along with this program.  If not, see <https://www.gnu.org/licenses/>.              ##
##                                                                                        ##
##    Contact Info:                                                                       ##
##    E#Mail: ekkehard@ekkehardmorgenstern.de                                             ##
##    Mail: Ekkehard Morgenstern, Mozartstr. 1, 76744 Woerth am Rhein, Germany, Europe    ##
############################################################################################

ifdef DEBUG
CFLAGS=-g
else
CFLAGS=-O2
endif

CFLAGS+= -Wall

ebnfcomp: 	main.c
	gcc -o ebnfcomp $(CFLAGS) main.c 

