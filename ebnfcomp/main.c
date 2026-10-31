/*
    EBNF Compiler
    Copyright (C) 2019  Ekkehard Morgenstern

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

    Contact Info:
    E-Mail: ekkehard@ekkehardmorgenstern.de
    Mail: Ekkehard Morgenstern, Mozartstr. 1, 76744 Woerth am Rhein, Germany, Europe
*/

#include <stdlib.h>
#include <stdbool.h>
#include <stdarg.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

/*
language syntax:

TOKEN hexadecimal := /\$[0-9a-fA-F]+/ .

TOKEN identifier  := /[a-z0-9-]+/ .
TOKEN str-literal := /'[^']+'/ | /"[^"]+"/ .

-- during parsing of regular expressions, whitespace skipping will be disabled
TOKEN re-any      := '.' .
TOKEN re-chr      := '\' /./ | /[^\/.*?[(|]/ .

TOKEN re-cc-chr   := '\' /./ | /[^\\\]]/ .
TOKEN re-cc-rng   := re-cc-chr '-' re-cc-chr .
TOKEN re-cc-item  := re-cc-rng | re-cc-chr .
TOKEN re-cc-items := re-cc-item { re-cc-item } .
TOKEN re-cc       := '[' [ '^' ] re-cc-items ']' .

TOKEN re-base-expr   := re-cc | re-chr | re-any | '(' re-expr ')' .
TOKEN re-repeat-expr := re-base-expr [ '+' | '*' | '?' ] .
TOKEN re-and-expr    := re-repeat-expr { re-repeat-expr } .
TOKEN re-or-expr     := re-and-expr { '|' re-and-expr } .
TOKEN re-expr        := re-or-expr .
TOKEN regex          := '/' re-expr '/' .

bin-field-type := 'BYTE' | 'WORD' | 'DWORD' | 'QWORD' .

bin-match   := hexadecimal | bin-field-type [ ':' identifier |
               '*' identifier ] .

base-expr   := identifier | str-literal | regex | bin-match |
               '(' expr ')' | '[' expr ']' | '{' expr '}' .
and-expr    := base-expr { base-expr } .
or-expr     := and-expr { '|' and-expr } .
expr        := or-expr .

production  := [ 'TOKEN' ] identifier ':=' expr '.' .
prod-list   := production { production } .

*/

enum {
    TB_UNDEF  = 0x00,
    TB_DATA   = 0x01,
    TB_BYTE   = 0x02,
    TB_WORD   = 0x03,
    TB_DWORD  = 0x04,
    TB_QWORD  = 0x05,
    TBF_PARAM = 0x10,
    TBF_WRITE = 0x20,
};

typedef enum _token_t {
    T_EOS,
    T_IDENTIFIER,
    T_STR_LITERAL,
    T_REG_EX,
    T_BRACK_EXPR,
    T_BRACE_EXPR,
    T_AND_EXPR,
    T_OR_EXPR,
    T_EXPR,
    T_PRODUCTION,
    T_PROD_LIST,
    T_BIN_DATA,
    T_BIN_FIELD,
    T_BIN_FIELD_COUNT,
    T_BIN_FIELD_TIMES,
} token_t;

static const char* token2text( token_t token ) {
    switch ( token ) {
        default:            return "?";
        case T_EOS:         return "T_EOS";
        case T_IDENTIFIER:  return "T_IDENTIFIER";
        case T_STR_LITERAL: return "T_STR_LITERAL";
        case T_REG_EX:      return "T_REG_EX";
        case T_BRACK_EXPR:  return "T_BRACK_EXPR";
        case T_BRACE_EXPR:  return "T_BRACE_EXPR";
        case T_AND_EXPR:    return "T_AND_EXPR";
        case T_OR_EXPR:     return "T_OR_EXPR";
        case T_EXPR:        return "T_EXPR";
        case T_PRODUCTION:  return "T_PRODUCTION";
        case T_PROD_LIST:   return "T_PROD_LIST";
        case T_BIN_DATA:    return "T_BIN_DATA";
        case T_BIN_FIELD:   return "T_BIN_FIELD";
        case T_BIN_FIELD_COUNT:   return "T_BIN_FIELD_COUNT";
        case T_BIN_FIELD_TIMES:   return "T_BIN_FIELD_TIMES";
    }
}

typedef struct _treenode_t {
    token_t                 token;
    char*                   text;
    struct _treenode_t**    branches;
    size_t                  branchAlloc;
    size_t                  numBranches;
    char*                   exportIdent;
    char*                   nodeTypeEnum;
    int                     id;
    int                     branchesIx;
    int                     refCnt;
    bool                    branchesOutput;
    bool                    implOutput;
} treenode_t;

static void* xmalloc( size_t size ) {
    size_t reqSize = size ? size : 1U;
    void* blk = malloc( reqSize );
    if ( blk == 0 ) {
        fprintf( stderr, "? out of memory\n" );
        exit( EXIT_FAILURE );
    }
    return blk;
}

static void xrealloc( void** pBlk, size_t newSize ) {
    size_t reqSize = newSize ? newSize : 0U;
    if ( *pBlk == 0 ) {
        *pBlk = xmalloc( reqSize );
    } else {
        void* newBlk = realloc( *pBlk, reqSize );
        if ( newBlk == 0 ) {
            fprintf( stderr, "? out of memory\n" );
            exit( EXIT_FAILURE );
        }
        *pBlk = newBlk;
    }
}

static char* xstrdup( const char* text ) {
    size_t len = strlen( text );
    char* blk = (char*) xmalloc( len + 1U );
    strcpy( blk, text );
    return blk;
}

static void dump_tree_node( treenode_t* node, int indent ) {
    if ( node == 0 ) return;
    if ( node->text == 0 ) {
        printf( "%-*.*s%s\n", indent, indent, "", token2text(node->token) );
    } else {
        printf( "%-*.*s%s '%s'\n", indent, indent, "", token2text(node->token), node->text );
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        dump_tree_node( node->branches[i], indent+2 );
    }
}

static treenode_t* create_node( token_t token, const char* text ) {
    treenode_t* node = (treenode_t*) xmalloc( sizeof(treenode_t) );
    node->token        = token;
    node->text         = text ? xstrdup(text) : 0;
    node->branches     = (struct _treenode_t**) xmalloc( sizeof(struct _treenode_t*) * 5U );
    node->branchAlloc  = 5U;
    node->numBranches  = 0U;
    node->exportIdent  = 0;
    node->nodeTypeEnum = 0;
    node->id           = -1;
    node->branchesIx   = -1;
    node->refCnt       = 1;
    node->branchesOutput = false;
    node->implOutput     = false;
    return node;
}

static void delete_node( treenode_t* node ) {
    if ( --node->refCnt > 0 ) return;
    node->branchesIx = -1;
    node->id         = -1;
    if ( node->nodeTypeEnum ) { free( node->nodeTypeEnum ); node->nodeTypeEnum = 0; }
    if ( node->exportIdent  ) { free( node->exportIdent  ); node->exportIdent  = 0; }
    while ( node->numBranches > 0U ) {
        treenode_t* branch = node->branches[--node->numBranches];
        if ( branch ) delete_node( branch );
    }
    free( (void*)(node->branches) ); node->branches = 0;
    node->branchAlloc = 0U;
    if ( node->text ) { free( node->text ); node->text = 0; }
    node->token = T_EOS;
    free( node );
}

static void add_branch( treenode_t* node, treenode_t* branch ) {
    if ( node->numBranches >= node->branchAlloc ) {
        size_t newSize = node->branchAlloc * 2U;
        xrealloc( (void**)(&node->branches), sizeof(struct _treenode_t*) * newSize );
        node->branchAlloc = newSize;
    }
    node->branches[ node->numBranches++ ] = branch;
}

static void set_export_ident( treenode_t* node, const char* text ) {
    if ( node->exportIdent ) { free( node->exportIdent ); node->exportIdent = 0; }
    node->exportIdent = xstrdup( text );
}

static void set_node_type_enum( treenode_t* node, const char* text ) {
    if ( node->nodeTypeEnum ) { free( node->nodeTypeEnum ); node->nodeTypeEnum = 0; }
    node->nodeTypeEnum = xstrdup( text );
}

static int ch  = EOF;
static int lno = 0;
static int chx = 0;

static char rngbuf[64];
static int  wpos = 0;
static int  rpos = 0;

static char regex[256];
static int  repos = 0;

static char pbbuf[256]; // putback buffer
static int  pbpos = -1;

static void storech() {
    rngbuf[wpos] = (char) ch;
    wpos = ( wpos + 1 ) & 63;
}

static void printrng() {
    while ( rpos != wpos ) {
        int c = (int) rngbuf[rpos];
        fputc( c, stderr );
        rpos = ( rpos + 1 ) & 63;
    }
    fputc( '\n', stderr );
}

static void putback( int c ) {
    if ( pbpos < 255 ) pbbuf[++pbpos] = (char) c;
}

static int rdch0( void ) {
    if ( pbpos >= 0 ) {
        return (int)( (unsigned char) pbbuf[pbpos--] );
    }
    return fgetc( stdin );
}

static void rdch( void ) {
RETRY:
    ch = rdch0();
REEVALUATE:
    if ( ch == EOF ) return;
    if ( lno == 0 ) { ++lno; chx = 0; }
    if ( ch == '\r' ) goto RETRY;
    if ( ch == '\n' ) { ++lno; chx = 0; goto RETRY; }
    if ( ch == '-'  ) {
        ch = rdch0();
        if ( ch != '-' ) {
            putback( ch );
            ch = '-';
        } else {
            // -- comment
            do { ch = rdch0(); } while ( ch != '\n' && ch != EOF );
            goto REEVALUATE;
        }
    }
    ++chx;
    storech();
}

static void report( const char* fmt, ... ) {
    char buf[1024];
    va_list ap;
    va_start( ap, fmt );
    vsnprintf( buf, 1024U, fmt, ap );
    va_end( ap );
    fprintf( stderr, "? %s in line %d near position %d\n", buf, lno, chx );
    printrng();
    exit( EXIT_FAILURE );
}

static void skip_whitespace( void ) {
    while ( ch == ' ' || ch == '\t' ) rdch();
}

static treenode_t* read_hexadecimal( void ) {
    // TOKEN hexadecimal := /\$[0-9a-fA-F]+/ .
    if ( ch != '$' ) return 0;
    rdch();
    char tmp[256];
    int  ix = 0;
    while ( isxdigit( ch ) ) {
        if ( ix < 253 ) tmp[ix++] = (char) ch;
        rdch();
    }
    tmp[ix] = '\0';
    if ( ix & 1 ) {
        memmove( &tmp[1], &tmp[0], ix+1U );
        tmp[0] = '0';
    }
    return create_node( T_BIN_DATA, tmp );
}

static treenode_t* read_identifier( void ) {
    // identifier := /[a-z0-9-]+/ .
    char tmp[256];
    int  ix = 0;
    do {
        if ( ix < 255 ) tmp[ix++] = (char) ch;
        rdch();
    } while ( ( ch >= '0' && ch <= '9' ) || ( ch >= 'a' && ch <= 'z' ) ||
        ch == '-' );
    tmp[ix] = '\0';
    return create_node( T_IDENTIFIER, tmp );
}

static treenode_t* read_str_literal( void ) {
    // str-literal := /'[^']+'/ | /"[^"]+"/ .
    char tmp[256];
    int  ix = 0;
    int  term = ch;
    do {
        if ( ch != term && ch != EOF && ix < 255 ) tmp[ix++] = (char) ch;
        rdch();
    } while ( ch != term && ch != EOF );
    rdch();
    if ( ix == 0 ) report( "string literal is empty" );
    tmp[ix] = '\0';
    return create_node( T_STR_LITERAL, tmp );
}

static void store_regex_char( char c ) {
    if ( repos < 255 ) regex[repos++] = (char) c;
}

static bool read_re_any( void ) {
    // re-any := '.' .
    if ( ch != '.' ) return false;
    store_regex_char( '.' );
    rdch();
    return true;
}

static bool read_re_chr( void ) {
    // re-chr := '\' /./ | /[^\/.*?[(|]/ .
    if ( ch == '\\' ) {
        rdch();
        if ( ch == EOF ) report( "unexpected end of file" );
        store_regex_char( '\\' );
    } else {
        switch ( ch ) {
            case EOF:
                report( "unexpected end of file" );
            case '/': case '.': case '*': case '?': case '[': case '(': case '|':
                return false;
            default: break;
        }
    }
    store_regex_char( (char) ch );
    rdch();
    return true;
}

static bool read_re_cc_chr( void ) {
    // re-cc-chr := '\' /./ | /[^\\\]]/ .
    if ( ch == '\\' ) {
        rdch();
        if ( ch == EOF ) report( "unexpected end of file" );
        store_regex_char( '\\' );
    } else {
        switch ( ch ) {
            case EOF:
                report( "unexpected end of file" );
            case '\\': case ']':
                return false;
            default: break;
        }
    }
    store_regex_char( (char) ch );
    rdch();
    return true;
}

static bool read_re_cc_item( void ) {
    // re-cc-rng  := re-cc-chr '-' re-cc-chr .
    // re-cc-item := re-cc-rng | re-cc-chr .
    // -or-
    // re-cc-item := re-cc-chr [ '-' re-cc-chr ] .
    if ( !read_re_cc_chr() ) return false;;
    if ( ch == '-' ) {
        store_regex_char( '-' );
        rdch();
        if ( !read_re_cc_chr() ) report( "bad character class in regular expression" );
    }
    return true;
}

static bool read_re_cc_items( void ) {
    // re-cc-items := re-cc-item { re-cc-item } .
    if ( !read_re_cc_item() ) return false;
    while ( read_re_cc_item() );
    return true;
}

static bool read_re_cc( void ) {
    // re-cc := '[' [ '^' ] re-cc-items ']' .
    if ( ch != '[' ) return false;
    store_regex_char( '[' );
    rdch();
    if ( ch == '^' ) {
        store_regex_char( '^' );
        rdch();
    }
    if ( !read_re_cc_items() || ch != ']' ) report( "bad character class in regular expression" );
    store_regex_char( ']' );
    rdch();
    return true;
}

static bool read_re_expr( void );

static bool read_re_base_expr( void ) {
    // re-base-expr := re-cc | re-chr | re-any | '(' re-expr ')' .
    if ( read_re_cc() || read_re_chr() || read_re_any() ) return true;
    if ( ch != '(' ) return false;
    store_regex_char( '(' );
    rdch();
    if ( !read_re_expr() || ch != ')' ) report( "expression expected in regular expression" );
    store_regex_char( ')' );
    rdch();
    return true;
}

static bool read_re_repeat_expr( void ) {
    // re-repeat-expr := re-base-expr [ '+' | '*' | '?' ] .
    if ( !read_re_base_expr() ) return false;
    if ( ch == '+' || ch == '*' || ch == '?' ) {
        store_regex_char( (char) ch );
        rdch();
    }
    return true;
}

static bool read_re_and_expr( void ) {
    // re-and-expr := re-repeat-expr { re-repeat-expr } .
    if ( !read_re_repeat_expr() ) return false;
    while ( read_re_repeat_expr() );
    return true;
}

static bool read_re_or_expr( void ) {
    // re-or-expr := re-and-expr { '|' re-and-expr } .
    if ( !read_re_and_expr() ) return false;
    do {
        if ( ch != '|' ) break;
        store_regex_char( '|' );
        rdch();
        if ( !read_re_and_expr() ) report( "expression expected in regular expression" );
    } while ( true );
    return true;
}

static bool read_re_expr( void ) {
    // re-expr := re-or-expr .
    return read_re_or_expr();
}

static treenode_t* read_regex( void ) {
    // regex := '/' re-expr '/' .
    if ( ch != '/' ) return false;
    rdch();
    repos = 0;
    if ( !read_re_expr() ) report( "regular expression expected" );
    if ( ch != '/' ) report( "delimiter '/' expected after regular expression" );
    rdch();
    regex[repos] = '\0';
    return create_node( T_REG_EX, regex );
}

static treenode_t* read_expr( void );

static treenode_t* read_paren_expr( void ) {
    // '(' expr ')'
    rdch();
    treenode_t* expr = read_expr();
    if ( expr == 0 ) report( "expression expected after '('" );
    if ( ch != ')' ) report( "closing parenthesis ')' expected" );
    rdch();
    return expr;
}

static treenode_t* read_brack_expr( void ) {
    // '[' expr ']'
    rdch();
    treenode_t* expr = read_expr();
    if ( expr == 0 ) report( "expression expected after '['" );
    if ( ch != ']' ) report( "closing bracket ']' expected" );
    rdch();
    treenode_t* node = create_node( T_BRACK_EXPR, 0 );
    add_branch( node, expr );
    return node;
}

static treenode_t* read_brace_expr( void ) {
    // '{' expr '}'
    rdch();
    treenode_t* expr = read_expr();
    if ( expr == 0 ) report( "expression expected after '{'" );
    if ( ch != '}' ) report( "closing brace '}' expected" );
    rdch();
    treenode_t* node = create_node( T_BRACE_EXPR, 0 );
    add_branch( node, expr );
    return node;
}

static treenode_t* read_bin_match( void ) {
    /*
    bin-field-type := 'BYTE' | 'WORD' | 'DWORD' | 'QWORD' .
    bin-match   := hexadecimal | bin-field-type [ ':' identifier |
                    '*' identifier ]  .
    */
    skip_whitespace();
    if ( ch == '$' ) {
        return read_hexadecimal();
    }
    char tmp[6]; int pos = 0;
    tmp[0] = '\0';
    switch ( ch ) {
        case 'B': case 'W': case 'D': case 'Q':
            do {
                tmp[pos++] = (char) ch;
                rdch();
            } while ( pos < 5 && ch >= 'A' && ch <= 'Z' );
            tmp[pos] = '\0';
            if ( strcmp( tmp, "BYTE" ) == 0 || strcmp( tmp, "WORD" ) == 0 ||
                strcmp( tmp, "DWORD" ) == 0 || strcmp( tmp, "QWORD" ) == 0 ) {
                break;
            }
            putback( ch );
            while ( pos > 0 ) {
                putback( (int)( (unsigned char) tmp[--pos] ) );
            }
            rdch();
            return 0;
        default:
            return 0;
    }
    treenode_t* ident = 0; token_t t = T_BIN_FIELD;
    if ( ch == ':' || ch == '*' ) {
        t = ch == ':' ? T_BIN_FIELD_COUNT : T_BIN_FIELD_TIMES;
        rdch();
        ident = read_identifier();
        if ( ident == 0 ) {
            report( "identifier expected after ':' or '*' in binary match");
        }
    }
    treenode_t* result = create_node( t, tmp );
    if ( ident ) add_branch( result, ident );
    return result;
}

static treenode_t* read_base_expr( void ) {
    // base-expr := identifier | str-literal | regex | bin-match | '(' expr ')'
    //              | '[' expr ']' | '{' expr '}' .
    skip_whitespace();
    switch ( ch ) {
        case '\'': case '"':    return read_str_literal();
        case '/':               return read_regex();
        case '(':               return read_paren_expr();
        case '[':               return read_brack_expr();
        case '{':               return read_brace_expr();
        default:
            if ( ( ch >= 'a' && ch <= 'z' ) || ( ch >= '0' && ch <= '9' ) ) {
                return read_identifier();
            }
            break;
    }
    return read_bin_match();
}

static treenode_t* read_and_expr( void ) {
    // and-expr := base-expr { base-expr } .
    treenode_t* expr = read_base_expr();
    if ( expr == 0 ) return 0;
    treenode_t* node = create_node( T_AND_EXPR, 0 );
    for (;;) {
        add_branch( node, expr );
        expr = read_base_expr();
        if ( expr == 0 ) break;
    }
    if ( node->numBranches == 1 ) {
        expr = node->branches[0]; node->branches[0] = 0;
        delete_node( node );
        return expr;
    }
    return node;
}

static treenode_t* read_or_expr( void ) {
    // or-expr := and-expr { '|' and-expr } .
    treenode_t* expr = read_and_expr();
    if ( expr == 0 ) return 0;
    treenode_t* node = create_node( T_OR_EXPR, 0 );
    for (;;) {
        add_branch( node, expr );
        skip_whitespace();
        if ( ch != '|' ) break;
        rdch();
        expr = read_and_expr();
        if ( expr == 0 ) report( "expression expected after '|'" );
    }
    if ( node->numBranches == 1 ) {
        expr = node->branches[0]; node->branches[0] = 0;
        delete_node( node );
        return expr;
    }
    return node;
}

static treenode_t* read_expr( void ) {
    // expr := or-expr .
    return read_or_expr();
}


static treenode_t* read_production( void ) {
    // production  := [ 'TOKEN' ] identifier ':=' expr '.' .
    skip_whitespace();
    char tmp[6]; int pos = 0;
    tmp[0] = '\0'; bool token = false;
    switch ( ch ) {
        case 'T':
            do {
                tmp[pos++] = (char) ch;
                rdch();
            } while ( pos < 5 && ch >= 'A' && ch <= 'Z' );
            tmp[pos] = '\0';
            if ( strcmp( tmp, "TOKEN" ) == 0 ) {
                token = true;
                break;
            }
            putback( ch );
            while ( pos > 0 ) {
                putback( (int)( (unsigned char) tmp[--pos] ) );
            }
            rdch();
            break;
        default:
            break;
    }
    skip_whitespace();
    treenode_t* ident;
    if ( ( ch >= '0' && ch <= '9' ) || ( ch >= 'a' && ch <= 'z' ) ) {
        ident = read_identifier();
    } else {
        return 0;
    }
    skip_whitespace();
    if ( ch != ':' ) {
        report( "':' expected, but found '%c' (%d)", (ch&0x60?ch:'.'), ch );
    }
    rdch();
    if ( ch != '=' ) report( "'=' expected" );
    rdch();
    treenode_t* expr = read_expr();
    if ( expr == 0 ) report( "expression expected in production" );
    skip_whitespace();
    if ( ch != '.' ) report( "'.' expected" );
    rdch();
    treenode_t* node = create_node( T_PRODUCTION, ident->text );
    delete_node( ident );
    add_branch( node, expr );
    return node;
}

static treenode_t* read_prod_list( void ) {
    // prod-list := production { production } .
    treenode_t* prod = read_production();
    if ( prod == 0 ) return 0;
    treenode_t* node = create_node( T_PROD_LIST, 0 );
    do {
        add_branch( node, prod );
        prod = read_production();
    } while ( prod );
    return node;
}

static treenode_t* tree = 0;

static treenode_t* find_literal_helper( treenode_t* query, treenode_t* node, const char* text, token_t token ) {
    if ( node == 0 ) return 0;
    if ( node->token == token && strcmp( node->text, text ) == 0 ) return node;
    for ( size_t i=0; i < node->numBranches; ++i ) {
        treenode_t* result = find_literal_helper( query, node->branches[i], text, token );
        if ( result ) return result;
    }
    return 0;
}

static treenode_t* find_literal( treenode_t* query, const char* text, token_t token ) {
    return find_literal_helper( query, tree, text, token );
}

static void deduplicate_literals( treenode_t** pBranch, treenode_t* node ) {
    if ( node == 0 ) return;
    if ( node->token == T_STR_LITERAL || node->token == T_REG_EX ) {
        treenode_t* found = find_literal( node, node->text, node->token );
        if ( found ) {
            *pBranch = found; found->refCnt++;
            if ( node != found ) delete_node( node );
            return;
        }
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        deduplicate_literals( &node->branches[i], node->branches[i] );
    }
}

static FILE* impfp = 0;
static FILE* hdrfp = 0;
static char  impfile[256] = { 0, }, hdrfile[256] = { 0, };
static const char* fileStem = 0;

static void help( void ) {
    printf( "%s",
        "usage: ebnfcomp [options] <file-stem>\n"
        "options:\n"
        "    --help, -h                 (this)\n"
        "    --tree, -t                 output syntax tree\n"
        "    --asm , -a                 output assembly language, not C\n"
        "default behavior:\n"
        "    compiles EBNF specified on standard input to internal form,\n"
        "    then outputs C or assembly language code for a parsing table to\n"
        "    a header and implementation file named using <file-stem>.\n"
    );
}

static void name_to_C_enum( char buf[256], const char* name ) {
    snprintf( buf, 256U, "NT_%s", name );
    size_t len = strlen( buf );
    for ( size_t i=0U; i < len; ++i ) {
        if ( buf[i] == '-' ) buf[i] = '_';
        if ( buf[i] >= 'a' && buf[i] <= 'z' ) buf[i] -= 'a'-'A';
    }
}

static bool is_export_node( treenode_t* node ) {
    switch ( node->token ) {
        case T_PRODUCTION:
        case T_STR_LITERAL:
        case T_REG_EX:
        case T_BIN_DATA:
        case T_BIN_FIELD:
        case T_BIN_FIELD_COUNT:
        case T_BIN_FIELD_TIMES:
        case T_AND_EXPR:
        case T_OR_EXPR:
        case T_BRACK_EXPR:
        case T_BRACE_EXPR:
            return true;
        default: break;
    }
    return false;
}

static bool is_name( const char* text ) {
    const char* p = text;
    while ( ( *p >= 'a' && *p <= 'z' ) || ( *p >= 'A' && *p <= 'Z' ) || ( *p >= '0' && *p <= '9' ) || *p == '_' ) ++p;
    if ( *p == '\0' ) return true;
    return false;
}

static const char* name_to_label( const char* text ) {
    static char buf[256];
    snprintf( buf, sizeof(buf), "%s", text );
    char* p = buf;
    while ( *p != '\0' ) {
        if ( *p >= 'a' && *p <= 'z' ) *p -= 'a'-'A';
        ++p;
    }
    return buf;
}

typedef struct _op2label_t {
    const char* op;
    const char* label;
} op2label_t;

static const char* operator_to_label( const char* text ) {
    static const op2label_t map[] = {
        { "<>", "NE", }, { "!=", "CNE" }, { "==", "DEQ" }, { "=", "EQ" }, { ">=", "GE" }, { "<=", "LE" }, { "<", "LT" }, { ">", "GT" },
        { "&", "AND" }, { "&&", "LOGAND" }, { "|", "OR" }, { "||", "LOGOR" }, { ";", "SEMIC" }, { ",", "COMMA" }, { ":", "COLON" },
        { "(", "LPAREN" }, { ")", "RPAREN" }, { "[", "LBRACK" }, { "]", "RBRACK" }, { "{", "LBRACE" }, { "}", "RBRACE" }, { "^", "XOR" },
        { "^^", "LOGXOR" }, { "*", "STAR" }, { "**", "DBLSTAR" }, { "/", "SLASH" }, { "+", "PLUS" }, { "-", "MINUS" },
        { ":=", "ASSIGN" }, { "::=", "ASSIGN2" }, { "~=", "APPLY" }, { "++", "PLUSPLUS" }, { "--", "MINUSMINUS" }, { "+=", "PLUSEQ" },
        { "-=", "MINUSEQ" }, { "*=", "STAREQ" }, { "/=", "SLASHEQ" }, { "&=", "ANDEQ" }, { "|=", "OREQ" }, { "^=", "XOREQ" },
        { ".", "DOT" }, { "!", "EXCLAM" }, { "<<", "LSHIFT" }, { ">>", "RSHIFT" }, { "%", "MODULO" }, { "%=", "MODULOEQ" },
        { "...", "ELLIPSIS" }, { "..", "RANGE" }, { 0, 0 }
    };
    for ( int i=0; map[i].op; ++i ) {
        if ( strcmp( map[i].op, text ) == 0 ) return map[i].label;
    }
    return 0;
}

typedef struct _havelabel_t {
    struct _havelabel_t* next;
    char*                text;
} havelabel_t;

static havelabel_t* havelabel_first = 0;
static havelabel_t* havelabel_last  = 0;

static bool check_have_label( const char* text ) {
    havelabel_t* lab = havelabel_first;
    while ( lab ) {
        if ( strcmp( lab->text, text ) == 0 ) return true;
        lab = lab->next;
    }
    lab = (havelabel_t*) xmalloc( sizeof(havelabel_t) );
    lab->next = 0;
    lab->text = xstrdup( text );
    if ( havelabel_first == 0 ) {
        havelabel_first = havelabel_last = lab;
    } else {
        havelabel_last->next = lab;
        havelabel_last       = lab;
    }
    return false;
}

static int id = 0;

static void output_enums_helper( treenode_t* node, bool doasm ) {
    if ( node == 0 ) return;
    if ( is_export_node( node ) && node->id == -1 ) {
        char tmp[512]; bool print = true;
        if ( node->token == T_PRODUCTION ) {
            name_to_C_enum( tmp, node->text );
        } else if ( node->token == T_STR_LITERAL || node->token == T_REG_EX ) {
            const char* text = 0;
            if ( is_name( node->text ) ) {
                text = name_to_label( node->text );
                snprintf( tmp, 512U, "NT_TERMINAL_%s", text );
                if ( check_have_label( tmp ) ) print = false;
            } else if ( ( text = operator_to_label( node->text ) ) ) {
                snprintf( tmp, 512U, "NT_TERMINAL_%s", text );
                if ( check_have_label( tmp ) ) print = false;
            } else {
                snprintf( tmp, 512U, "NT_TERMINAL_%d", id );
            }
        } else {
            snprintf( tmp, 512U, "%s", "_NT_GENERIC" );
            print = false;
        }
        set_node_type_enum( node, tmp );
        if ( print ) {
            if ( doasm ) {
                static int cnt = 1;
                // 00000000001111111111222222222233333333334444444444
                // 01234567890123456789012345678901234567890123456789
                // _NT_GENERIC             equ         0
                fprintf( hdrfp, "%-23s equ         %d\n", tmp, cnt++ );
            } else {
                fprintf( hdrfp, "    %s,\n", tmp );
            }

        }
        node->id = id++;
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        output_enums_helper( node->branches[i], doasm );
    }
}

static void name_to_C_name( char buf[256], const char* name, const char* prefix ) {
    snprintf( buf, 256U, "%s%s", prefix, name );
    size_t len = strlen( buf );
    for ( size_t i=0U; i < len; ++i ) {
        if ( buf[i] == '-' ) buf[i] = '_';
    }
}

static void text_to_C_text( char buf[512], const char* text, size_t len ) {
    const char* s = text; const char* s2 = text + len;
    char* d = &buf[0]; char* e = &buf[510];
    while ( s < s2 ) {
        if ( *s == '\"' ) {
            if ( d+2 <= e ) {
                *d++ = '\\';
                *d++ = '\"';
            }
        } else if ( *s == '\\' ) {
            if ( d+2 <= e ) {
                *d++ = '\\';
                *d++ = '\\';
            }
        } else if ( (*s&0x60)!=0 && d+1 <= e ) {
            *d++ = *s;
        } else if ( (*s&0x60)==0 && d+4 <= e ) {
            *d++ = '\\';
            *d++ = 'x';
            *d++ = "0123456789abcdef"[(*s>>4)&15];
            *d++ = "0123456789abcdef"[ *s    &15];
        }
        ++s;
    }
    *d = '\0';
}

static bool text_to_asm_text( char buf[512], const char* text, char qc ) {
    const char* s = text; char* d = &buf[0]; char* e = &buf[510];
    while ( *s != '\0' ) {
        if ( *s == qc ) {
            return false;
        } else if ( d+1 <= e ) {
            *d++ = *s;
        }
        ++s;
    }
    *d = '\0';
    return true;
}

static int branches_ix = 0;

static void output_decls_helper( treenode_t* node ) {
    if ( node == 0 ) return;
    if ( node->id >= 0 && node->exportIdent == 0 ) {
        const char* prefix = ""; bool numId = node->token != T_PRODUCTION;
        switch ( node->token ) {
            case T_PRODUCTION:      prefix = "production_"; break;
            case T_STR_LITERAL:     prefix = "string_terminal_"; break;
            case T_REG_EX:          prefix = "regex_terminal_"; break;
            case T_AND_EXPR:        prefix = "mandatory_expr_"; break;
            case T_OR_EXPR:         prefix = "alternative_expr_"; break;
            case T_BRACK_EXPR:      prefix = "optional_expr_"; break;
            case T_BRACE_EXPR:      prefix = "optional_repetitive_expr_"; break;
            default: break;
        }
        char nameText[256];
        if ( numId ) {
            snprintf( nameText, 256U, "%s%d", prefix, node->id );
        } else {
            name_to_C_name( nameText, node->text, prefix );
        }
        set_export_ident( node, nameText );
        if ( node->numBranches != 0U ) {
            node->branchesIx = branches_ix;
            branches_ix += node->numBranches;
        }
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        output_decls_helper( node->branches[i] );
    }
}

static int find_prod_id( treenode_t* node, const char* name ) {
    if ( node == 0 ) return -1;
    if ( node->token == T_PRODUCTION && strcmp( node->text, name ) == 0 ) return node->id;
    for ( size_t i=0; i < node->numBranches; ++i ) {
        int id = find_prod_id( node->branches[i], name );
        if ( id >= 0 ) return id;
    }
    return -1;
}

static void report2( const char* fmt, ... ) {
    va_list ap;
    va_start( ap, fmt );
    fprintf( stderr, "? " );
    vfprintf( stderr, fmt, ap );
    fprintf( stderr, "\n" );
    va_end( ap );
    exit( EXIT_FAILURE );
}

// -- default output: C -------------------------------------------------------

static int output_branches_helper( treenode_t* node, int index ) {
    if ( node == 0 ) return 0;
    if ( node->id >= 0 && node->branchesIx == index ) {
        fprintf( impfp, "    // %d: %s branches\n    ", node->branchesIx,
            node->exportIdent );
        for ( size_t i=0; i < node->numBranches; ++i ) {
            treenode_t* branch = node->branches[i]; int id;
            if ( branch->id >= 0 ) {
                fprintf( impfp, "%d, ", branch->id );
            } else if ( branch->token == T_IDENTIFIER &&
                ( id = find_prod_id( tree, branch->text ) ) >= 0 ) {
                fprintf( impfp, "%d, ", id );
            } else if ( node->token != T_BIN_DATA &&
                ( node->token < T_BIN_FIELD ||
                  node->token > T_BIN_FIELD_TIMES ) ) {
                if ( branch->token == T_IDENTIFIER ) report2( "production '%s' not found", branch->text );
                fprintf( impfp, "-1 /* %s */, ", token2text(branch->token) );
            } else {
                fprintf( impfp, "-2 /* %s */, ", token2text(branch->token) );
            }
        }
        fprintf( impfp, "\n" );
        return node->numBranches;
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        int n = output_branches_helper( node->branches[i], index );
        if ( n ) return n;
    }
    return 0;
}

static void output_branches( void ) {
    for ( int i=0; i < branches_ix; ) {
        i += output_branches_helper( tree, i );
    }
}

static bool output_impls_helper( treenode_t* node, int id ) {
    if ( node == 0 ) return false;
    if ( node->id == id ) {
        bool numId = node->token != T_PRODUCTION;
        char text[1024]; const char* termType = "TT_UNDEF";
        const char* nodeClass = "???";
        text[0] = '0'; text[1] = '\0';
        if ( numId ) {
            if ( node->token == T_STR_LITERAL || node->token == T_REG_EX ||
                node->token == T_BIN_DATA || ( node->token >= T_BIN_FIELD &&
                node->token <= T_BIN_FIELD_TIMES ) ) {
                nodeClass = "NC_TERMINAL";
                if ( node->token == T_STR_LITERAL ) {
                    termType = "TT_STRING";
                } else if ( node->token == T_REG_EX ) {
                    termType = "TT_REGEX";
                } else { // T_BIN_DATA or T_BIN_FIELD
                    termType = "TT_BINARY";
                }
            } else {
                switch ( node->token ) {
                    case T_AND_EXPR:    nodeClass = "NC_MANDATORY"; break;
                    case T_OR_EXPR:     nodeClass = "NC_ALTERNATIVE"; break;
                    case T_BRACK_EXPR:  nodeClass = "NC_OPTIONAL"; break;
                    case T_BRACE_EXPR:  nodeClass = "NC_OPTIONAL_REPETITIVE"; break;
                    default: break;
                }
            }
            if ( node->text ) {
                char tmp[512];
                tmp[0] = '\0';
                if ( node->token == T_STR_LITERAL || node->token == T_REG_EX ) {
                    text_to_C_text( tmp, node->text, strlen( node->text ) );
                } else if ( node->token == T_BIN_DATA ) {
                    const char* s   = node->text;
                    size_t      len = strlen( s );
                    size_t      nb  = len / 2U;
                    size_t      i;
                    char        tmp2[256];
                    if ( nb > 256U ) nb = 256U;
                    for ( i=0; i < nb; ++i ) {
                        char c[3]; int x = 0;
                        c[0] = *s++;
                        c[1] = *s++;
                        c[2] = '\0';
                        sscanf( c, "%x", &x );
                        tmp2[i] = (char) x;
                    }
                    text_to_C_text( tmp, tmp2, nb );
                } else if ( node->token >= T_BIN_FIELD &&
                    node->token <= T_BIN_FIELD_TIMES ) {
                    int v = 0;
                    if ( strcmp( node->text, "BYTE" ) == 0 ) {
                        v |= TB_BYTE;
                    }
                    else if ( strcmp( node->text, "WORD" ) == 0 ) {
                        v |= TB_WORD;
                    }
                    else if ( strcmp( node->text, "DWORD" ) == 0 ) {
                        v |= TB_DWORD;
                    }
                    else if ( strcmp( node->text, "QWORD" ) == 0 ) {
                        v |= TB_QWORD;
                    }
                    if ( node->numBranches > 0U ) {
                        v |= TBF_PARAM;
                    }
                    if ( node->token == T_BIN_FIELD_COUNT ) {
                        v |= TBF_WRITE;
                    }
                    char b = (char) v;
                    text_to_C_text( tmp, &b, 1U );
                }
                snprintf( text, 1024U, "\"%s\"", tmp );
            }
        } else {
            nodeClass = "NC_PRODUCTION";
        }
        fprintf( impfp,
            "    // %d: %s\n"
            "    { %s, %s, %s, %s, %d, %d },\n"
            , node->id, node->exportIdent
            , nodeClass, node->nodeTypeEnum, termType, text
            , (int) node->numBranches, node->branchesIx
        );
        return true;
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        if ( output_impls_helper( node->branches[i], id ) ) return true;
    }
    return false;
}

static void output_impls( void ) {
    for ( int i=0; i < id; ++i ) {
        output_impls_helper( tree, i );
    }
}

static void output_code( void ) {
    char hdrsym[256];
    snprintf( hdrsym, 256U, "%s", hdrfile );
    char* p = hdrsym;
    while ( *p != '\0' ) {
        char c = *p; int iuc = (unsigned char) c;
        if ( islower( iuc ) ) {
            iuc = toupper( iuc );
            c   = (char) iuc;
        } else if ( c == '.' || c == '/' || c == '\\' || c == ':' ) {
            c   = '_';
        }
        *p++ = c;
    }
    fprintf( hdrfp,
        "// code auto-generated by ebnfcomp; do not modify!\n"
        "// (code might get overwritten during next ebnfcomp invocation)\n\n"
        "#ifndef %s\n"
        "#define %s 1\n\n"
        "#include <stddef.h>\n\n"
        "typedef enum _nodeclass_t {\n"
        "    NC_TERMINAL,\n"
        "    NC_PRODUCTION,\n"
        "    NC_MANDATORY,\n"
        "    NC_ALTERNATIVE,\n"
        "    NC_OPTIONAL,\n"
        "    NC_OPTIONAL_REPETITIVE,\n"
        "} nodeclass_t;\n\n"
        "typedef enum _terminaltype_t {\n"
        "    TT_UNDEF,\n"
        "    TT_STRING,\n"
        "    TT_REGEX,\n"
        "    TT_BINARY,\n"
        "} terminaltype_t;\n\n"
        "enum {\n"
        "    TB_UNDEF  = 0x00,\n"
        "    TB_DATA   = 0x01,\n"
        "    TB_BYTE   = 0x02,\n"
        "    TB_WORD   = 0x03,\n"
        "    TB_DWORD  = 0x04,\n"
        "    TB_QWORD  = 0x05,\n"
        "    TBF_PARAM = 0x10,\n"
        "    TBF_WRITE = 0x20,\n"
        "};\n\n"
        "typedef enum _nodetype_t {\n"
        "    _NT_GENERIC,\n",
        hdrsym, hdrsym
    );
    output_enums_helper( tree, false );
    fprintf( hdrfp, "%s",
        "} nodetype_t;\n\n"
        "typedef struct _parsingnode_t {\n"
        "    nodeclass_t        nodeClass;\n"
        "    nodetype_t         nodeType;\n"
        "    terminaltype_t     termType;\n"
        "    const char*        text;\n"
        "    size_t             numBranches;\n"
        "    int                branches;\n"
        "} parsingnode_t;\n\n"
    );
    output_decls_helper( tree );
    fprintf( hdrfp, "extern const int %s_branches[%d];\n", fileStem,
        branches_ix );
    fprintf( impfp,
        "// code auto-generated by ebnfcomp; do not modify!\n"
        "// (code might get overwritten during next ebnfcomp invocation)\n\n"
        "#include \"%s\"\n\n"
        "// branches\n\n"
        "const int %s_branches[%d] = {\n"
        , hdrfile, fileStem, branches_ix
    );
    output_branches();
    fprintf( hdrfp, "extern const parsingnode_t %s_parsingTable[%d];\n\n",
        fileStem, id );
    fprintf( hdrfp, "#endif\n" );
    fprintf( impfp,
        "};\n\n"
        "const parsingnode_t %s_parsingTable[%d] = {\n"
        , fileStem, id
    );
    output_impls();
    fprintf( impfp,
        "};\n\n"
    );
}

// -- optional output: Assembly Language --------------------------------------

static int output_branches_helper_asm( treenode_t* node, int index ) {
    if ( node == 0 ) return 0;
    if ( node->id >= 0 && node->branchesIx == index ) {
        fprintf( impfp,
                "                        ; %d: %s branches\n"
                "                        dw          ",
            node->branchesIx, node->exportIdent );
        for ( size_t i=0; i < node->numBranches; ++i ) {
            treenode_t* branch = node->branches[i]; int id;
            bool last = i == node->numBranches - 1U;
            if ( branch->id >= 0 ) {
                fprintf( impfp, "%d%s ", branch->id, last?"":"," );
            } else if ( branch->token == T_IDENTIFIER &&
                ( id = find_prod_id( tree, branch->text ) ) >= 0 ) {
                fprintf( impfp, "%d%s ", id, last?"":"," );
            } else if ( node->token != T_BIN_DATA &&
                ( node->token < T_BIN_FIELD ||
                  node->token > T_BIN_FIELD_TIMES ) ) {
                if ( branch->token == T_IDENTIFIER ) {
                    report2( "production '%s' not found", branch->text );
                }
                fprintf( impfp, "-1 ; %s%s",
                    token2text(branch->token),
                    (last?"":"\n                        dw          ") );
            } else {
                fprintf( impfp, "-2 ; %s%s",
                    token2text(branch->token),
                    (last?"":"\n                        dw          ") );
            }
        }
        fprintf( impfp, "\n" );
        return node->numBranches;
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        int n = output_branches_helper_asm( node->branches[i], index );
        if ( n ) return n;
    }
    return 0;
}

static void output_branches_asm( void ) {
    for ( int i=0; i < branches_ix; ) {
        i += output_branches_helper_asm( tree, i );
    }
}

static void text_as_source_asm( char* buf, size_t bufsz, const char* s ) {
    char tmp[512];
    if ( text_to_asm_text( tmp, s, '\'' ) ) {
        snprintf( buf, bufsz, "'%s'", tmp );
    } else if ( text_to_asm_text( tmp, s, '"' ) ) {
        snprintf( buf, bufsz, "\"%s\"", tmp );
    } else {
        bool first = true;
        char* d = buf; char* e = &buf[bufsz-1U];
        while ( *s != '\0' ) {
            if ( !first ) {
                if ( d+1 < e ) *d++ = ',';
            } else {
                first = false;
            }
            if ( d+4 < e ) {
                unsigned char hnyb = ( *s >> 4 ) & 15;
                unsigned char lnyb = *s & 15;
                *d++ = '0';
                *d++ = 'x';
                *d++ = "0123456789abcdef"[hnyb];
                *d++ = "0123456789abcdef"[lnyb];
            }
            ++s;
        }
        *d = '\0';
    }
}

static void dump_as_source_asm( char* buf, size_t bufsz, const char* s ) {
    size_t len = strlen(s);
    if ( len & 1U ) report( "unexpected odd length in string '%s'", s );
    size_t nbytes = len / 2U;
    char* p = buf; char* e = &buf[bufsz-1U];
    if ( p + 7 < e ) {
        strcpy( p, "TB_DATA" );
        p += 7;
    }
    if ( p + 5 < e ) {
        *p++ = ',';
        *p++ = '0';
        *p++ = 'x';
        *p++ = "0123456789abcdef"[(nbytes>>4U)&15U];
        *p++ = "0123456789abcdef"[ nbytes     &15U];
    }
    for ( size_t i=0; i < nbytes; ++i ) {
        // bool last = i == nbytes-1U;
        if ( p + 5 >= e ) {
            report( "object too large during output at '%s'", s );
        }
        else {
            *p++ = ',';
            *p++ = '0';
            *p++ = 'x';
            *p++ = *s++;
            *p++ = *s++;
        }
    }
    *p = '\0';
}

static void field_as_source_asm( char* buf, size_t bufsz, treenode_t* node ) {
    snprintf( buf, bufsz, "TB_%s%s%s", node->text,
        (node->numBranches?"|TBF_PARAM":""), (node->token==T_BIN_FIELD_COUNT?
        "|TBF_WRITE":"") );
}

static bool output_texts_helper_asm( treenode_t* node, int id ) {
    if ( node == 0 ) return false;
    if ( node->id == id ) {
        bool numId = node->token != T_PRODUCTION;
        char text[1024], labl[256];
        text[0] = '\0';
        if ( numId ) {
            if ( ( node->token == T_STR_LITERAL || node->token == T_REG_EX )
                && node->text ) {
                text_as_source_asm( text, 1024U, node->text );
            } else if ( node->token == T_BIN_DATA ) {
                dump_as_source_asm( text, 1024U, node->text );
            } else if ( node->token >= T_BIN_FIELD &&
                node->token <= T_BIN_FIELD_TIMES ) {
                field_as_source_asm( text, 1024U, node );
            }
        }
        if ( text[0] != '\0' && ( node->token == T_STR_LITERAL ||
            node->token == T_REG_EX ) ) {
            snprintf( labl, 256U, "prod_%d_text", node->id );
            fprintf( impfp, "%-23s db          %s,0\n", labl, text );
        } else if ( text[0] != '\0' && ( node->token == T_BIN_DATA ||
            ( node->token >= T_BIN_FIELD &&
              node->token <= T_BIN_FIELD_TIMES  ) ) ) {
            snprintf( labl, 256U, "prod_%d_text", node->id );
            fprintf( impfp, "%-23s db          %s\n", labl, text );
        }
        return true;
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        if ( output_texts_helper_asm( node->branches[i], id ) ) return true;
    }
    return false;
}

static void output_texts_asm( void ) {
    for ( int i=0; i < id; ++i ) {
        output_texts_helper_asm( tree, i );
    }
}

static bool output_impls_helper_asm( treenode_t* node, int id ) {
    if ( node == 0 ) return false;
    if ( node->id == id ) {
        bool numId = node->token != T_PRODUCTION;
        const char* termType = "TT_UNDEF"; const char* nodeClass = "???";
        if ( numId ) {
            if ( node->token == T_STR_LITERAL || node->token == T_REG_EX ||
                node->token == T_BIN_DATA || ( node->token >= T_BIN_FIELD &&
                node->token <= T_BIN_FIELD_TIMES ) ) {
                nodeClass = "NC_TERMINAL";
                if ( node->token == T_STR_LITERAL ) {
                    termType = "TT_STRING";
                } else if ( node->token == T_REG_EX ) {
                    termType = "TT_REGEX";
                } else { // T_BIN_DATA or T_BIN_FIELD
                    termType = "TT_BINARY";
                }
            } else {
                switch ( node->token ) {
                    case T_AND_EXPR:    nodeClass = "NC_MANDATORY"; break;
                    case T_OR_EXPR:     nodeClass = "NC_ALTERNATIVE"; break;
                    case T_BRACK_EXPR:  nodeClass = "NC_OPTIONAL"; break;
                    case T_BRACE_EXPR:  nodeClass = "NC_OPTIONAL_REPETITIVE"; break;
                    default: break;
                }
            }
        } else {
            nodeClass = "NC_PRODUCTION";
        }
        fprintf( impfp, "                        ; %d: %s\n", node->id,
            node->exportIdent );
        fprintf( impfp, "                        db          %s, %s\n",
            nodeClass, termType );
        fprintf( impfp, "                        dw          %s, %d, %d\n",
            node->nodeTypeEnum, (int) node->numBranches, node->branchesIx );
        if ( numId && node->text != 0 ) {
            fprintf( impfp,
                "                        dq          prod_%d_text\n",
                node->id );
        } else {
            fprintf( impfp, "                        dq          0\n" );
        }
        return true;
    }
    for ( size_t i=0; i < node->numBranches; ++i ) {
        if ( output_impls_helper_asm( node->branches[i], id ) ) return true;
    }
    return false;
}

static void output_impls_asm( void ) {
    for ( int i=0; i < id; ++i ) {
        output_impls_helper_asm( tree, i );
    }
}

static void output_code_asm( void ) {
    fprintf( hdrfp, "%s",
        "; code auto-generated by ebnfcomp; do not modify!\n"
        "; (code might get overwritten during next ebnfcomp invocation)\n\n"
        "                        cpu         x64\n"
        "                        bits        64\n\n"
        "NC_TERMINAL             equ         0\n"
        "NC_PRODUCTION           equ         1\n"
        "NC_MANDATORY            equ         2\n"
        "NC_ALTERNATIVE          equ         3\n"
        "NC_OPTIONAL             equ         4\n"
        "NC_OPTIONAL_REPETITIVE  equ         5\n\n"
        "TT_UNDEF                equ         0\n"
        "TT_STRING               equ         1\n"
        "TT_REGEX                equ         2\n"
        "TT_BINARY               equ         3\n\n"
        "TB_UNDEF                equ         0x00\n"
        "TB_DATA                 equ         0x01\n"
        "TB_BYTE                 equ         0x02\n"
        "TB_WORD                 equ         0x03\n"
        "TB_DWORD                equ         0x04\n"
        "TB_QWORD                equ         0x05\n"
        "TBF_PARAM               equ         0x10\n"
        "TBF_WRITE               equ         0x20\n\n"
        "_NT_GENERIC             equ         0\n"
    );
    output_enums_helper( tree, true );
    fprintf( hdrfp, "%s",
        "\n"
        "                        struc      parsingnode\n"
        "                           pn_nodeClass:       resb    1\n"
        "                           pn_termType:        resb    1\n"
        "                           pn_nodeType:        resw    1\n"
        "                           pn_numBranches:     resw    1\n"
        "                           pn_branches:        resw    1\n"
        "                           pn_text:            resq    1\n"
        "                        endstruc\n\n"
    );
    output_decls_helper( tree );
    fprintf( impfp,
        "; code auto-generated by ebnfcomp; do not modify!\n"
        "; (code might get overwritten during next ebnfcomp invocation)\n\n"
        "                        cpu         x64\n"
        "                        bits        64\n\n"
        "                        %%include    \"%s\"\n\n"
        "                        section     .rodata\n\n"
        "                        global      %s_branches\n"
        "                        global      %s_parsingTable\n\n"
        "%s_branches:\n", hdrfile, fileStem, fileStem, fileStem
    );
    output_branches_asm();
    fprintf( impfp, "\n\n" );
    output_texts_asm();
    fprintf( impfp,
        "\n\n"
        "                        align       8,db 0\n\n"
        "%s_parsingTable:\n", fileStem
    );
    output_impls_asm();
    fprintf( impfp,
        "\n\n"
    );
}

// -- main program ------------------------------------------------------------

int main( int argc, char** argv ) {

    bool printTree = false;
    bool printAsm  = false;

    for ( int i=1; i < argc; ++i ) {
        const char* arg = argv[i];
        if ( strcmp( arg, "--help" ) == 0 || strcmp( arg, "-h" ) == 0 ) {
            help();
            return EXIT_SUCCESS;
        }
        else if ( strcmp( arg, "--tree" ) == 0 || strcmp( arg, "-t" ) == 0 ) {
            printTree = true;
        }
        else if ( strcmp( arg, "--asm" ) == 0 || strcmp( arg, "-a" ) == 0 ) {
            printAsm = true;
        }
        else if ( fileStem == 0 && arg[0] != '-' ) {
            fileStem = arg;
            printf( "file stem is '%s'\n", fileStem );
        }
        else if ( arg[0] == '-' ) {
            fprintf( stderr, "unknown option '%s'\n", arg );
            return EXIT_FAILURE;
        }
        else {
            fprintf( stderr, "unknown parameter '%s'\n", arg );
            return EXIT_FAILURE;
        }
    }

    if ( fileStem == 0 ) {
        fprintf( stderr, "missing parameter, see --help\n" );
        return EXIT_FAILURE;
    }

    if ( printAsm ) {
        snprintf( impfile, 256U, "%s.nasm", fileStem );
        snprintf( hdrfile, 256U, "%s.inc", fileStem );
    } else {
        snprintf( impfile, 256U, "%s.c", fileStem );
        snprintf( hdrfile, 256U, "%s.h", fileStem );
    }
    impfp = fopen( impfile, "wt" );
    if ( impfp == 0 ) {
        fprintf( stderr, "? failed to create implementation file '%s': %m\n",
            impfile );
        return EXIT_FAILURE;
    }
    hdrfp = fopen( hdrfile, "wt" );
    if ( hdrfp == 0 ) {
        fprintf( stderr, "? failed to create header file '%s': %m\n",
            hdrfile );
        return EXIT_FAILURE;
    }

    rdch();
    treenode_t* prodlist = read_prod_list();
    if ( prodlist == 0 ) report( "production list expected" );

    if ( printTree ) { dump_tree_node( prodlist, 0 ); return EXIT_SUCCESS; }

    tree = prodlist;
    deduplicate_literals( &tree, tree );
    if ( printAsm ) {
        output_code_asm();
    } else {
        output_code();
    }

    return EXIT_SUCCESS;
}
