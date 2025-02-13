%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2009 Marc Worrell
%% Date: 2009-07-02
%% @doc Support for editing predicates in the admin module.  Also hooks into the rsc update function to
%% save the specific fields for predicates

%% Copyright 2009 Marc Worrell
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

-module(mod_admin_predicate).
-author("Marc Worrell <marc@worrell.nl>").

-mod_title("Admin predicate support").
-mod_description("Adds support for editing predicates to the admin.").
-mod_prio(600).
-mod_depends([admin]).
-mod_provides([]).

%% interface functions
-export([
    event/2,
    observe_rsc_update/3,
    observe_rsc_update_done/2,
    observe_rsc_delete/2,
    observe_admin_menu/3,
    observe_search_query/2
]).

-include_lib("zotonic_core/include/zotonic.hrl").
-include_lib("zotonic_mod_admin/include/admin_menu.hrl").
-include_lib("zotonic_mod_wires/include/mod_wires.hrl").

event(#submit{message={delete_move, Args}}, Context) ->
    ToPredId = z_convert:to_integer(z_context:get_q_validated(<<"predicate_id">>, Context)),
    {id, PredId} = proplists:lookup(id, Args),
    case z_acl:rsc_deletable(PredId, Context) of
        true ->
            {ok, ToPredName} = m_predicate:id_to_name(ToPredId, Context),
            case z_acl:is_allowed(insert, #acl_edge{subject_id=PredId, predicate=ToPredName, object_id=PredId}, Context) of
                true ->
                    Context1 = z_context:prune_for_async(Context),
                    spawn(fun() ->
                            pred_move_and_delete(PredId, ToPredId, Context1)
                          end),
                    z_render:wire({dialog_close, []}, Context);
                false ->
                    z_render:growl(?__("Sorry, you are not allowed to insert connections with this predicate.", Context), Context)
            end;
        false ->
            z_render:growl(?__("Sorry, you are not allowed to delete this.", Context), Context)
    end;
event(#postback{message={delete_all, Args}}, Context) ->
    {id, PredId} = proplists:lookup(id, Args),
    IfEmpty = proplists:get_value(if_empty, Args, false),
    case not IfEmpty orelse not m_predicate:is_used(PredId, Context) of
        true ->
            case z_acl:rsc_deletable(PredId, Context)  of
                true ->
                    Context1 = z_context:prune_for_async(Context),
                    spawn(fun() ->
                            pred_delete(PredId, Context1)
                          end),
                    z_render:wire({dialog_close, []}, Context);
                false ->
                    z_render:growl(?__("Sorry, you are not allowed to delete this.", Context), Context)
            end;
        false ->
            z_render:wire({alert, [{message, ?__("Delete is canceled, there are connections with this predicate.", Context)}]}, Context)
    end.

page_actions(Actions, Context) ->
    z_notifier:first(#page_actions{ actions = Actions }, Context).

pred_delete(Id, Context) ->
    page_actions({mask, [{message, ?__("Deleting...", Context)}]}, Context),
    z_db:q("delete from edge where predicate_id = $1", [Id], Context, 120000),
    _ = m_rsc:delete(Id, Context),
    page_actions({unmask, []}, Context).

pred_move_and_delete(FromPredId, ToPredId, Context) ->
    page_actions({mask, [{message, ?__("Deleting...", Context)}]}, Context),
    Edges = z_db:q("select a.id
                    from edge a
                            left join edge b
                            on  a.subject_id = b.subject_id
                            and a.object_id = b.object_id
                            and b.predicate_id = $2
                    where a.predicate_id = $1
                      and b.id is null",
                   [FromPredId, ToPredId],
                   Context,
                   120000),
    Edges1 = [ EdgeId || {EdgeId} <- Edges ],
    pred_move(Edges1, ToPredId, 0, length(Edges), Context),
    z_db:q("delete from edge where predicate_id = $1", [FromPredId], Context, 120000),
    _ = m_rsc:delete(FromPredId, Context),
    page_actions({unmask, []}, Context).

pred_move([], _ToPredId, _Ct, _N, _Context) ->
    ok;
pred_move(EdgeIds, ToPredId, Ct, N, Context) ->
    {UpdIds, RestIds} = take(EdgeIds, 100),
    z_db:q("update edge
            set predicate_id = $1
            where id in (SELECT(unnest($2::int[])))",
           [ToPredId, UpdIds],
           Context,
           120000),
    Ct1 = Ct + length(UpdIds),
    maybe_progress(Ct, Ct1, N, Context),
    pred_move(RestIds, ToPredId, Ct1, N, Context).

maybe_progress(_N1, _N2, 0, _Context) ->
    ok;
maybe_progress(N1, N2, Total, Context) ->
    z_pivot_rsc:pivot_delay(Context),
    PerStep = Total / 100,
    S1 = round(N1 / PerStep),
    S2 = round(N2 / PerStep),
    case S1 of
        S2 -> ok;
        _ -> page_actions({mask_progress, [{percent,S2}]}, Context)
    end.


take(L, N) ->
    take(L, N, []).

take([], _N, Acc) ->
    {Acc, []};
take(L, 0, Acc) ->
    {Acc, L};
take([Id|L], N, Acc) ->
    take(L, N-1, [Id|Acc]).

%% @doc Check if the update contains information for a predicate.  If so then update
%% the predicate information in the db and remove it from the update props.
observe_rsc_update(#rsc_update{id=Id}, {ok, Props}, Context) ->
    case       maps:is_key(<<"predicate_subject_list">>, Props)
        orelse maps:is_key(<<"predicate_object_list">>, Props) of

        true ->
            Subjects = maps:get(<<"predicate_subject_list">>, Props, []),
            Objects  = maps:get(<<"predicate_object_list">>, Props, []),
            m_predicate:update_noflush(Id, Subjects, Objects, Context),

            Props1 = maps:without([
                    <<"predicate_subject_list">>,
                    <<"predicate_object_list">>
                ], Props),
            {ok, Props1};
        false ->
            {ok, Props}
    end;
observe_rsc_update(#rsc_update{}, {error, _} = Error, _Context) ->
    Error.

%% @doc Whenever a predicate has been updated we have to flush the predicate cache.
observe_rsc_update_done(#rsc_update_done{pre_is_a=BeforeCatList, post_is_a=CatList}, Context) ->
    case lists:member(predicate, CatList) orelse lists:member(predicate, BeforeCatList) of
        true -> m_predicate:flush(Context);
        false -> ok
    end.

%% @doc Do not allow a predicate to be removed iff there are edges with that predicate
observe_rsc_delete(#rsc_delete{id=Id, is_a=IsA}, Context) ->
    case lists:member(predicate, IsA) of
        true ->
            case m_predicate:is_used(Id, Context) of
                true -> throw({error, is_used});
                false -> ok
            end;
        false ->
            ok
    end.


observe_admin_menu(#admin_menu{}, Acc, Context) ->
    [
     #menu_item{id = admin_predicate,
                parent = admin_structure,
                label = ?__("Predicates", Context),
                url = admin_predicate,
                visiblecheck = {acl, use, mod_admin_predicate}},
     #menu_item{id = admin_edges,
                parent = admin_content,
                label = ?__("Page connections", Context),
                url = admin_edges,
                sort = 3}
     |Acc].

observe_search_query(#search_query{ search={edges, Args} }, Context) ->
    PredId = rid(predicate, Args, Context),
    SubjectId = rid(hassubject, Args, Context),
    ObjectId = rid(hasobject, Args, Context),
    search_query(SubjectId, PredId, ObjectId);
observe_search_query(_, _Context) ->
    undefined.

rid(P, Args, Context) ->
    m_rsc:rid(map_empty(proplists:get_value(P, Args)), Context).

search_query(SubjectId, PredId, ObjectId) ->
    {W1, A1} = maybe_add("e.predicate_id ", PredId, [], []),
    {W2, A2} = maybe_add("e.subject_id ", SubjectId, W1, A1),
    {W3, A3} = maybe_add("e.object_id ", ObjectId, W2, A2),
    #search_sql{
        select="e.id, e.subject_id, e.predicate_id, e.object_id, e.creator_id, e.created",
        from="edge e join rsc s on s.id = e.subject_id join rsc o on o.id = e.object_id",
        order="e.id desc",
        where=W3,
        args=A3,
        tables=[{rsc,"o"}, {rsc,"s"}],
        assoc=true
    }.

maybe_add(_, undefined, Where, As) ->
    {Where, As};
maybe_add(Clause, V, Where, As) ->
    As1 = As ++ [ V ],
    W = Clause ++ " = $"++integer_to_list(length(As1)),
    {append_where(Where, W), As1}.
append_where("", W) ->
    W;
append_where(Ws, W) ->
    Ws ++ " and " ++ W.
map_empty(<<>>) -> undefined;
map_empty("") -> undefined;
map_empty(null) -> undefined;
map_empty(false) -> undefined;
map_empty(A) -> A.
