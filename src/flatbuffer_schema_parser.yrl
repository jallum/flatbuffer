Nonterminals root definition option fields field key_def value attribute_def attributes enums enum_def unions union_def identifier type struct_fields.
Terminals  table struct enum union namespace root_type include attribute file_identifier file_extension float int bool string '-' '}' '{' '(' ')' '['']' ';' ',' ':' '=' quote.
Rootsymbol root.

root -> definition      : {'$1', []}.
root -> option          : {#{}, ['$1']}.
root -> root definition : add_def('$1', '$2').
root -> root option     : add_opt('$1', '$2').

% options (non-quoted)
option -> namespace string ';' : {get_name('$1'), get_value_bin('$2')}.
option -> root_type string ';' : {get_name('$1'), get_value_bin('$2')}.

% options (quoted)
option -> include quote string quote ';'         : {get_name('$1'), get_value_bin('$3')}.
option -> attribute quote string quote ';'       : {get_name('$1'), get_value_bin('$3')}.
option -> file_identifier quote string quote ';' : {get_name('$1'), get_value_bin('$3')}.
option -> file_extension quote string quote ';'  : {get_name('$1'), get_value_bin('$3')}.

% definitions
definition -> table string '{' fields '}'           : #{get_value_bin('$2') => {table, '$4'}}.
definition -> table string '{' '}'                  : #{get_value_bin('$2') => {table, []}}.
definition -> enum string ':' type '{' enums '}'    : #{get_value_bin('$2') => {{enum, '$4'}, '$6'}}.
definition -> union string '{' unions '}'           : #{get_value_bin('$2') => {union, '$4'}}.
definition -> struct string '{' struct_fields '}'   : #{get_value_bin('$2') => {struct, '$4'}}.

% enums
enums -> enum_def             : [ '$1' ].
enums -> enum_def ',' enums   : [ '$1' | '$3'].
enums -> enum_def ','         : [ '$1' ].

enum_def -> identifier                : '$1'.
enum_def -> identifier '=' int        : {'$1', get_value('$3')}.
enum_def -> identifier '=' identifier : {'$1', '$3'}.

% unions
unions -> union_def             : [ '$1' ].
unions -> union_def ',' unions  : [ '$1' | '$3'].
unions -> union_def ','         : [ '$1' ].

union_def -> string : get_value_bin('$1').

% tables
fields -> field ';'         : [ '$1' ].
fields -> field ';' fields  : [ '$1' | '$3' ].

field -> key_def                    : '$1'.
field -> key_def '(' attributes ')' : with_attributes('$1', '$3').

key_def -> identifier ':' type              : {'$1', '$3'}.
key_def -> identifier ':' '[' type ']'      : {'$1', {vector, '$4'}}.
key_def -> identifier ':' type '=' value    : {'$1', {'$3', '$5'}}.

attributes -> attributes ',' attribute_def : maps:merge('$1', '$3').
attributes -> attribute_def                : '$1'.
attribute_def -> string ':' value          : #{get_value_bin('$1') => '$3'}.
attribute_def -> string                    : #{get_value_bin('$1') => true}.

type -> string : get_type('$1').

value -> '-' int   : -get_value('$2').
value -> '-' float : -get_value('$2').
value -> int       : get_value('$1').
value -> float     : get_value('$1').
value -> bool      : get_value('$1').
value -> identifier : '$1'.

identifier -> string : get_value_bin('$1').

% struct fields
struct_fields -> field ';'             : [ '$1' ].
struct_fields -> field ';' struct_fields : [ '$1' | '$3' ].

Erlang code.

get_value_bin({_Token, _Line, Value})  -> list_to_binary(Value).
get_value({_Token, _Line, Value})      -> Value.

get_name({Token, _Line, _Value})  -> Token;
get_name({Token, _Line})          -> Token.

get_type({_Token, _Line, "bool"})   -> bool;
get_type({_Token, _Line, "byte"})   -> byte;
get_type({_Token, _Line, "ubyte"})  -> ubyte;
get_type({_Token, _Line, "short"})  -> short;
get_type({_Token, _Line, "ushort"}) -> ushort;
get_type({_Token, _Line, "int"})    -> int;
get_type({_Token, _Line, "uint"})   -> uint;
get_type({_Token, _Line, "long"})   -> long;
get_type({_Token, _Line, "ulong"})  -> ulong;
get_type({_Token, _Line, "float"})  -> float;
get_type({_Token, _Line, "double"}) -> double;
get_type({_Token, _Line, "string"}) -> string;
get_type({_Token, _Line, Value})    -> list_to_binary(Value).

add_def({Defs, Opts}, Def) -> {maps:merge(Defs, Def), Opts}.
add_opt({Defs, Opts}, Opt) -> {Defs, [Opt | Opts]}.

with_attributes({Name, Type}, Attributes) ->
    {Name, {attributes, Type, Attributes}}.
