%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2009-2020 Marc Worrell
%% @doc Open a dialog with some fields to make a new page/resource.

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

-module(action_admin_dialog_new_rsc).
-author("Marc Worrell <marc@worrell.nl").

%% interface functions
-export([
    render_action/4,
    event/2,

    do_new_page_actions/3
]).

-include_lib("zotonic_core/include/zotonic.hrl").

render_action(TriggerId, TargetId, Args, Context) ->
    Cat = proplists:get_value(cat, Args),
    NoCatSelect = z_convert:to_bool(proplists:get_value(nocatselect, Args, false)),
    TabsEnabled = proplists:get_value(tabs_enabled, Args),
    Title = proplists:get_value(title, Args),
    Redirect = proplists:get_value(redirect, Args, true),
    SubjectId = proplists:get_value(subject_id, Args),
    ObjectId = proplists:get_value(object_id, Args),
    Predicate = proplists:get_value(predicate, Args),
    Callback = proplists:get_value(callback, Args),
    Actions = proplists:get_all_values(action, Args),
    Objects = proplists:get_all_values(object, Args),
    Postback = {new_rsc_dialog, Title, Cat, NoCatSelect, TabsEnabled, Redirect, SubjectId, ObjectId, Predicate, Callback, Actions, Objects},
    {PostbackMsgJS, _PickledPostback} = z_render:make_postback(Postback, click, TriggerId, TargetId, ?MODULE, Context),
    {PostbackMsgJS, Context}.


%% @doc Fill the dialog with the new page form. The form will be posted back to this module.
%% @spec event(Event, Context1) -> Context2
event(#postback{message={new_rsc_dialog, Title, Cat, NoCatSelect, TabsEnabled, Redirect, SubjectId, ObjectId, Predicate, Callback, Actions, Objects}}, Context) ->
    CatId = case Cat of
                undefined -> undefined;
                "" -> undefined;
                "*" -> undefined;
                <<>> -> undefined;
                <<"*">> -> undefined;
                X when is_integer(X) -> X;
                X -> {ok, Id} = m_category:name_to_id(X, Context), Id
            end,
    CatName = case CatId of
        undefined -> z_convert:to_list(?__("page", Context));
        _ -> z_convert:to_list(?__(m_rsc:p(CatId, title, Context), Context))
    end,
    Vars = [
        {delegate, atom_to_list(?MODULE)},
        {redirect, Redirect},
        {subject_id, SubjectId},
        {object_id, ObjectId},
        {predicate, Predicate},
        {title, Title},
        {cat, CatId},
        {nocatselect, NoCatSelect},
        {tabs_enabled, TabsEnabled},
        {catname, CatName},
        {callback, Callback},
        {catname, CatName},
        {actions, Actions},
        {objects, Objects},
        {width, <<"large">>}
    ],
    z_render:dialog(?__("Make a new page", Context), "_action_dialog_new_rsc.tpl", Vars, Context);

event(#submit{message={new_page, Args}}, Context) ->
    Title = case z_context:get_q(<<"new_rsc_title">>, Context) of
        undefined -> z_context:get_q(<<"title">>, Context);
        T -> T
    end,
    BaseProps = get_base_props(Title, Context),
    File = z_context:get_q(<<"upload_file">>, Context),
    Result = case File of
        #upload{filename = OriginalFilename} ->
            BaseProps1 = BaseProps#{
                <<"original_filename">> => OriginalFilename
            },
            m_media:insert_file(File, BaseProps1, Context);
        undefined ->
            m_rsc_update:insert(BaseProps, Context)
    end,
    case Result of
        {ok, Id} ->
            do_new_page_actions(Id, Args, Context);
        {error, Reason} ->
            Msg = error_message(Reason, Context),
            z_render:growl_error(Msg, Context)
    end;

event(#postback{message={admin_connect_select, _Args}} = Postback, Context) ->
    mod_admin:event(Postback, Context).

do_new_page_actions(Id, Args, Context) ->
    Redirect = proplists:get_value(redirect, Args, true),
    SubjectId = z_convert:to_integer(proplists:get_value(subject_id, Args)),
    ObjectId = z_convert:to_integer(proplists:get_value(object_id, Args)),
    Predicate = proplists:get_value(predicate, Args),
    Callback = proplists:get_value(callback, Args),
    Actions = proplists:get_value(actions, Args, []),
    Objects = proplists:get_value(objects, Args, []),

    Callback1 = case dispatch(Redirect) of
        false -> Callback;
        _Dispatch -> undefined
    end,

    % Optionally add an edge from the subject to this new resource
    {_,Context1} = case {is_integer(SubjectId), is_integer(ObjectId)} of
        {true, _} ->
            mod_admin:do_link(SubjectId, Predicate, Id, Callback1, Context);
        {_, true} ->
            mod_admin:do_link(Id, Predicate, ObjectId, Callback1, Context);
        {false, false} when Callback1 =/= undefined ->
            % Call the optional callback
            mod_admin:do_link(undefined, undefined, Id, Callback1, Context);
        {false, false} ->
            {ok, Context}
    end,

    %% Optionally add outgoing edges from this new rsc to the given resources (id / name, predicate pairs)
    maybe_add_objects(Id, Objects, Context),

    % Close the dialog
    Context2a = z_render:wire({dialog_close, []}, Context1),

    % wire any custom actions
    Context2 = z_render:wire([{Action, [{id, Id}|ActionArgs]}|| {Action, ActionArgs} <- Actions], Context2a),

    % optionally redirect to the edit page of the new resource
    case dispatch(Redirect) of
        false ->
            Context2;
        page ->
            z_render:wire({redirect, [{id, Id}]}, Context2);
        Dispatch ->
            Location = z_dispatcher:url_for(Dispatch, [{id, Id}], Context2),
            z_render:wire({redirect, [{location, Location}]}, Context2)
    end.

error_message(duplicate_name, Context) ->
    ?__("There is already a page with this name.", Context);
error_message(eacces, Context) ->
    ?__("You don't have permission to create this page.", Context);
error_message(file_not_allowed, Context) ->
    ?__("You don't have the proper permissions to upload this type of file.", Context);
error_message(download_failed, Context) ->
    ?__("Failed to download the file.", Context);
error_message(infected, Context) ->
    ?__("This file is infected with a virus.", Context);
error_message(av_external_links, Context) ->
    ?__("This file contains links to other files or locations.", Context);
error_message(sizelimit, Context) ->
    ?__("This file is too large.", Context);
error_message(R, Context) ->
    ?LOG_WARNING(#{
        text => <<"Unknown page creation or upload error">>,
        in => zotonic_mod_admin,
        result => error,
        reason => R
    }),
    ?__("Error creating the page.", Context).

maybe_add_objects(Id, Objects, Context) when is_list(Objects) ->
    [{ok, _} = m_edge:insert(Id, Pred, m_rsc:rid(Object, Context), Context) || [Object, Pred] <- Objects];
maybe_add_objects(_Id, undefined, _Context) ->
    ok;
maybe_add_objects(_Id, Objects, _Context) ->
    ?LOG_WARNING(#{
        text => <<"action_admin_dialog_new_rsc: objects are not a list">>,
        in => zotonic_mod_admin,
        objects => Objects
    }),
    ok.

dispatch(undefined) ->
    false;
dispatch("") ->
    false;
dispatch(<<>>) ->
    false;
dispatch(true) ->
    admin_edit_rsc;
dispatch(false) ->
    false;
dispatch(Dispatch) when is_atom(Dispatch) ->
    Dispatch;
dispatch(Dispatch) when is_list(Dispatch) ->
    try
        dispatch(list_to_existing_atom(Dispatch))
    catch
        error:badarg -> false
    end;
dispatch(Dispatch) when is_binary(Dispatch) ->
    try
        dispatch(binary_to_existing_atom(Dispatch, utf8))
    catch
        error:badarg -> false
    end;
dispatch(Cond) ->
    dispatch(z_convert:to_bool(Cond)).


get_base_props(undefined, Context) ->
    lists:foldl(
        fun({Prop,Val}, Acc) ->
            maybe_add_prop(Prop, Val, Acc)
        end,
        #{
            <<"is_published">> => false
        },
        z_context:get_q_all_noz(Context));
get_base_props(NewRscTitle, Context) ->
    Lang = z_context:language(Context),
    Props = lists:foldl(fun({Prop,Val}, Acc) ->
                            maybe_add_prop(Prop, Val, Acc)
                        end,
                        #{
                            <<"is_published">> => false
                        },
                        z_context:get_q_all_noz(Context)),
    Props#{
        <<"title">> => #trans{ tr = [ {Lang, NewRscTitle} ] },
        <<"language">> => [ Lang ]
    }.

maybe_add_prop(_P, #upload{}, Acc) -> Acc;
maybe_add_prop(<<"is_published">>, IsPublished, Acc) ->
    Acc#{
        <<"is_published">> => z_convert:to_bool(IsPublished)
    };
maybe_add_prop(<<"is_dependent">>, IsDependent, Acc) ->
    Acc#{
        <<"is_dependent">> => z_convert:to_bool(IsDependent)
    };
maybe_add_prop(<<"title">>, _, Acc) -> Acc;
maybe_add_prop(<<"new_rsc_title">>, _, Acc) -> Acc;
maybe_add_prop(<<"cat_exclude">>, _V, Acc) -> Acc;
maybe_add_prop(<<"find_category">>, _V, Acc) -> Acc;
maybe_add_prop(<<"*">>, _V, Acc) -> Acc;
maybe_add_prop(_P, undefined, Acc) -> Acc;
maybe_add_prop(<<"category_id">>, Cat, Acc) ->
    Acc#{
        <<"category_id">> => z_convert:to_integer(Cat)
    };
maybe_add_prop(P, V, Acc) ->
    Acc#{
        P => V
    }.
