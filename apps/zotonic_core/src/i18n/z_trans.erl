%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2009-2020 Marc Worrell
%% @doc Translate english sentences into other languages, following
%% the GNU gettext principle.

%% Copyright 2009-2020 Marc Worrell
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(z_trans).
-author("Marc Worrell <marc@worrell.nl>").

-export([
    translations/2,
    parse_translations/1,
    trans/2,
    trans/3,
    lookup/2,
    lookup/3,
    lookup_fallback/2,
    lookup_fallback/3,
    lookup_fallback_language/2,
    lookup_fallback_language/3
]).

-include_lib("../../include/zotonic.hrl").

%% @doc Fetch all translations for the given string.
-spec translations(z:trans() | binary() | string(), z:context()) -> z:trans() | binary().
translations(#trans{ tr = Tr0 } = Trans0, Context) ->
    {en, From} = proplists:lookup(en, Tr0),
    case translations(From, Context) of
        #trans{ tr = Tr1 } ->
            #trans{ tr = merge_trs(Tr0, lists:reverse(Tr1)) };
        _ -> Trans0
    end;
translations(From, Context) when is_binary(From) ->
    try
        case ets:lookup(z_trans_server:table(Context), From) of
            [] ->
    			From;
            [{_, Trans}] ->
    			#trans{ tr = Trans }
        end
    catch
        error:badarg ->
            From
    end;
translations(From, Context) when is_list(From) ->
    translations(unicode:characters_to_binary(From), Context);
translations(From, Context) ->
    translations(z_convert:to_binary(From), Context).

merge_trs([], Acc) ->
    lists:reverse(Acc);
merge_trs([{Lang,_} = LT|Rest], Acc) ->
    case proplists:is_defined(Lang, Acc) of
        true -> merge_trs(Rest, Acc);
        false -> merge_trs(Rest, [LT|Acc])
    end.

%% @doc Prepare a translations table based on all .po files in the active modules.
%%      Returns a map of english sentences with all their translations
-spec parse_translations(z:context()) -> map().
parse_translations(Context) ->
    Mods = z_module_indexer:translations(Context),
    ParsePOFiles = parse_mod_pofiles(Mods, []),
    build_index(ParsePOFiles, #{}).

%% @doc Parse all .po files. Results in a dict {label, [iso_code,trans]}
parse_mod_pofiles([], Acc) ->
    lists:reverse(Acc);
parse_mod_pofiles([{_Module, POFiles}|Rest], Acc) ->
    Acc1 = parse_pofiles(POFiles, Acc),
    parse_mod_pofiles(Rest, Acc1).

parse_pofiles([], Acc) ->
    Acc;
parse_pofiles([{Lang,File}|POFiles], Acc) ->
    parse_pofiles(POFiles, [{Lang, z_gettext:parse_po(File)}|Acc]).

build_index([], Acc) ->
    Acc;
build_index([{Lang, Labels}|Rest], Acc) ->
    build_index(Rest, add_labels(Lang, Labels, Acc)).

add_labels(_Lang, [], Acc) ->
    Acc;
add_labels(Lang, [{header,_}|Rest], Acc) ->
    add_labels(Lang, Rest, Acc);
add_labels(Lang, [{Label,Trans}|Rest], Acc) when is_binary(Trans), is_binary(Label) ->
    case maps:find(Label, Acc) of
        {ok, Ts} ->
            case proplists:is_defined(Lang, Ts) of
                false -> add_labels(Lang, Rest, Acc#{ Label => [{Lang,Trans}|Ts]});
                true -> add_labels(Lang, Rest, Acc)
            end;
        error ->
            add_labels(Lang, Rest, Acc#{ Label => [{Lang,Trans}] })
    end.

%% @doc Strict translation lookup of a language version
-spec lookup(z:trans()|binary()|string(), #context{}) -> binary() | string() | undefined.
lookup(Trans, Context) ->
    lookup(Trans, z_context:language(Context), Context).

-spec lookup(z:trans()|binary()|string(), atom(), #context{}) -> binary() | string() | undefined.
lookup(#trans{ tr = Tr }, Lang, _Context) ->
    proplists:get_value(Lang, Tr);
lookup(Text, Lang, Context) ->
    case z_context:language(Context) of
        Lang -> Text;
        _ -> undefined
    end.

%% @doc Non strict translation lookup of a language version.
%%      In order check: requested language, default configured language, english, any
-spec lookup_fallback(z:trans()|binary()|string()|undefined, z:context()|undefined) -> binary() | string() | undefined.
lookup_fallback(undefined, _Context) ->
    undefined;
lookup_fallback(Trans, undefined) ->
    lookup_fallback(Trans, en, undefined);
lookup_fallback(Trans, Context) ->
    lookup_fallback(Trans, z_context:language(Context), Context).

lookup_fallback(#trans{ tr = Tr }, Lang, Context) ->
    case proplists:get_value(Lang, Tr) of
        undefined ->
            FallbackLang = case Context of
                undefined -> en;
                _ -> z_context:fallback_language(Context)
            end,
            case proplists:get_value(FallbackLang, Tr) of
                undefined ->
                    case z_language:default_language(Context) of
                        undefined -> take_english_or_first(Tr);
                        CfgLang ->
                            case proplists:get_value(z_convert:to_atom(CfgLang), Tr) of
                                undefined -> take_english_or_first(Tr);
                                Text -> Text
                            end
                    end;
                Text ->
                    Text
            end;
        Text ->
            Text
    end;
lookup_fallback(Text, _Lang, _Context) ->
    Text.

take_english_or_first(Tr) ->
    case proplists:get_value(en, Tr) of
        undefined ->
            case Tr of
                [{_,Text}|_] -> Text;
                _ -> undefined
            end;
        EnglishText ->
            EnglishText
    end.

-spec lookup_fallback_language([atom()], z:context()) -> atom().
lookup_fallback_language(Langs, Context) ->
    lookup_fallback_language(Langs, z_context:language(Context), Context).

-spec lookup_fallback_language([atom()], atom(), z:context()) -> atom().
lookup_fallback_language([], Lang, _Context) ->
    Lang;
lookup_fallback_language(Langs, Lang, Context) ->
    case lists:member(Lang, Langs) of
        false ->
            case z_language:default_language(Context) of
                undefined ->
                    case lists:member(en, Langs) of
                        true ->
                            en;
                        false ->
                            case Langs of
                                [] -> Lang;
                                [L|_] -> L
                            end
                    end;
                CfgLang ->
                    CfgLangAtom = z_convert:to_atom(CfgLang),
                    case lists:member(CfgLangAtom, Langs) of
                        false ->
                            case lists:member(en, Langs) of
                                true ->
                                    en;
                                false ->
                                    case Langs of
                                        [] -> Lang;
                                        [L|_] -> L
                                    end
                            end;
                        true ->
                            CfgLangAtom
                    end
            end;
        true ->
            Lang
    end.


%% @doc translate a string or trans record into another language
-spec trans(z:trans() | binary() | string(), z:context() | atom()) -> binary() | undefined.
trans(#trans{ tr = Tr }, Lang) when is_atom(Lang) ->
    proplists:get_value(Lang, Tr);
trans(Text, Lang) when is_atom(Lang) ->
    z_convert:to_binary(Text);
trans(Text, Context) ->
    trans(Text, z_context:language(Context), Context).

trans(#trans{ tr = Tr0 }, Language, Context) ->
    case proplists:lookup(en, Tr0) of
        {en, Text} ->
            case translations(Text, Context) of
                #trans{ tr = Tr } ->
                    case proplists:get_value(Language, Tr) of
                        undefined -> proplists:get_value(Language, Tr0, Text);
                        Translated -> Translated
                    end;
                _ ->
                    proplists:get_value(Language, Tr0, Text)
            end;
        none ->
            proplists:get_value(Language, Tr0)
    end;
trans(Text, Language, Context) ->
    case translations(Text, Context) of
        #trans{ tr = Tr } ->
            proplists:get_value(Language, Tr, Text);
        _ ->
            z_convert:to_binary(Text)
    end.
