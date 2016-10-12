%%% Copyright (C) 2006 - 2008 Willem de Jong
%%%
%%% This file is part of Erlsom.
%%%
%%% Erlsom is free software: you can redistribute it and/or modify
%%% it under the terms of the GNU Lesser General Public License as 
%%% published by the Free Software Foundation, either version 3 of 
%%% the License, or (at your option) any later version.
%%%
%%% Erlsom is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%%% GNU Lesser General Public License for more details.
%%%
%%% You should have received a copy of the GNU Lesser General Public 
%%% License along with Erlsom.  If not, see 
%%% <http://www.gnu.org/licenses/>.
%%%
%%% Author contact: w.a.de.jong@gmail.com

%%% ====================================================================
%%% Writes record definitions, to be used with Erlsom.
%%% ====================================================================

%%% Writes record defintions, taking a 'model' (from erlsom_compile) as
%%% input.

-module(erlsom_writeHrl).
-export([writeHrl/1]).
-export([writeHrlFile/3]).
-export([writeXsdHrlFile/2]).

-include("erlsom_parse.hrl").
-include("erlsom.hrl").

%% debug(Text) -> io:format("writeHrl: ~p~n", [Text]).

%% debug(Text1, Text2) ->
  %% io:format("~p ~p~n", [Text1, Text2]).

writeHrl(#model{tps = Types, th = TypeHierarchy}) ->
  [header(), writeTypes(Types, TypeHierarchy)].

writeHrlFile(Xsd, Prefix, Namespaces) ->
%% compile file
  Result = erlsom:compile(Xsd, Prefix, Namespaces),
  case Result of
    {ok, Model} -> 
      writeHrl(Model);
    {error, Error} -> 
      io:format("Error while compiling file: ~p~n", [Error])
  end.

writeXsdHrlFile(Xsd, Options) ->
%% compile file
  Result = erlsom:compile_xsd(Xsd, Options),
  case Result of
    {ok, Model} -> 
      writeHrl(Model);
    {error, Error} -> 
      throw({error, Error})
  end.

header() ->
"%% HRL file generated by ERLSOM\n"
"%%\n"
"%% It is possible (and in some cases necessary) to change the name of\n"
"%% the record fields.\n"
"%%\n"
"%% It is possible to add default values, but be aware that these will\n"
"%% only be used when *writing* an xml document.\n\n"
"\n"
"-type anyAttrib()  :: {{string(),    %% name of the attribute\n"
"                        string()},   %% namespace\n"
"                       string()}.    %% value\n"
"\n"
"-type anyAttribs() :: [anyAttrib()] | undefined.\n"
"\n"
"%% xsd:QName values are translated to #qname{} records.\n"
"-record(qname, {uri :: string(),\n"
"                localPart :: string(),\n"
"                prefix :: string(),\n"
"                mappedPrefix :: string()}).\n".

writeTypes(Types, TypeHierarchy) ->
  [writeType(T, TypeHierarchy) || T <- Types].

writeType(#type{nm = '_document'}, _) ->
  [];
writeType(#type{nm = Name, els = Elements, atts = Attributes, mxd = Mixed},
          Hierarchy) ->
  Format = "~3n-record(~p, {anyAttribs :: anyAttribs()~s~s})."
           "~2n-type ~s :: ~s.",
  Args   = [Name, writeAttributes(Attributes), 
            writeElements(Elements, Mixed, Hierarchy),
            formatType(Name), formatRecord(Name)],
  lists:flatten(io_lib:format(Format, Args)).

writeElements(Elements, Mixed, Hierarchy) ->
  writeElements(Elements, Mixed, Hierarchy, 0).

writeElements([], _Mixed, _Hierarchy, _) ->
  [];
writeElements([Element | Tail], Mixed, Hierarchy, CountChoices) ->
  {Elem, CountChoices2} = writeElement(Element, Mixed, Hierarchy, CountChoices),
  NextElems = writeElements(Tail, Mixed, Hierarchy, CountChoices2),
  [",\n\t", Elem, NextElems].

writeElement(#el{alts = Alternatives, mn = Min, mx = Max, nillable = Nillable}, Mixed, Hierarchy, CountChoices) ->
  {Label, Types, Count2} = case Mixed of
    true -> 
      writeAlternatives(Alternatives, 1, 1, false, Hierarchy, CountChoices);
    _ ->
      writeAlternatives(Alternatives, Min, Max, Nillable, Hierarchy, CountChoices)
  end,
  TypeSpec = case Mixed of
    true ->
      [Label, "[", Types, " | string()]"];
    _ ->
      [Label, Types]
  end,
  {TypeSpec, Count2}.


%% returns  {Label (including " :: "), Type, CountChoices}
%%
%% more than 1 alternative: a choice
writeAlternatives(Alts, Min, Max, _N, Hierarchy, CountChoices) when length(Alts) > 1 ->
  Label = case CountChoices of
         0 ->
           "choice :: ";
         _ -> 
           ["choice", integer_to_list(CountChoices), " :: "]
       end,
  Alternatives = [writeAlternative(A, 1, 1, false, Hierarchy) || A <- Alts],
  Type = lists:flatten([minMaxType(string:join(Alternatives, " | "),
                          Min, Max, 1, false, simple)]),
  {Label, Type, CountChoices + 1};
%% 1 alternative (not a choice)
writeAlternatives([#alt{tag = Tag, tp = Tp, rl=Rl} = Alt], Min, Max, Nillable, Hierarchy, CountChoices) ->
  LabelAtom = case Rl of
    true ->
      %% erlsom_lib:nameWithoutPrefix(atom_to_list(Tag));
      Tag;
    _ when Rl == false; Rl == simple ->
      case Tp of 
        {'#PCDATA', _} ->
          Tag;
        _ ->
          Tp
      end
  end,
  Label = io_lib:format("~p :: ", [LabelAtom]),
  Type = writeAlternative(Alt, Min, Max, Nillable, Hierarchy),
  {Label, Type, CountChoices}.

%%  alternative (not a choice), 'real' element (not a group)
writeAlternative(#alt{tag = '#any'}, _, _, _, _) ->
  "any()";
writeAlternative(#alt{rl = true, tp = {Tp1, Tp2}, mx = Max2}, Min, Max, Nillable, _H) ->
  formatSimpleType(Tp1, Tp2, Min, Max, Max2, Nillable);
writeAlternative(#alt{rl = Rl, tp = Type, mx = Max2}, Min, Max, Nillable, Hierarchy) 
  when Rl == true; Rl == simple ->
  %% The type could be abstract, in that case put the 'leaves' of the type hierarchy
  case erlsom_lib:getDescendants(Type, Hierarchy) of
    [] -> 
      formatListType(Type, Min, Max, Max2, Nillable);
    Leaves ->
      minMaxType(string:join([formatType(L) || L <- [Type | Leaves]], " | "),
        Min, Max, Max2, Nillable, false)
  end;
%% simpleContent type
writeAlternative(#alt{rl = false, tp = {Tp1, Tp2}, mx=Max2}, Min, Max, Nillable, _H) ->
  formatSimpleType(Tp1, Tp2, Min, Max, Max2, Nillable);
%% group type
writeAlternative(#alt{rl = false, tp=Tp, mx=Max2}, Min, Max, Nillable, _H) ->
  formatListType(Tp, Min, Max, Max2, Nillable).


formatRecord(Type) ->
    io_lib:format("#~p{}", [Type]).

formatType(Type) ->
    io_lib:format("~p()", [Type]).

%% TODO: delete the flatten call.
writeAttributes(Attributes) ->
   lists:flatten(lists:map(fun writeAttribute/1, Attributes)).


-spec writeAttribute(#att{}) -> Acc when Acc :: iolist().

writeAttribute(#att{nm = Name, opt = Optional, tp = Type}) -> 
    OptOrReq = if Optional -> " | undefined"; true -> "" end,
    Format = ","
             "~n\t~p :: ~s~s",
    io_lib:format(Format, [Name, makeType(Type), OptOrReq]).


formatSimpleType(Tp1, Tp2, Min, Max, Max2, Nullable) ->
  Type = simpleType(Tp1, Tp2),
  minMaxType(Type, Min, Max, Max2, Nullable, true).

minMaxType(Type, Min, Max, Max2, Nullable, Simple) ->
  Optional = if 
    Min == 0 ->
      " | undefined";
    true -> ""
  end,
  {Bracket1, Bracket2} = if
    Max == 1 ->
      {"", ""};
    true ->
      {"[", "]"}
  end,
  {BracketA, BracketB} = if
    Max2 == 1 ->
      {"", ""};
    true ->
      {"[", "]"}
  end,
  NullAlternative = case {Nullable, Simple} of
    {true, true} ->
      " | nil";
    {true, false} ->
      [" | {nil, ", Type, "}"];
    _ ->
      ""
  end,
  lists:flatten([ Bracket1
                , BracketA
                , Type
                , NullAlternative
                , BracketB
                , Bracket2
                , Optional
                ]).

simpleType(_, Type) -> makeType(Type).

makeType(char) -> "string()";
makeType(integer) -> "integer()";
makeType(bool) -> "boolean()";
makeType(float) -> "float()";
makeType(qname) -> "#qname{}".

formatListType(Type, Min, Max, Max2, Nullable) ->
  TypeAsString = formatType(Type),
  minMaxType(TypeAsString, Min, Max, Max2, Nullable, false).
